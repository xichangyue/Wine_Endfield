#!/usr/bin/env python3
"""Exercise the production installer with a tiny, non-Wine synthetic runtime.

Only temporary test installations are changed. No actual Wine process, official
launcher, account, game, desktop shortcut, or /Applications entry is launched.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import time


REPO = Path(__file__).resolve().parents[2]
VERSION = "v0.4.0-synthetic"
FROZEN_DLL_OVERRIDE = "d3d11,dxgi,winemetal=b;vulkan-1,winevulkan=b"
FAKE_WINE = r'''#!/bin/bash
set -eu
# This file is a test double, never the real Wine executable.
mkdir -p "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/dosdevices"
[ -L "$WINEPREFIX/dosdevices/c:" ] || ln -s '../drive_c' "$WINEPREFIX/dosdevices/c:"
printf '%s\t' "$(basename "$0")" "$@" >> "$WINEPREFIX/.synthetic-calls"
printf '\n' >> "$WINEPREFIX/.synthetic-calls"
printf '%s\t%s\t%s\n' "$(basename "$0")" "${1:-}" "${WINEDLLOVERRIDES:-}" >> "$WINEPREFIX/.synthetic-environment.tsv"
if [ -f "$(dirname "$0")/.fail-prepare" ]; then
  echo 'synthetic Wine initialization failure' >&2
  exit 42
fi
if [ ! -e "$WINEPREFIX/system.reg" ]; then
  printf 'WINE REGISTRY Version 2\n' > "$WINEPREFIX/system.reg"
fi
case "${1:-}" in
  wineboot|wineboot.exe)
    [ "${2:-}" = -u ] || exit 91
    ;;
  reg|reg.exe)
    [ "${2:-}" = import ] && [ -f "${3:-}" ] || exit 92
    ;;
  -w)
    [ "$(basename "$0")" = wineserver ] || exit 93
    ;;
  *Launcher.exe)
    if [ -f "$WINEPREFIX/.synthetic-launch-exit" ]; then
      exit "$(cat "$WINEPREFIX/.synthetic-launch-exit")"
    fi
    ;;
  *) echo "Unexpected synthetic Wine command: $*" >&2; exit 94;;
esac
exit 0
'''


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(path: Path) -> dict:
    """File bytes and links, without following external or directory symlinks."""
    if not path.exists() and not path.is_symlink():
        return {}
    result = {}
    candidates = [path] + (list(path.rglob("*")) if path.is_dir() and not path.is_symlink() else [])
    for item in candidates:
        name = str(item.relative_to(path))
        if item.is_symlink():
            result[name] = ("link", os.readlink(item))
        elif item.is_file():
            result[name] = ("file", digest(item), item.stat().st_mode & 0o777)
        else:
            result[name] = ("dir",)
    return result


def write(path: Path, content: str | bytes, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content)
    if executable:
        path.chmod(0o755)


class Suite:
    def __init__(self, work: Path, isolate_process_check: bool = False):
        self.work = work
        self.isolate_process_check = isolate_process_check
        self.results = []
        self.res: Path | None = None
        self.tree = work / "tree/Recovery"
        self.payload = work / "payload"
        self.exe = work / "Synthetic Official.exe"
        self.source_hashes = {name: digest(REPO / name) for name in [
            "installer/setup.sh", "installer/common.sh", "installer/cleanup.sh", "installer/run.sh", "installer/Installer.swift",
            "installer/test-installation.sh", "installer/tests/integration.py", "tools/build-installer.sh",
        ]}

    def command(self, label: str, args: list[str | Path], success: bool = True, **kwargs):
        start = time.monotonic()
        p = subprocess.run([str(a) for a in args], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, errors="replace", **kwargs)
        write(self.work / "logs" / (label + ".log"), p.stdout)
        self.results.append({"case": label, "returncode": p.returncode,
                             "expected_success": success,
                             "expected_outcome_met": (p.returncode == 0) == success,
                             "seconds": round(time.monotonic() - start, 3)})
        assert (p.returncode == 0) == success, (label, p.returncode, p.stdout[-8000:])
        print(f"PASS {label}", flush=True)
        return p

    def setup(self, label: str, dest: Path, success: bool = True,
              res: Path | None = None, exe: Path | str = ""):
        return self.command(label, ["/bin/bash", REPO / "installer/setup.sh",
                                  res or self.res, dest, exe], success)

    def archive(self, target: Path, tree: Path | None = None) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(target, "w:xz") as output:
            output.add(tree or self.tree, arcname="Recovery")

    def refresh_hashes(self, tree: Path) -> None:
        runtime = tree / "runtime"
        write(tree / "RUNTIME-SHA256.txt", "".join(
            f"{digest(p)}  ./{p.relative_to(runtime).as_posix()}\n"
            for p in sorted(runtime.rglob("*")) if p.is_file() and not p.is_symlink()))
        wine = runtime / "Wine Devel.app/Contents/Resources/wine"
        core = ["bin/wine", "bin/wineserver", "lib/wine/x86_64-windows/ntoskrnl.exe",
                "lib/wine/x86_64-windows/d3d11.dll", "lib/wine/x86_64-windows/dxgi.dll",
                "lib/wine/x86_64-windows/winemetal.dll"]
        write(tree / "CORE-SHA256.txt", "".join(f"{digest(wine / p)}  ./{p}\n" for p in core))
        write(tree / "PROFILE-SHA256.txt", "".join(
            f"{digest(tree / p)}  ./{p}\n"
            for p in ["environment.sh", "fonts.reg", "version.json", "CORE-SHA256.txt"]))

    def build(self):
        wine = self.tree / "runtime/Wine Devel.app/Contents/Resources/wine"
        for name in ["wine", "wine64", "wineboot", "wineserver"]:
            write(wine / "bin" / name, FAKE_WINE, executable=True)
        for name in ["ntoskrnl.exe", "d3d11.dll", "dxgi.dll", "winemetal.dll"]:
            write(wine / "lib/wine/x86_64-windows" / name, "synthetic PE: " + name + "\n")
        write(self.tree / "environment.sh", "#!/bin/bash\nexport WINEDEBUG=-all\n"
              f"export WINEDLLOVERRIDES='{FROZEN_DLL_OVERRIDE}'\n")
        shutil.copy2(REPO / "DirectX11/fonts.reg", self.tree / "fonts.reg")
        # Exercise cleanup against the actual license set shipped by Recovery.
        shutil.copytree(REPO / "Recovery/licenses/DXMT-dependencies",
                        self.tree / "licenses/DXMT-dependencies")
        write(self.tree / "version.json", json.dumps({"version": VERSION, "synthetic": True}) + "\n")
        (self.tree / "bin").mkdir(parents=True)
        shutil.copy2(REPO / "Vulkan/bin/7zz", self.tree / "bin/7zz")
        self.refresh_hashes(self.tree)
        self.archive(self.payload / f"Wine_Endfield-Recovery-{VERSION}.tar.xz")
        self.command("build-installer", ["/bin/bash", REPO / "tools/build-installer.sh",
                                         self.payload, self.work / "built", VERSION])
        self.res = self.work / "built/终末地 Mac 安装器.app/Contents/Resources"
        if self.isolate_process_check:
            # Only these synthetic test resources see a filtered process
            # inventory. Production code and the user's running processes are
            # untouched; the actual busy parser still sees our test server.
            inventory = self.work / "synthetic-process-inventory"
            write(inventory, "#!/bin/bash\nset -eo pipefail\n"
                  "printf '%s synthetic-idle-test-host\\n' \"$(/usr/bin/id -u)\"\n"
                  "/bin/ps -ww -axo uid=,comm= | /usr/bin/awk -v target=" +
                  shlex.quote(str(self.work / "wineserver")) +
                  " ' { uid=$1; $1=\"\"; sub(/^ +/, \"\"); if ($0==target) print uid, $0 }'\n", executable=True)
            common = self.res / "common.sh"
            original = common.read_text()
            assert original.count("/bin/ps -ww -axo uid=,comm=") == 1
            write(common, original.replace("/bin/ps -ww -axo uid=,comm=", shlex.quote(str(inventory))))
        official = self.work / "official-source/$0/9.9.9"
        for name in ["Launcher.exe", "Games.exe"]:
            write(official / name, "synthetic official file; never executed\n")
        self.command("create-synthetic-official", [self.tree / "bin/7zz", "a", self.exe, "$0"],
                     cwd=self.work / "official-source")

    def legacy(self, dest: Path, version: str = "v0.3.0-preview", updater: bool = True):
        write(dest / ".endfield-installer-v1", "")
        write(dest / "payload-manifest.tsv", f"format\t1\nversion\t{version}\n")
        write(dest / "run.sh", "#!/bin/bash\n# old entry, must only change on success\n")
        official = "1.5.0" if version == "v0.2.0" else "1.6.0"
        for name in ["Launcher.exe", f"{official}/Launcher.exe", f"{official}/Games.exe"]:
            write(dest / "Launcher" / name, "retained official launcher: " + name + "\n")
        if version != "v0.2.0":
            write(dest / "Launcher/.official-version", official + "\n")
        write(dest / "Launcher/local-settings.json", '{"render_mode":"vk","user":"synthetic"}\n')
        write(dest / "Game/Endfield.exe", bytes(range(256)))
        write(dest / "Game/Endfield_Data/large-test-asset", os.urandom(65536))
        (dest / "Launcher/games").mkdir()
        (dest / "Launcher/games/Arknights Endfield").symlink_to(dest / "Game", target_is_directory=True)
        for mode in (["Updater"] if updater else []) + ["Vulkan", "DirectX11"]:
            state = dest / mode / "local"
            write(state / "ready-v1", "")
            write(state / "cache/retained-user-cache", "cache for " + mode)
            write(state / "prefix/system.reg", "WINE REGISTRY Version 2\n; retained from " + mode + "\n")
            write(state / "prefix/drive_c/users/synthetic/settings.bin", "settings from " + mode)
            write(state / "prefix/drive_c/users/synthetic/AppData/LocalLow/Hypergryph/Endfield/settings.json",
                  '{"ordinary_user_settings":true,"source":"' + mode + '"}\n')
            (state / "prefix/dosdevices").mkdir()
            (state / "prefix/dosdevices/c:").symlink_to("../drive_c", target_is_directory=True)
            (state / "prefix/drive_c/Endfield").symlink_to(dest / "Game", target_is_directory=True)
            if mode != "Updater":
                write(dest / mode / ".payload-id", version + " " + "a" * 64 + "\n")
                runtime_file = dest / mode / "runtime/preserved-old-runtime"
                write(runtime_file, mode + " runtime\n")
                write(dest / mode / "RUNTIME-SHA256.txt", f"{digest(runtime_file)}  ./preserved-old-runtime\n")
            write(state / "custom-note.txt", "keep personal note in " + mode)
            write(dest / mode / "custom-note.txt", "keep personal note beside " + mode)
        write(dest / "Apps/Unrelated User.app/Contents/keep", "do not replace user apps")
        for mode, title in [("Vulkan", "终末地 Vulkan"), ("DirectX11", "终末地 DX11"), ("Update", "终末地 更新与修复")]:
            write(dest / "Apps" / (title + ".app") / "Contents/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "io.wineendfield.installed." + mode,
                "InstallRoot": str(dest), "LaunchMode": mode,
            }))
        write(dest / "user-note.txt", "unmanaged addition inside a managed root")

    def assert_portable(self, dest: Path, label: str):
        self.command(label, ["/bin/bash", REPO / "installer/test-installation.sh", dest])
        for app in (dest / "Apps").glob("*.app"):
            plist = app / "Contents/Info.plist"
            if not plist.exists():
                continue
            metadata = plistlib.loads(plist.read_bytes())
            if metadata.get("CFBundleIdentifier", "").startswith("io.wineendfield.installed."):
                p = subprocess.run([str(app / "Contents/MacOS/EndfieldInstaller"), "--check"],
                                   capture_output=True, text=True, check=True)
                assert str(dest) in p.stdout, (app, "did not resolve current installation root", p.stdout)

    def variant(self, label: str, fail_prepare: bool = False) -> Path:
        assert self.res
        res = self.work / label / "Contents/Resources"
        shutil.copytree(self.res.parent, res.parent)
        tree = self.work / (label + "-tree") / "Recovery"
        shutil.copytree(self.tree, tree, symlinks=True)
        if fail_prepare:
            write(tree / "runtime/Wine Devel.app/Contents/Resources/wine/bin/.fail-prepare", "fail\n")
        else:
            write(tree / "version.json", json.dumps({"synthetic": label}) + "\n")
        self.refresh_hashes(tree)
        archive = res / f"Wine_Endfield-Recovery-{VERSION}.tar.xz"
        self.archive(archive, tree)
        write(res / "payload-manifest.tsv", f"format\t2\nversion\t{VERSION}\n"
              f"payload\tRecovery\t{archive.name}\t{digest(archive)}\n")
        return res

    def run(self):
        self.build()
        no_exe = self.work / "fresh-without-official-installer"
        failed = self.setup("fresh-install-requires-official-installer", no_exe, success=False)
        assert "新安装需要从官网下载的 Windows 官方启动器 EXE" in failed.stdout
        assert "安装失败阶段：检查系统与安装位置（退出码 1）" in failed.stdout
        assert not no_exe.exists()
        disconnected = Path("/Volumes") / ("Endfield-disconnected-" + self.work.name) / "Wine Endfield"
        assert not disconnected.parent.exists()
        self.setup("disconnected-volume-rejected", disconnected, success=False, exe=self.exe)
        assert not disconnected.parent.exists()
        fresh = self.work / "external volume 中文 & space's $ [1]" / "Wine Endfield"
        self.setup("fresh-special-path", fresh, exe=self.exe)
        self.assert_portable(fresh, "fresh-installed-check")
        initial_environment = self.environment_calls(fresh / "State/prefix")
        boots = [row for row in initial_environment if row[1] == "wineboot.exe"]
        assert len(boots) == 1, initial_environment
        assert boots[0][2] == FROZEN_DLL_OVERRIDE + ";mscoree,mshtml=", boots
        imports = [row for row in initial_environment if row[1] == "reg.exe"]
        assert len(imports) == 2, initial_environment
        assert all(row[2] == FROZEN_DLL_OVERRIDE for row in initial_environment if row[1] != "wineboot.exe")
        assert not any(row[1] in {"wineboot", "reg"} for row in initial_environment)

        for version in ["v0.2.0", "v0.3.0-preview"]:
            dest = self.work / ("upgrade-" + version)
            self.legacy(dest, version)
            game = snapshot(dest / "Game")
            self.setup("upgrade-" + version, dest)
            assert snapshot(dest / "Game") == game
            self.assert_legacy_cleaned(dest)
            assert (dest / "State/prefix/drive_c/users/synthetic/settings.bin").read_text() == "settings from Updater"
            assert (dest / "Apps/Unrelated User.app/Contents/keep").read_text() == "do not replace user apps"
            assert (dest / "Launcher/local-settings.json").read_text().startswith('{"render_mode":"vk"')
            self.assert_portable(dest, "structure-" + version)

        early = self.work / "upgrade-early-v0.2-without-manifest"
        self.legacy(early, "v0.2.0")
        (early / "payload-manifest.tsv").unlink()
        for mode in ["Vulkan", "DirectX11"]:
            (early / mode / ".payload-id").unlink()
            write(early / mode / "common.sh", "#!/bin/bash\n# early managed runtime\n")
            write(early / mode / "fonts.reg", "Windows Registry Editor Version 5.00\n")
        game_before = snapshot(early / "Game")
        self.setup("upgrade-early-v0.2-without-manifest-or-payload-id", early)
        self.assert_legacy_cleaned(early)
        assert snapshot(early / "Game") == game_before
        for backup in (early / ".runtime-backups").glob("*"):
            assert not (backup / "run.sh").exists()
            assert not (backup / "Apps/终末地 Vulkan.app").exists()
            assert (backup / "Apps/Unrelated User.app/Contents/keep").is_file()

        dest = self.work / "upgrade-v0.3.0-preview"
        write(dest / "State/cache/new-user-settings", "retain unified state on reinstall")
        self.setup("same-version-reinstall", dest)
        assert (dest / "State/cache/new-user-settings").read_text() == "retain unified state on reinstall"
        assert not list((dest / ".runtime-backups").glob("*/State/prefix")), "successful installation retained superseded state backup"
        assert not list((dest / ".runtime-backups").glob("*/State/cache")), "successful installation retained superseded state cache"
        assert not list((dest / ".runtime-backups").glob("*/Recovery/runtime")), "successful installation retained superseded runtime backup"
        assert not list((dest / ".runtime-backups").glob("*/Recovery")), "successful installation retained recognized Recovery metadata or licenses"
        assert snapshot(dest / "Recovery/licenses/DXMT-dependencies") == snapshot(self.tree / "licenses/DXMT-dependencies")

        fallback = self.work / "legacy-without-updater"
        self.legacy(fallback, updater=False)
        self.setup("migration-falls-back-to-dx11-state", fallback)
        assert (fallback / "State/prefix/drive_c/users/synthetic/settings.bin").read_text() == "settings from DirectX11"
        self.assert_legacy_cleaned(fallback)

        original_location = self.work / "legacy-before-move"
        self.legacy(original_location)
        relocated_legacy = self.work / "legacy relocated 中文" / "Wine Endfield"
        relocated_legacy.parent.mkdir()
        original_location.rename(relocated_legacy)
        old_game = snapshot(relocated_legacy / "Game")
        self.setup("upgrade-already-moved-legacy-installation", relocated_legacy)
        self.assert_portable(relocated_legacy, "moved-legacy-installed-check")
        self.assert_legacy_cleaned(relocated_legacy)
        assert snapshot(relocated_legacy / "Game") == old_game

        tracked = ["Recovery", "State", "Apps", "run.sh", "common.sh", "payload-manifest.tsv", "Game"]
        before = {name: snapshot(dest / name) for name in tracked}
        failres = self.variant("failure-app", fail_prepare=True)
        failed = self.setup("failed-upgrade-rolls-back", dest, success=False, res=failres)
        assert failed.returncode == 42, failed.stdout
        assert "安装失败阶段：初始化 Wine 环境（退出码 42）" in failed.stdout
        assert "synthetic Wine initialization failure" in failed.stdout
        assert "安装诊断结束。" in failed.stdout
        assert all(snapshot(dest / name) == content for name, content in before.items()), "rollback changed installed data"
        assert not (dest / ".setup-lock").exists()

        finalres = self.variant("commit-failure-app")
        common = finalres / "common.sh"
        write(common, common.read_text() + "\n# Test-only failure after the production commit loop.\n"
              "verify_installation() { echo 'synthetic final validation failure' >&2; return 43; }\n")
        original_download_link = (dest / "Launcher/games/Arknights Endfield").readlink()
        failed = self.setup("failed-final-validation-rolls-back-committed-files", dest,
                            success=False, res=finalres)
        assert failed.returncode == 43, failed.stdout
        assert "安装失败阶段：验证安装结果（退出码 43）" in failed.stdout
        assert "synthetic final validation failure" in failed.stdout
        assert "synthetic Wine initialization failure" not in failed.stdout, "included stale nested logs"
        assert all(snapshot(dest / name) == content for name, content in before.items()), "commit rollback changed installed data"
        assert (dest / "Launcher/games/Arknights Endfield").readlink() == original_download_link

        # Cleaning is a post-success operation. An old installation must keep
        # every independent prefix when either preparation or commit fails.
        for label, failure_res, code in [
            ("failed-legacy-prepare-preserves-all-environments", failres, 42),
            ("failed-legacy-validation-preserves-all-environments", finalres, 43),
        ]:
            legacy_failure = self.work / label
            self.legacy(legacy_failure)
            preserved_names = ["Updater", "Vulkan", "DirectX11", "Game", "Launcher", "Apps", "run.sh", "payload-manifest.tsv"]
            original_legacy = {name: snapshot(legacy_failure / name) for name in preserved_names}
            failed = self.setup(label, legacy_failure, success=False, res=failure_res)
            assert failed.returncode == code, failed.stdout
            assert all(snapshot(legacy_failure / name) == content for name, content in original_legacy.items())
            assert not (legacy_failure / "State").exists()

        cleanupres = self.variant("cleanup-failure-app")
        write(cleanupres / "cleanup.sh", "#!/bin/bash\necho 'synthetic cleanup failure' >&2\nexit 49\n", executable=True)
        cleanup_failure = self.work / "cleanup-failure-does-not-undo-installation"
        self.legacy(cleanup_failure)
        original_game = snapshot(cleanup_failure / "Game")
        result = self.setup("cleanup-failure-does-not-undo-installation", cleanup_failure, res=cleanupres)
        assert "清理提醒：" in result.stdout and "synthetic cleanup failure" in result.stdout, result.stdout
        assert (cleanup_failure / "State/prefix/drive_c/users/synthetic/settings.bin").read_text() == "settings from Updater"
        assert snapshot(cleanup_failure / "Game") == original_game
        self.assert_portable(cleanup_failure, "cleanup-failure-installed-check")

        for label, injection in [
            ("committed-backup-staging-failure-is-nonfatal", r'''
mkdir() {
  if [ "$#" = 2 ] && [ "$1" = -p ] && [ "$2" = "$DEST/.runtime-backups" ]; then
    echo 'synthetic backup directory creation failure' >&2; return 44
  fi
  command mkdir "$@"
}
'''),
            ("committed-work-removal-failure-is-nonfatal", r'''
rm() {
  if [ "${committed:-0}" = 1 ] && [ "$#" = 2 ] && [ "$1" = -rf ] && [ "$2" = "${work:-no-test-work}" ]; then
    echo 'synthetic committed work removal failure' >&2; return 45
  fi
  command rm "$@"
}
'''),
        ]:
            failure_res = self.variant(label + "-app")
            common = failure_res / "common.sh"
            write(common, common.read_text() + "\n# Synthetic fixture: fail one post-commit filesystem operation.\n" + injection)
            installed = self.work / label
            self.legacy(installed)
            original_game = snapshot(installed / "Game")
            result = self.setup(label, installed, res=failure_res)
            assert "清理提醒：" in result.stdout, result.stdout
            expected_failure = "synthetic backup directory creation failure" if "backup-staging" in label else "synthetic committed work removal failure"
            assert expected_failure in result.stdout, result.stdout
            assert snapshot(installed / "Game") == original_game
            assert (installed / "State/prefix/drive_c/users/synthetic/settings.bin").read_text() == "settings from Updater"
            assert list(installed.glob(".setup-work.*")), "failed cleanup discarded the diagnostic work directory"
            if "backup-staging" in label:
                assert list(installed.glob(".setup-work.*/backup/run.sh")), "failed backup move lost the old entry"
            self.assert_portable(installed, label + "-installed-check")

        verifyres = self.variant("payload-verify-failure-app")
        archive = verifyres / f"Wine_Endfield-Recovery-{VERSION}.tar.xz"
        tree = self.work / "payload-verify-failure-app-tree/Recovery"
        # Make the archive itself valid while corrupting an internally pinned file.
        write(tree / "fonts.reg", "synthetic corruption\n")
        self.archive(archive, tree)
        write(verifyres / "payload-manifest.tsv", f"format\t2\nversion\t{VERSION}\n"
              f"payload\tRecovery\t{archive.name}\t{digest(archive)}\n")
        failed = self.setup("nested-payload-error-reaches-main-log", dest, success=False, res=verifyres)
        assert "安装失败阶段：校验修复运行库（退出码 1）" in failed.stdout
        assert "运行配置校验失败" in failed.stdout
        assert "checksum did NOT match" in failed.stdout
        assert all(snapshot(dest / name) == content for name, content in before.items())

        badexe = self.work / "Corrupt Official.exe"
        write(badexe, "not an installer\n")
        failed = self.setup("official-extraction-error-reaches-main-log", self.work / "failed-extraction",
                            success=False, exe=badexe)
        assert "安装失败阶段：提取官方启动器" in failed.stdout
        assert "installer-extract.log" in failed.stdout
        assert "ERROR" in failed.stdout

        archive = failres / f"Wine_Endfield-Recovery-{VERSION}.tar.xz"
        with archive.open("ab") as f:
            f.write(b"bad checksum")
        self.setup("corrupt-payload-rejected", dest, success=False, res=failres)
        assert all(snapshot(dest / name) == content for name, content in before.items())

        unknown = self.work / "unmanaged"
        write(unknown / "important.txt", "must not touch")
        original = snapshot(unknown)
        self.setup("unmanaged-directory-rejected", unknown, success=False)
        assert snapshot(unknown) == original
        linked = self.work / "symbolic-root"
        linked.symlink_to(dest, target_is_directory=True)
        self.setup("symlink-root-rejected", linked, success=False)
        assert all(snapshot(dest / name) == content for name, content in before.items())

        with (dest / ".session.lock").open("a") as held_lock:
            fcntl.flock(held_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.setup("concurrent-installation-lock-rejected", dest, success=False)
        assert all(snapshot(dest / name) == content for name, content in before.items())

        guarded = self.work / "protected-game-is-link"
        self.legacy(guarded)
        shutil.rmtree(guarded / "Game")
        (guarded / "Game").symlink_to(unknown, target_is_directory=True)
        self.setup("external-game-directory-rejected", guarded, success=False)
        assert snapshot(unknown) == original

        mismatched = self.work / "launcher-download-path-changed"
        self.legacy(mismatched)
        download_link = mismatched / "Launcher/games/Arknights Endfield"
        download_link.unlink()
        download_link.symlink_to(unknown, target_is_directory=True)
        self.setup("nonstandard-launcher-download-path-rejected", mismatched, success=False)
        assert download_link.readlink() == unknown
        assert snapshot(unknown) == original

        linked_system = self.work / "legacy-system-directory-is-link"
        self.legacy(linked_system)
        external_system = self.work / "external-system-directory"
        original_drive = linked_system / "Updater/local/prefix/drive_c"
        original_drive.rename(external_system)
        original_drive.symlink_to(external_system, target_is_directory=True)
        external_before = snapshot(external_system)
        self.setup("external-prefix-system-directory-rejected", linked_system, success=False)
        assert snapshot(external_system) == external_before, "installer followed a system-directory symlink"

        linked_games = self.work / "launcher-games-directory-is-link"
        self.legacy(linked_games)
        external_games = self.work / "external-launcher-games"
        (linked_games / "Launcher/games").rename(external_games)
        (linked_games / "Launcher/games").symlink_to(external_games, target_is_directory=True)
        external_before = snapshot(external_games)
        self.setup("external-launcher-games-directory-rejected", linked_games, success=False)
        assert snapshot(external_games) == external_before, "installer followed the launcher games symlink"

        server = self.work / "wineserver"
        # Copying a platform-signed /bin/sleep can be killed by macOS; use our
        # own signed executable so the guard sees a reliably live process.
        self.command("build-busy-test-process", ["/usr/bin/clang", "-x", "c", "-", "-o", server],
                     input="#include <unistd.h>\nint main(void) { sleep(60); return 0; }\n")
        self.command("sign-busy-test-process", ["/usr/bin/codesign", "--force", "--sign", "-", server])
        own_process = subprocess.Popen([str(server)])
        try:
            time.sleep(0.25)
            assert own_process.poll() is None, "busy-test process did not stay alive"
            self.setup("busy-wine-rejected", self.work / "blocked-by-wine", success=False, exe=self.exe)
            assert not (self.work / "blocked-by-wine").exists()
        finally:
            own_process.terminate()
            own_process.wait()

        moved = self.work / "renamed external volume 中文" / "moved installation"
        moved.parent.mkdir()
        fresh.rename(moved)
        self.assert_portable(moved, "moved-installation-check")
        prefix = moved / "State/prefix"
        for mode in ["", "Vulkan", "DirectX11", "Update"]:
            args = ["/bin/bash", moved / "run.sh"] + ([mode] if mode else [])
            previous_count = len(self.environment_calls(prefix))
            self.command("run-launcher-" + (mode or "default"), args)
            calls = (prefix / ".synthetic-calls").read_text()
            assert "Launcher.exe" in calls
            assert "-force-vulkan" not in calls and "-force-d3d11" not in calls
            assert "Endfield.exe" not in calls
            launched = self.environment_calls(prefix)[previous_count:]
            assert len(launched) == 2 and launched[0][1].endswith("Launcher.exe"), launched
            assert all(row[2] == FROZEN_DLL_OVERRIDE for row in launched), launched
        write(prefix / ".synthetic-launch-exit", "17\n")
        p = self.command("failed-launch-still-waits-for-server", ["/bin/bash", moved / "run.sh"], False)
        assert p.returncode == 17, p.stdout
        calls = (prefix / ".synthetic-calls").read_text().splitlines()
        assert calls[-1].startswith("wineserver\t-w\t"), calls[-5:]
        self.filesystem_contract()
        self.cleanup_contract()

    def assert_legacy_cleaned(self, dest: Path):
        for mode in ["Updater", "Vulkan", "DirectX11"]:
            assert not (dest / mode / "local/prefix").exists(), (mode, "legacy user prefix remains")
            assert not (dest / mode / "local/cache").exists(), (mode, "legacy user cache remains")
            assert not (dest / mode / "runtime").exists(), (mode, "legacy runtime remains")
            if (dest / mode).exists():
                assert (dest / mode / "custom-note.txt").read_text() == "keep personal note beside " + mode
                assert (dest / mode / "local/custom-note.txt").read_text() == "keep personal note in " + mode
        assert (dest / "State/prefix/system.reg").is_file()
        assert (dest / "user-note.txt").read_text() == "unmanaged addition inside a managed root"

    def cleanup_fixture(self, name: str) -> Path:
        """Represent a committed new installation plus recognizable old files."""
        assert self.res
        dest = self.work / "cleanup-fixtures" / name
        self.legacy(dest)
        shutil.copytree(self.tree, dest / "Recovery", symlinks=True)
        write(dest / "Recovery/.payload-id", VERSION + " " + "b" * 64 + "\n")
        shutil.copy2(self.res / "payload-manifest.tsv", dest / "payload-manifest.tsv")
        shutil.copy2(self.res / "common.sh", dest / "common.sh")
        write(dest / "State/prefix/system.reg", "WINE REGISTRY Version 2\n; active adopted state\n")
        write(dest / "State/cache/current-cache", "active cache must remain")
        return dest

    def run_cleanup(self, label: str, dest: Path):
        protected = {name: snapshot(dest / name) for name in ["Recovery", "State", "Game", "Launcher"]}
        result = self.command(label, ["/bin/bash", REPO / "installer/cleanup.sh", dest])
        assert all(snapshot(dest / name) == content for name, content in protected.items()), "cleanup changed active/game data"
        return result

    def cleanup_contract(self):
        dest = self.cleanup_fixture("known-legacy-and-personal-files")
        self.run_cleanup("cleanup-known-environments-preserves-personal-files", dest)
        self.assert_legacy_cleaned(dest)
        original = snapshot(dest)
        self.run_cleanup("cleanup-repeat-is-idempotent", dest)
        assert snapshot(dest) == original

        # A real copy of game data inside an obsolete tree is deliberately
        # retained. Name matching must not depend on the filesystem's casing.
        exe = self.cleanup_fixture("embedded-game-executable")
        copied_exe = exe / "DirectX11/local/prefix/drive_c/Manual Game/EnDfIeLd.ExE"
        write(copied_exe, b"GAME executable sentinel\x00\xff")
        old_prefix = snapshot(exe / "DirectX11/local/prefix")
        result = self.run_cleanup("cleanup-preserves-embedded-game-executable", exe)
        assert snapshot(exe / "DirectX11/local/prefix") == old_prefix
        assert "清理提醒：" in result.stdout

        data = self.cleanup_fixture("embedded-game-data")
        copied_data = data / "Vulkan/local/cache/manual/enDFieLD_dATa/chunk"
        write(copied_data, b"GAME data sentinel\x00\xff")
        old_cache = snapshot(data / "Vulkan/local/cache")
        result = self.run_cleanup("cleanup-preserves-embedded-game-data", data)
        assert snapshot(data / "Vulkan/local/cache") == old_cache
        assert "清理提醒：" in result.stdout

        linked = self.cleanup_fixture("external-and-game-links")
        external = self.work / "cleanup-external-data"
        write(external / "personal-data", "outside cleanup root")
        external_before = snapshot(external)
        (linked / "Updater/local/prefix/drive_c/external").symlink_to(external, target_is_directory=True)
        shutil.rmtree(linked / "Vulkan/local/cache")
        (linked / "Vulkan/local/cache").symlink_to(external, target_is_directory=True)
        self.run_cleanup("cleanup-does-not-follow-game-or-external-links", linked)
        assert snapshot(external) == external_before
        assert not (linked / "Updater/local/prefix").exists(), "ordinary Game symlink prevented cleaning obsolete prefix"

        linked_prefix = self.cleanup_fixture("linked-unselected-prefix")
        external_prefix = self.work / "cleanup-external-prefix"
        (linked_prefix / "Vulkan/local/prefix").rename(external_prefix)
        (linked_prefix / "Vulkan/local/prefix").symlink_to(external_prefix, target_is_directory=True)
        before = snapshot(external_prefix)
        self.run_cleanup("cleanup-does-not-follow-an-old-prefix-link", linked_prefix)
        assert snapshot(external_prefix) == before

        backups = self.cleanup_fixture("legacy-backup-formats")
        old_mode = backups / ".runtime-backups/20260101-120000-Vulkan-4321"
        shutil.copytree(backups / "Vulkan", old_mode, symlinks=True)
        mixed = backups / ".runtime-backups/20260101-120001-4321"
        shutil.copytree(backups / "Recovery", mixed / "Recovery", symlinks=True)
        shutil.copytree(backups / "State", mixed / "State", symlinks=True)
        write(mixed / "State/custom-note.txt", "old state personal note")
        shutil.copytree(backups / "Apps", mixed / "Apps", symlinks=True)
        shutil.copy2(backups / "payload-manifest.tsv", mixed / "payload-manifest.tsv")
        write(mixed / "run.sh", "#!/bin/bash\n# obsolete managed entry\n")
        write(mixed / "personal-note.txt", "backup personal note")
        write(mixed / "Game/Endfield.exe", "retained game in historical backup")
        unknown = backups / ".runtime-backups/personal-archive"
        write(unknown / "local/prefix/system.reg", "unmanaged backup must remain")
        unknown_before = snapshot(unknown)
        (backups / ".runtime-backups/20260101-120002-Vulkan-4321").symlink_to(external, target_is_directory=True)
        self.run_cleanup("cleanup-recognizes-both-backup-formats", backups)
        assert not (old_mode / "runtime").exists()
        assert not (old_mode / "local/prefix").exists()
        assert (old_mode / "custom-note.txt").is_file()
        assert not (mixed / "Recovery/runtime").exists()
        assert not (mixed / "State/prefix").exists()
        assert not (mixed / "State/cache").exists()
        assert (mixed / "State/custom-note.txt").read_text() == "old state personal note"
        assert not (mixed / "Apps/终末地 Vulkan.app").exists()
        assert (mixed / "Apps/Unrelated User.app/Contents/keep").is_file()
        assert (mixed / "Game/Endfield.exe").read_text() == "retained game in historical backup"
        assert (mixed / "personal-note.txt").read_text() == "backup personal note"
        assert snapshot(unknown) == unknown_before
        assert snapshot(external) == external_before

        embedded = self.cleanup_fixture("game-in-old-runtime-backup")
        old_mode = embedded / ".runtime-backups/20260101-120000-DirectX11-4321"
        shutil.copytree(embedded / "DirectX11", old_mode, symlinks=True)
        write(old_mode / "runtime/ENDFIELD.exe", "retained game alongside old runtime")
        before = snapshot(old_mode / "runtime")
        result = self.run_cleanup("cleanup-preserves-game-in-runtime-backup", embedded)
        assert snapshot(old_mode / "runtime") == before
        assert "清理提醒：" in result.stdout

        custom = self.cleanup_fixture("untracked-runtime-addition")
        write(custom / "Vulkan/runtime/personal-plugin", "not listed by original runtime manifest")
        before = snapshot(custom / "Vulkan/runtime")
        result = self.run_cleanup("cleanup-preserves-untracked-runtime-addition", custom)
        assert snapshot(custom / "Vulkan/runtime") == before
        assert "清理提醒：" in result.stdout

        unowned = self.cleanup_fixture("unrecognized-payload-id")
        write(unowned / "Vulkan/.payload-id", "unrecognized runtime\n")
        before = snapshot(unowned / "Vulkan")
        result = self.run_cleanup("cleanup-preserves-unrecognized-old-runtime", unowned)
        assert snapshot(unowned / "Vulkan") == before
        assert "清理提醒：" in result.stdout

        linked_id = self.cleanup_fixture("linked-payload-marker")
        (linked_id / "Vulkan/.payload-id").unlink()
        (linked_id / "Vulkan/.payload-id").symlink_to(linked_id / "DirectX11/.payload-id")
        before = snapshot(linked_id / "Vulkan")
        result = self.run_cleanup("cleanup-does-not-trust-linked-payload-marker", linked_id)
        assert snapshot(linked_id / "Vulkan") == before
        assert "清理提醒：" in result.stdout

        logs = self.cleanup_fixture("obsolete-root-logs")
        obsolete = ["setup-Vulkan.log", "setup-DirectX11.log", "setup-updater.log",
                    "verify-Vulkan.log", "verify-DirectX11.log", "extract.log", "installer-123456.log",
                    "run-Vulkan-123456.log", "run-DirectX11-123456.log", "run-Update-123456.log"]
        retained = ["installer-prefix.log", "installer-verify.log", "installer-extract.log", "installer-cleanup.log",
                    "session-20260101.log", "shortcut.log", "custom-user.log", "installer-not-numeric.log",
                    "run-Unknown-123456.log"]
        for name in obsolete + retained:
            write(logs / "logs" / name, "log sentinel " + name)
        external_log = self.work / "cleanup-external-log.txt"
        write(external_log, "external log must stay")
        (logs / "logs/installer-456789.log").symlink_to(external_log)
        self.run_cleanup("cleanup-removes-only-recognized-old-root-logs", logs)
        assert all(not (logs / "logs" / name).exists() for name in obsolete)
        assert all((logs / "logs" / name).read_text() == "log sentinel " + name for name in retained)
        assert (logs / "logs/installer-456789.log").is_symlink()
        assert external_log.read_text() == "external log must stay"

        for early in [False, True]:
            label = "early-v0.2" if early else "v0.3"
            retry = self.cleanup_fixture("retry-retained-game-" + label)
            mode = retry / "Vulkan"
            if early:
                (mode / ".payload-id").unlink()
                write(mode / "common.sh", "#!/bin/bash\n# early managed runtime\n")
                write(mode / "fonts.reg", "Windows Registry Editor Version 5.00\n")
            real_game = mode / "local/prefix/drive_c/manual-copy/Endfield.exe"
            write(real_game, "game kept during partial cleanup")
            self.run_cleanup("cleanup-preserves-retry-ownership-" + label, retry)
            assert real_game.is_file()
            assert not (mode / "runtime").exists()
            assert (mode / "RUNTIME-SHA256.txt").is_file(), "partial cleanup lost early-runtime ownership proof"
            if early:
                assert (mode / "common.sh").is_file() and (mode / "fonts.reg").is_file()
            else:
                assert (mode / ".payload-id").is_file()
            recovered = retry / "Game/Recovered-old-Endfield.exe"
            real_game.rename(recovered)
            self.run_cleanup("cleanup-retries-after-game-is-relocated-" + label, retry)
            assert not (mode / "local/prefix").exists(), "recognized leftover prefix was never retried"
            assert recovered.read_text() == "game kept during partial cleanup"

    def environment_calls(self, prefix: Path):
        return [line.split("\t", 2) for line in (prefix / ".synthetic-environment.tsv").read_text().splitlines()]

    def filesystem_contract(self):
        # Isolate only diskutil's metadata; execute the exact production parser
        # and validation branches with real plutil/df/path checks. These are
        # explicitly simulated filesystems, separate from the optional image.
        directory = self.work / "filesystem-metadata-fixtures"
        stub = directory / "diskutil-stub"
        common = directory / "common.sh"
        write(common, (REPO / "installer/common.sh").read_text().replace(
            "/usr/sbin/diskutil", shlex.quote(str(stub))))
        for kind in ["apfs", "hfs", "exfat", "msdos", "ntfs"]:
            plist = plistlib.dumps({"FilesystemType": kind, "WritableVolume": True}).decode()
            write(stub, "#!/bin/bash\ncat <<'PLIST'\n" + plist + "PLIST\n", executable=True)
            target = directory / ("not-created-" + kind)
            p = self.command("filesystem-metadata-" + kind,
                             ["/bin/bash", "-euc", 'source "$1"; validate_path "$2"',
                              "filesystem-fixture", common, target], kind in {"apfs", "hfs"})
            assert not target.exists()
            if kind not in {"apfs", "hfs"}:
                assert "APFS" in p.stdout and "Mac OS" in p.stdout and kind in p.stdout, p.stdout

    def exfat(self):
        image = self.work / "external-exfat-test.dmg"
        mount = self.work / "mounted exFAT"
        self.command("create-exfat-image", ["/usr/bin/hdiutil", "create", "-size", "64m",
                                            "-fs", "ExFAT", "-volname", "Endfield Synthetic",
                                            image])
        self.command("attach-exfat-image", ["/usr/bin/hdiutil", "attach", "-nobrowse",
                                            "-mountpoint", mount, image])
        try:
            dest = mount / "Wine Endfield"
            self.setup("exfat-explicitly-rejected", dest, success=False, exe=self.exe)
            assert not dest.exists(), "Unsupported filesystem was mutated"
            log = (self.work / "logs/exfat-explicitly-rejected.log").read_text()
            assert "APFS" in log and ("HFS" in log or "Mac OS" in log), log
        finally:
            self.command("detach-exfat-image", ["/usr/bin/hdiutil", "detach", mount])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New output directory; retained for review")
    parser.add_argument("--test-exfat", action="store_true", help="Also mount a temporary 64 MiB ExFAT image")
    parser.add_argument("--isolate-process-check", action="store_true", help="Synthetic resources only: report only the suite's fake wineserver in the process inventory")
    args = parser.parse_args()
    if args.output:
        work = args.output.resolve()
        work.mkdir(parents=True, exist_ok=False)
    else:
        work = Path(tempfile.mkdtemp(prefix="endfield-installer-tests-"))
    suite = Suite(work, isolate_process_check=args.isolate_process_check)
    completed = False
    try:
        suite.run()
        if args.test_exfat:
            suite.exfat()
        completed = True
    finally:
        write(work / "results.json", json.dumps({
            "scope": "Synthetic runtime; no real Wine or official application executed",
            "process_inventory": "simulated; only the suite's fake wineserver is included" if args.isolate_process_check else "actual host process inventory",
            "completed": completed, "output": str(work), "results": suite.results,
            "source_sha256": suite.source_hashes,
            "synthetic_common_sha256": digest(suite.res / "common.sh") if suite.res else None,
        }, ensure_ascii=False, indent=2) + "\n")
        print(f"Evidence: {work}", flush=True)


if __name__ == "__main__":
    main()
