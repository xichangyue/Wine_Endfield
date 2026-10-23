import AppKit
import Darwin

private let manager = FileManager.default
private let markerName = ".endfield-installer-v1"
private let acceptedLaunchModes = ["Launcher", "Vulkan", "DirectX11", "Update"]

func installFailureSummary(log: URL, exitCode: Int32) -> String {
    let data: Data
    do {
        let handle = try FileHandle(forReadingFrom: log)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let limit: UInt64 = 64 * 1024
        try handle.seek(toOffset: size > limit ? size - limit : 0)
        data = try handle.read(upToCount: Int(limit)) ?? Data()
    } catch {
        return "未能读取安装日志（退出码 \(exitCode)）。请保留下面的日志路径供排查。"
    }
    let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    func relevant(_ line: String) -> Bool {
        !["系统信息：", "安装器版本：", "正在", "安装未完成，原有运行环境已保留或恢复", "安装诊断结束。"]
            .contains(where: line.hasPrefix)
    }
    var selected: [String]
    if let start = lines.lastIndex(where: { $0.hasPrefix("安装失败阶段：") }) {
        let end = lines[(start + 1)...].firstIndex(of: "安装诊断结束。") ?? lines.endIndex
        // Preflight errors are printed just before the diagnostic block;
        // subprocess failures additionally include their own log inside it.
        let preceding = lines[..<start].filter(relevant).suffix(3)
        selected = [lines[start]] + preceding + lines[(start + 1)..<end].filter(relevant)
        if end < lines.endIndex {
            selected += lines[(end + 1)...].filter(relevant).suffix(2)
        }
    } else {
        selected = Array(lines.filter(relevant).suffix(10))
    }
    guard !selected.isEmpty else {
        return "安装过程未写入错误详情（退出码 \(exitCode)）。请保留完整日志供排查。"
    }
    // Keep the failure stage and context, plus the final subprocess output.
    if selected.count > 10 { selected = Array(selected.prefix(5)) + ["…（更多内容见完整日志）"] + selected.suffix(4) }
    return selected.map { $0.count > 160 ? String($0.prefix(160)) + "…" : $0 }.joined(separator: "\n")
}

func cleanEnvironment() -> [String: String] {
    ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
     "TMPDIR": NSTemporaryDirectory(), "LANG": "zh_CN.UTF-8"]
}

func failure(_ detail: String) -> NSError {
    NSError(domain: "WineEndfield", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
}

func alert(_ title: String, _ detail: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = detail
    a.addButton(withTitle: "好")
    NSApp.activate(ignoringOtherApps: true)
    a.runModal()
}

func process(_ script: String, _ arguments: [String]) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script] + arguments
    p.environment = cleanEnvironment()
    p.standardInput = FileHandle.nullDevice
    return p
}

// The shell entry points and older installed apps share this advisory lock.
// Only setup.sh creates the installation directory, after validating the target.
func acquire(_ root: String) throws -> Int32 {
    var directory = stat()
    guard lstat(root, &directory) == 0,
          (directory.st_mode & S_IFMT) == S_IFDIR else {
        throw failure("安装目录不存在或是符号链接。请先连接外置磁盘，或选择正确的安装目录。")
    }
    let fd = open(root + "/.session.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw failure("无法打开运行锁，请检查安装目录权限；运行锁不能是符号链接。") }
    var info = stat()
    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
        close(fd)
        throw failure("运行锁不是普通文件，请检查安装目录。")
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        throw failure("当前有安装、游戏或更新任务，请先正常退出后重试。")
    }
    return fd
}

func runWithLock(_ arguments: [String]) -> Int32 {
    guard arguments.count >= 4 else {
        fputs("用法：EndfieldInstaller --with-lock ROOT SCRIPT [ARGS...]\n", stderr)
        return 2
    }
    do {
        let fd = try acquire(arguments[2])
        defer { close(fd) }
        let p = process(arguments[3], Array(arguments.dropFirst(4)))
        p.environment?["ENDFIELD_LOCK_HELD"] = "1"
        try p.run()
        p.waitUntilExit()
        return p.terminationReason == .uncaughtSignal ? 128 + p.terminationStatus : p.terminationStatus
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        return 1
    }
}

func isManaged(_ root: URL) -> Bool {
    manager.fileExists(atPath: root.appendingPathComponent(markerName).path)
}

