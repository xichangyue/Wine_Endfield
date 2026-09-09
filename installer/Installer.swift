import AppKit
import Darwin

func cleanEnvironment() -> [String: String] {
    ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
     "TMPDIR": NSTemporaryDirectory(), "LANG": "zh_CN.UTF-8"]
}
func alert(_ title: String, _ detail: String) {
    let a = NSAlert(); a.messageText = title; a.informativeText = detail
    a.addButton(withTitle: "好"); NSApp.activate(ignoringOtherApps: true); a.runModal()
}
func acquire(_ root: String) throws -> Int32 {
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    let fd = open(root + "/.session.lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw NSError(domain: "WineEndfield", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建运行锁，请检查安装目录权限。"]) }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd); throw NSError(domain: "WineEndfield", code: 2, userInfo: [NSLocalizedDescriptionKey: "当前有安装、游戏或更新任务，请先正常退出。"])
    }
    return fd
}
func process(_ script: String, _ arguments: [String]) -> Process {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script] + arguments; p.environment = cleanEnvironment()
    p.standardInput = FileHandle.nullDevice
    return p
}

final class Installer: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let exe = NSTextField(string: "")
    let destination = NSTextField(string: NSHomeDirectory() + "/Games/Wine Endfield")
    let vulkan = NSButton(checkboxWithTitle: "Vulkan（首次游玩需要缓存预热）", target: nil, action: nil)
    let dx11 = NSButton(checkboxWithTitle: "DirectX 11（DXMT）", target: nil, action: nil)
    let desktop = NSButton(checkboxWithTitle: "在桌面创建所选版本及更新入口", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "只配置运行环境；游戏下载和校验由官方启动器完成。")
    let progress = NSProgressIndicator()
    var controls: [NSControl] = []
    var official: String?
    var busy = false
    var worker: Process?
    var lockFD: Int32 = -1
    var logHandle: FileHandle?

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出安装器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 490),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "终末地 · Mac 安装器（实验版）"; window.delegate = self
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading
        stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        func label(_ text: String) { stack.addArrangedSubview(NSTextField(wrappingLabelWithString: text)) }
        label("1. 提供官方启动器 EXE（已验证 1.5.0 安装包）")
        exe.placeholderString = "选择文件，或粘贴官方安装器的完整路径"
        exe.widthAnchor.constraint(equalToConstant: 560).isActive = true
        destination.widthAnchor.constraint(equalToConstant: 560).isActive = true
        stack.addArrangedSubview(exe)
        let choose = NSButton(title: "选择官方安装包…", target: self, action: #selector(pickEXE))
        stack.addArrangedSubview(choose)
        label("2. 选择安装位置（两种模式共用一份游戏）")
        stack.addArrangedSubview(destination)
        let folder = NSButton(title: "选择安装位置…", target: self, action: #selector(pickFolder))
        stack.addArrangedSubview(folder)
        vulkan.state = .on; dx11.state = .on; desktop.state = .on
        stack.addArrangedSubview(vulkan); stack.addArrangedSubview(dx11); stack.addArrangedSubview(desktop)
        label("需要 Apple Silicon 和 Rosetta 2。不会自动接受官方协议。\n请通过本项目快捷方式游玩，不使用官方“开始游戏”按钮。")
        let start = NSButton(title: "安装环境并打开官方启动器", target: self, action: #selector(install))
        start.bezelStyle = .rounded; stack.addArrangedSubview(start)
        progress.style = .bar; progress.isIndeterminate = true
        progress.widthAnchor.constraint(equalToConstant: 560).isActive = true
        stack.addArrangedSubview(progress); stack.addArrangedSubview(status)
        controls = [choose, folder, exe, destination, vulkan, dx11, desktop, start]
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20)])
        window.setContentSize(NSSize(width: 620, height: 610))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func pickEXE() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.message = "选择从游戏官网下载的 HypergryphLauncher_*.exe，不是已经安装的 Launcher.exe。"
        if p.runModal() == .OK, let u = p.url {
            guard u.pathExtension.lowercased() == "exe" else { alert("文件类型不符", "请选择 Windows EXE 安装器。"); return }
            official = u.path; exe.stringValue = u.path
        }
    }
    @objc func pickFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.canCreateDirectories = true; p.message = "选择父目录，将在其中建立 Wine Endfield 文件夹。"
        if p.runModal() == .OK, let u = p.url { destination.stringValue = u.appendingPathComponent("Wine Endfield").path }
    }
    @objc func install() {
        let official = (exe.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard official.lowercased().hasSuffix(".exe"), FileManager.default.fileExists(atPath: official) else {
            alert("请选择官方安装器", "请选择文件，或粘贴官方 EXE 的完整路径，不要添加引号。"); return
        }
        let modes = [("Vulkan", vulkan.state), ("DirectX11", dx11.state)].filter { $0.1 == .on }.map { $0.0 }
        guard !modes.isEmpty else { alert("请选择渲染方式", "至少选择一种。"); return }
        let root = (destination.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard root.hasPrefix("/"), root != "/" else { alert("安装路径无效", "请提供新的安装文件夹完整路径。"); return }
        let fm = FileManager.default
        if fm.fileExists(atPath: root) && !fm.fileExists(atPath: root + "/.endfield-installer-v1") {
            alert("安装目录已有文件", "请选择其他位置；不会覆盖已有目录。"); return
        }
        do {
            // Mark ownership before acquiring the per-installation lock (which creates the directory).
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: root + "/.endfield-installer-v1") {
                fm.createFile(atPath: root + "/.endfield-installer-v1", contents: Data())
            }
            lockFD = try acquire(root)
            try fm.createDirectory(atPath: root + "/logs", withIntermediateDirectories: true)
            let log = root + "/logs/installer-\(Int(Date().timeIntervalSince1970)).log"
            fm.createFile(atPath: log, contents: nil); logHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
            let resources = Bundle.main.resourceURL!.path
            let p = process(resources + "/setup.sh", [resources, root, official, modes.joined(separator: ",")])
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else { h.readabilityHandler = nil; return }
                self?.logHandle?.write(data)
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { self?.status.stringValue = String(message.suffix(500)) }
            }
            p.terminationHandler = { [weak self] task in
                DispatchQueue.main.async { self?.finished(task.terminationStatus, root, log) }
            }
            busy = true; controls.forEach { $0.isEnabled = false }; progress.startAnimation(nil)
            status.stringValue = "正在准备运行环境，请勿关闭安装器……"; worker = p; try p.run()
        } catch {
            busy = false; controls.forEach { $0.isEnabled = true }; progress.stopAnimation(nil)
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            alert("无法安装", error.localizedDescription)
        }
    }
    func finished(_ code: Int32, _ root: String, _ log: String) {
        busy = false; worker = nil; controls.forEach { $0.isEnabled = true }; progress.stopAnimation(nil)
        if lockFD >= 0 { close(lockFD); lockFD = -1 }
        guard code == 0 else {
            status.stringValue = "配置失败（\(code)）。日志：\(log)"
            alert("安装未完成", "可在相同目录重试。请保留日志：\n\(log)"); return
        }
        var warnings: [String] = []
        if desktop.state == .on {
            do {
                let apps = try FileManager.default.contentsOfDirectory(atPath: root + "/Apps").filter { $0.hasSuffix(".app") }
                let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                for name in apps {
                    let link = dir.appendingPathComponent(name).path
                    if FileManager.default.fileExists(atPath: link) {
                        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != root + "/Apps/" + name {
                            warnings.append("桌面同名入口已存在，未覆盖：\(name)")
                        }
                        continue
                    }
                    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: root + "/Apps/" + name)
                }
            } catch { warnings.append("桌面快捷方式创建失败：\(error.localizedDescription)") }
        }
        status.stringValue = "环境安装完成。游戏仍需通过官方启动器下载和校验。"
        alert("环境已就绪", "接下来将打开官方启动器。请保留默认游戏安装路径（也可选 C:\\Endfield），自行确认协议并下载。\n完成后退出官方启动器，从桌面对应版本启动。\n\n应用入口也保存在：\(root)/Apps\n" + warnings.joined(separator: "\n"))
        NSWorkspace.shared.open(URL(fileURLWithPath: root + "/Apps/终末地 更新与修复.app"))
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
if let root = Bundle.main.object(forInfoDictionaryKey: "InstallRoot") as? String,
   let mode = Bundle.main.object(forInfoDictionaryKey: "LaunchMode") as? String {
    if CommandLine.arguments.contains("--check") {
        guard FileManager.default.fileExists(atPath: root + "/run.sh"), ["Vulkan", "DirectX11", "Update"].contains(mode) else { exit(1) }
        print("\(mode): \(root)"); exit(0)
    }
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    do {
        let fd = try acquire(root); defer { close(fd) }
        if mode == "Update" {
            alert("官方启动器仅用于安装、更新与校验", "请保留默认安装路径或选择 C:\\Endfield。完成后退出启动器，从 Vulkan/DX11 快捷方式游玩，不要点击官方“开始游戏”。")
        }
        let log = root + "/logs/run-\(mode)-\(Int(Date().timeIntervalSince1970)).log"
        FileManager.default.createFile(atPath: log, contents: nil)
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: log)); defer { try? h.close() }
        let p = process(root + "/run.sh", [mode]); p.standardOutput = h; p.standardError = h
        try p.run()
        // Keep AppKit responsive while the Wine child (including launcher helpers) runs.
        while p.isRunning {
            if let event = app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.2), inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            app.updateWindows()
        }
        if p.terminationStatus != 0 {
            alert("未能正常运行", "如果尚未完成游戏下载，请先使用更新入口。否则请查看日志：\n\(log)")
        }
    } catch { alert("无法启动", error.localizedDescription) }
} else {
    app.setActivationPolicy(.regular)
    let delegate = Installer(); app.delegate = delegate; app.run()
}