func installRoot(bundle: Bundle = .main) throws -> URL {
    // The app travels inside ROOT/Apps. Prefer its current location over the
    // original InstallRoot, which can change when a drive is remounted or moved.
    let apps = bundle.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent()
    if apps.lastPathComponent == "Apps" {
        let relativeRoot = apps.deletingLastPathComponent()
        if isManaged(relativeRoot) {
            guard manager.fileExists(atPath: relativeRoot.appendingPathComponent("run.sh").path) else {
                throw failure("此安装目录缺少运行入口。请重新打开安装器，选择同一目录进行修复；游戏与本次采用的用户环境会保留。")
            }
            return relativeRoot
        }
    }
    if let original = bundle.object(forInfoDictionaryKey: "InstallRoot") as? String {
        let root = URL(fileURLWithPath: original).standardizedFileURL
        if isManaged(root), manager.fileExists(atPath: root.appendingPathComponent("run.sh").path) {
            return root
        }
    }
    throw failure("找不到此应用的安装目录。若安装在外置磁盘，请先连接磁盘，再从安装目录的 Apps/终末地.app 打开。整体移动安装目录后也可从该入口启动，或运行安装器恢复桌面入口。")
}

func expandedPath(_ text: String) -> String {
    (text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
}

func aliasTarget(_ file: URL) -> URL? {
    if let symlink = try? manager.destinationOfSymbolicLink(atPath: file.path) {
        return URL(fileURLWithPath: symlink, relativeTo: file.deletingLastPathComponent()).standardizedFileURL
    }
    guard let data = try? URL.bookmarkData(withContentsOf: file) else { return nil }
    var stale = false
    return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                    relativeTo: nil, bookmarkDataIsStale: &stale)
}

func createDesktopEntry(root: URL) throws -> [String] {
    let desktop = try manager.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    let application = root.appendingPathComponent("Apps/终末地.app")
    guard manager.fileExists(atPath: application.path) else {
        throw failure("安装目录中缺少 Apps/终末地.app。")
    }
    let bookmark = try application.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
    let link = desktop.appendingPathComponent("终末地.app")
    if manager.fileExists(atPath: link.path) || (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil {
        guard let target = aliasTarget(link), target.standardizedFileURL == application.standardizedFileURL else {
            return ["桌面已有其他同名入口，未覆盖。请使用安装目录 Apps/终末地.app。"]
        }
        try manager.removeItem(at: link)
    }
    try URL.writeBookmarkData(bookmark, to: link)
    return []
}

final class Installer: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let exe = NSTextField(string: "")
    let destination = NSTextField(string: NSHomeDirectory() + "/Games/Wine Endfield")
    let desktop = NSButton(checkboxWithTitle: "在桌面创建“终末地”入口", target: nil, action: nil)
    let destinationNote = NSTextField(wrappingLabelWithString: "")
    let sourceNote = NSTextField(wrappingLabelWithString: "")
    let status = NSTextField(wrappingLabelWithString: "准备就绪。请确认安装目录后继续。")
    let progress = NSProgressIndicator()
    let start = NSButton(title: "安装环境", target: nil, action: nil)
    let revealLog = NSButton(title: "查看日志", target: nil, action: nil)
    var controls: [NSControl] = []
    var busy = false
    var worker: Process?
    var lastLog: URL?

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出安装器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "终末地 · Mac 安装器"
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        func label(_ text: String, bold: Bool = false, secondary: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = bold ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 12)
            if secondary { field.textColor = .secondaryLabelColor }
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return field
        }
        let title = label("安装或更新终末地运行环境", bold: true)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        _ = label("一个入口，两种渲染方式。游戏通过官方启动器下载、更新和启动。", secondary: true)
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)

        _ = label("1. 安装目录", bold: true)
        destination.placeholderString = "完整路径，例如 /Volumes/游戏硬盘/终末地"
        destination.delegate = self
        let folder = NSButton(title: "选择目录…", target: self, action: #selector(pickFolder))
        pathRow(destination, button: folder, in: stack)
        destinationNote.font = .systemFont(ofSize: 12)
        destinationNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(destinationNote)
        destinationNote.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        _ = label("这里就是最终安装目录，不会再追加子目录。外置磁盘请使用 APFS 或 Mac OS 扩展格式。", secondary: true)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        _ = label("2. 官方 Windows 启动器安装包", bold: true)
        exe.placeholderString = "选择官网下载的 HypergryphLauncher_*.exe"
        let choose = NSButton(title: "选择 EXE…", target: self, action: #selector(pickEXE))
        pathRow(exe, button: choose, in: stack)
        sourceNote.font = .systemFont(ofSize: 12)
        sourceNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(sourceNote)
        sourceNote.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(20, after: sourceNote)

        desktop.state = .on
        stack.addArrangedSubview(desktop)
        _ = label("在官方启动器点击“开始游戏”：\n未勾选“DirectX 11 启动”使用 Vulkan；勾选后使用 DirectX 11 / DXMT。", secondary: true)
        _ = label("需要 Apple Silicon、macOS 26 或更新版本、Rosetta 2。安装器不会代你接受官方协议。", secondary: true)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)

        start.target = self
        start.action = #selector(install)
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        revealLog.target = self
        revealLog.action = #selector(showLog)
        revealLog.isHidden = true
        let actions = NSStackView(views: [start, revealLog])
        actions.orientation = .horizontal
        actions.spacing = 12
        stack.addArrangedSubview(actions)
        progress.style = .bar
        progress.isIndeterminate = true
        stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12)
        status.maximumNumberOfLines = 3
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        controls = [choose, folder, exe, destination, desktop, start]
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -22)
        ])
        refreshDestination()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func pathRow(_ field: NSTextField, button: NSButton, in stack: NSStackView) {
        let row = NSStackView(views: [field, button])
        row.orientation = .horizontal
        row.spacing = 10
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func refreshDestination() {
        let root = URL(fileURLWithPath: expandedPath(destination.stringValue))
        if isManaged(root) {
            destinationNote.stringValue = "已识别旧版安装：保留游戏并迁移采用的用户环境；成功后自动删除其他旧设置、缓存和运行库备份。"
            start.title = "更新环境并打开官方启动器"
        } else {
            destinationNote.stringValue = "新安装：请选择空目录或尚未创建的目录。升级 v0.2 / v0.3 时，请选择原安装目录。"
            start.title = "安装环境并打开官方启动器"
        }
        let launcherExists = isManaged(root) && manager.fileExists(atPath: root.appendingPathComponent("Launcher/Launcher.exe").path)
        sourceNote.stringValue = launcherExists
            ? "已找到官方启动器，本次更新可留空，无需重新下载 EXE。"
            : "新安装或缺少官方启动器时需要 EXE。请选择安装包，不是已安装的 Launcher.exe。"
    }

    func controlTextDidChange(_ obj: Notification) { if !busy { refreshDestination() } }

    @objc func pickEXE() {
        let p = NSOpenPanel()
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.allowsMultipleSelection = false
        p.message = "选择从游戏官网下载的 HypergryphLauncher_*.exe 安装包。"
        if p.runModal() == .OK, let u = p.url {
            guard u.pathExtension.lowercased() == "exe" else { alert("文件类型不符", "请选择 Windows EXE 安装包。"); return }
            exe.stringValue = u.path
        }
    }

    @objc func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "使用此目录"
        p.message = "选择最终安装目录。升级请选择原目录；新安装可在这里新建空文件夹。不会自动追加子目录。"
        let current = expandedPath(destination.stringValue)
        if manager.fileExists(atPath: current) { p.directoryURL = URL(fileURLWithPath: current) }
        if p.runModal() == .OK, let u = p.url {
            destination.stringValue = u.path
            refreshDestination()
        }
    }

    @objc func install() {
        guard !busy else { return }
        let root = expandedPath(destination.stringValue)
        guard root.hasPrefix("/"), root != "/", !root.contains("\n"), !root.contains("\r") else {
            alert("安装路径无效", "请提供最终安装目录的完整路径，或使用“选择目录”。")
            return
        }
        let official = expandedPath(exe.stringValue)
        let existingLauncher = isManaged(URL(fileURLWithPath: root)) && manager.fileExists(atPath: root + "/Launcher/Launcher.exe")
        if !existingLauncher && official.isEmpty {
            alert("请选择官方安装包", "此目录尚无官方启动器，请选择从官网下载的 Windows EXE 安装包。")
            return
        }
        if !official.isEmpty && (!official.lowercased().hasSuffix(".exe") || !manager.isReadableFile(atPath: official)) {
            alert("官方安装包不可读取", "请选择 Windows EXE 安装包，或粘贴不带引号的完整路径。已有官方启动器时可以留空。")
            return
        }
        do {
            guard let resources = Bundle.main.resourceURL else { throw failure("安装器资源不完整。") }
            let logDirectory = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs/Wine Endfield Installer", isDirectory: true)
            try manager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let log = logDirectory.appendingPathComponent("installer-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).log")
            guard manager.createFile(atPath: log.path, contents: nil) else { throw failure("无法创建安装日志。") }
            let logHandle = try FileHandle(forWritingTo: log)
            let p = process(resources.appendingPathComponent("setup.sh").path, [resources.path, root, official])
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            let outputLock = NSLock()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                outputLock.lock()
                defer { outputLock.unlock() }
                let data = h.availableData
                guard !data.isEmpty else { h.readabilityHandler = nil; return }
                logHandle.write(data)
                let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
                guard let last = lines.last else { return }
                DispatchQueue.main.async { self?.status.stringValue = String(last.suffix(240)) }
            }
            p.terminationHandler = { [weak self] task in
                pipe.fileHandleForReading.readabilityHandler = nil
                outputLock.lock()
                logHandle.write(pipe.fileHandleForReading.readDataToEndOfFile())
                try? logHandle.close()
                outputLock.unlock()
                DispatchQueue.main.async {
                    self?.finished(task.terminationStatus, URL(fileURLWithPath: root), log)
                }
            }
            lastLog = log
            revealLog.isHidden = false
            setBusy(true)
            status.stringValue = "正在检查安装目录与资源。升级会迁移用户环境，成功后自动清理旧版本；请勿拔出磁盘……"
            worker = p
            try p.run()
        } catch {
            worker = nil
            setBusy(false)
            status.stringValue = "安装尚未开始。"
            alert("无法开始安装", error.localizedDescription)
        }
    }

    func setBusy(_ value: Bool) {
        busy = value
        controls.forEach { $0.isEnabled = !value }
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    func finished(_ code: Int32, _ root: URL, _ log: URL) {
        worker = nil
        setBusy(false)
        refreshDestination()
        guard code == 0 else {
            let summary = installFailureSummary(log: log, exitCode: code)
            status.stringValue = String(summary.split(separator: "\n").first ?? "安装未完成（\(code)）。")
            alert("安装未完成", summary + "\n\n请点击“查看日志”查看完整内容，排除原因后可在同一目录重试。\n\n完整日志：\(log.path)")
            return
        }
        var warnings: [String] = []
        let cleanupLog = root.appendingPathComponent("logs/installer-cleanup.log")
        let cleanup = try? String(contentsOf: cleanupLog, encoding: .utf8)
        let installation = try? String(contentsOf: log, encoding: .utf8)
        if cleanup?.contains("清理提醒：") == true || installation?.contains("清理提醒：") == true {
            warnings.append("部分旧内容已保留或清理未完成。请点击“查看日志”了解详情。")
        } else if cleanup == nil {
            warnings.append("未能读取旧版本清理日志，部分旧文件可能尚未清理。")
        }
        if desktop.state == .on {
            do { warnings += try createDesktopEntry(root: root) }
            catch { warnings.append("桌面入口创建失败：\(error.localizedDescription)") }
        }
        status.stringValue = "环境已就绪。官方启动器负责游戏下载、更新与启动。"
        let detail = "接下来打开官方启动器。首次安装请自行确认协议，在默认位置或 C:\\Endfield 下载游戏，再点击“开始游戏”。\n\n未勾选“DirectX 11 启动”使用 Vulkan；勾选后使用 DirectX 11 / DXMT。\n\n入口保存在：\(root.path)/Apps/终末地.app\n外置磁盘需保持连接。整体搬动安装目录后，可直接打开上述 Apps 内的入口。"
        alert("环境已就绪", detail + (warnings.isEmpty ? "" : "\n\n" + warnings.joined(separator: "\n")))
        NSWorkspace.shared.open(root.appendingPathComponent("Apps/终末地.app"))
    }

    @objc func showLog() {
        if let log = lastLog { NSWorkspace.shared.activateFileViewerSelecting([log]) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Locking is a non-UI command, so setup/run can use it without creating an app.
if CommandLine.arguments.dropFirst().first == "--with-lock" {
    exit(runWithLock(CommandLine.arguments))
}

if let mode = Bundle.main.object(forInfoDictionaryKey: "LaunchMode") as? String {
    do {
        guard acceptedLaunchModes.contains(mode) else { throw failure("此快捷方式的启动模式无效，请使用安装器更新入口。") }
        let root = try installRoot()
        if CommandLine.arguments.contains("--check") {
            print("Launcher: \(root.path)")
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let log = root.appendingPathComponent("logs/shortcut.log")
        guard manager.createFile(atPath: log.path, contents: nil) else { throw failure("无法写入运行日志，请检查安装目录权限。") }
        let h = try FileHandle(forWritingTo: log)
        defer { try? h.close() }
        let p = process(root.appendingPathComponent("run.sh").path, ["Launcher"])
        p.standardOutput = h
        p.standardError = h
        try p.run()
        while p.isRunning {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.2), inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            app.updateWindows()
        }
        if p.terminationStatus != 0 {
            alert("未能正常启动", "请先正常退出其他 Wine 游戏与启动器，再重试。详细原因见日志：\n\(log.path)")
        }
    } catch {
        if CommandLine.arguments.contains("--check") {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        alert("无法启动", error.localizedDescription)
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = Installer()
    app.delegate = delegate
    app.run()
}
