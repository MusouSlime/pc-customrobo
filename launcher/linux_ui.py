#!/usr/bin/env python3
"""Native-dialog launcher for Linux (yad, with a zenity fallback)."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import core  # noqa: E402

TITLE = "Custom Robo: Battle Revolution"


def have(prog: str) -> bool:
    return shutil.which(prog) is not None


YAD = have("yad")
ZENITY = have("zenity")
PROGRESS_TOOL = "yad" if YAD else "zenity"


def _run_dialog(cmd: list[str]) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL)
        return r.returncode, (r.stdout or "").strip()
    except OSError:
        return 1, ""


def info(text: str, title: str = TITLE) -> None:
    if YAD:
        _run_dialog(["yad", "--info", "--title", title, "--text", text,
                     "--width", "520", "--center", "--button", "OK"])
    elif ZENITY:
        _run_dialog(["zenity", "--info", "--title", title, "--text", text,
                     "--width", "520"])
    else:
        print(f"{title}: {text}")


def error(text: str, title: str = TITLE) -> None:
    if YAD:
        _run_dialog(["yad", "--error", "--title", title, "--text", text,
                     "--width", "620", "--center", "--button", "OK"])
    elif ZENITY:
        _run_dialog(["zenity", "--error", "--title", title, "--text", text,
                     "--width", "620"])
    else:
        print(f"{title}: {text}", file=sys.stderr)


def ask(text: str, title: str = TITLE) -> bool:
    if YAD:
        rc, _ = _run_dialog(["yad", "--question", "--title", title, "--text", text,
                             "--width", "520", "--center",
                             "--button", "No:1", "--button", "Yes:0"])
        return rc == 0
    if ZENITY:
        rc, _ = _run_dialog(["zenity", "--question", "--title", title, "--text", text,
                             "--width", "520"])
        return rc == 0
    return False


def menu(options: list[str], text: str) -> str | None:
    if YAD:
        cmd = ["yad", "--list", "--title", TITLE, "--text", text,
               "--column", "Action", "--no-headers", "--width", "460",
               "--height", str(150 + 34 * len(options)), "--center",
               "--separator=", "--button", "OK:0", "--button", "Quit:1"]
        rc, out = _run_dialog(cmd + options)
    elif ZENITY:
        cmd = ["zenity", "--list", "--title", TITLE, "--text", text,
               "--column", "Action", "--hide-header", "--width", "460",
               "--height", str(80 + 32 * len(options))]
        rc, out = _run_dialog(cmd + options)
    else:
        print(text)
        for i, o in enumerate(options, 1):
            print(f"  {i}. {o}")
        try:
            n = int(input("> ")) - 1
            return options[n] if 0 <= n < len(options) else None
        except (ValueError, EOFError):
            return None
    if rc != 0 or not out:
        return None
    line = out.splitlines()[0].strip()
    # yad's default separator is "|" even with a single column; drop it.
    if "|" in line:
        line = line.split("|", 1)[0].strip()
    return line or None


def pick_file(title: str, start: str | None, patterns: str) -> str | None:
    start = start or str(Path.home())
    filters: list[str] = []
    for line in patterns.splitlines():
        if line.strip():
            filters += ["--file-filter", line]
    if YAD:
        cmd = ["yad", "--file", "--title", title, "--filename", start] + filters + [
            "--width", "760", "--height", "520"]
    elif ZENITY:
        cmd = ["zenity", "--file-selection", "--title", title,
               "--filename", start + ("/" if Path(start).is_dir() else "")] + filters
    else:
        return None
    rc, out = _run_dialog(cmd)
    return out if rc == 0 and out else None


def pick_dir(title: str, start: str | None) -> str | None:
    start = start or str(Path.home())
    if YAD:
        cmd = ["yad", "--file", "--directory", "--title", title,
               "--filename", start, "--width", "760", "--height", "520"]
    elif ZENITY:
        cmd = ["zenity", "--file-selection", "--directory", "--title", title,
               "--filename", start + "/"]
    else:
        return None
    rc, out = _run_dialog(cmd)
    return out if rc == 0 and out else None


class Progress:
    """A pulsating yad/zenity progress window that follows build stages."""

    def __init__(self, text: str):
        self.proc = None
        self.closed = False
        if PROGRESS_TOOL == "yad":
            cmd = ["yad", "--progress", "--pulsate", "--auto-close", "--no-cancel",
                   "--title", TITLE, "--text", text, "--width", "560",
                   "--center", "--skip-taskbar"]
        elif PROGRESS_TOOL == "zenity":
            cmd = ["zenity", "--progress", "--pulsate", "--auto-close", "--no-cancel",
                   "--title", TITLE, "--text", text, "--width", "560"]
        else:
            print(text, flush=True)
            return
        try:
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                         text=True, bufsize=1)
        except OSError:
            self.proc = None

    def stage(self, text: str) -> None:
        if self.proc is None or self.closed:
            print(f"== {text}", flush=True)
            return
        try:
            self.proc.stdin.write("# " + text.replace("\n", " ") + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def finish(self) -> None:
        if self.proc is None or self.closed:
            return
        self.closed = True
        try:
            self.proc.stdin.write("100\n")
            self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            try:
                self.proc.kill()
            except OSError:
                pass


def tail(path: Path, n: int = 30) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(lines[-n:])


class Launcher:
    def __init__(self) -> None:
        self.settings = core.load_settings()
        self.work = self.settings.get("work") or str(core.default_work())
        self.iso = self.settings.get("iso") or ""
        self.fonts = self.settings.get("fonts") or ""
        self.sdl3 = self.settings.get("sdl3") or ""
        if self.sdl3 and not Path(self.sdl3).is_dir():
            self.sdl3 = ""

    def save(self) -> None:
        self.settings.update(work=self.work, iso=self.iso,
                             fonts=self.fonts, sdl3=self.sdl3)
        core.save_settings(self.settings)

    # -- settings ----------------------------------------------------------
    def choose_iso(self) -> bool:
        path = pick_file("Choose your Custom Robo (USA) disc image", self.iso,
                         "Disc images | *.iso *.rvz *.wia *.gcm *.wbfs *.dol\nAll files | *")
        if not path:
            return False
        self.iso = path
        self.save()
        return True

    def choose_work(self) -> None:
        path = pick_dir("Choose a working folder for the build", self.work)
        if path:
            self.work = path
            self.save()

    def choose_fonts(self) -> None:
        path = pick_dir("Choose Dolphin's Sys/GC folder "
                        "(it contains font_western.bin)", self.fonts or self.work)
        if not path:
            return
        try:
            core.install_fonts(Path(self.work), Path(path))
        except Exception as e:  # noqa: BLE001
            error(str(e))
            return
        self.fonts = path
        self.save()
        info(f"Console fonts installed in:\n{Path(self.work) / 'fonts'}")

    def ensure_fonts(self) -> bool:
        try:
            if core.install_fonts(Path(self.work), Path(self.fonts) if self.fonts else None):
                return True
        except Exception:  # noqa: BLE001
            pass
        if not ask("Dolphin's GC system files were not found.\n\n"
                   "They are needed for the console's boot fonts.\n"
                   "Install Dolphin, or choose its Sys/GC folder now."):
            return False
        path = pick_dir("Choose Dolphin's Sys/GC folder", str(Path.home()))
        if not path:
            return False
        try:
            core.install_fonts(Path(self.work), Path(path))
        except Exception as e:  # noqa: BLE001
            error(str(e))
            return False
        self.fonts = path
        self.save()
        return True

    def check_build_tools(self) -> bool:
        missing = [x for x in ("cmake", "ninja", "clang++") if not shutil.which(x)]
        if missing:
            error("These build tools are missing:\n\n  " + "\n  ".join(missing) +
                  "\n\nInstall them with your package manager "
                  "(for Bazzite: rpm-ostree install cmake ninja-build clang), "
                  "then start the launcher again.")
            return False
        return True

    # -- actions -----------------------------------------------------------
    def build(self) -> None:
        if not self.iso or not Path(self.iso).is_file():
            if not self.choose_iso():
                return
        if not self.check_build_tools():
            return
        if not self.ensure_fonts():
            return
        work = Path(self.work)
        work.mkdir(parents=True, exist_ok=True)
        log = work / "build.log"

        prog = Progress("Preparing the build...")
        try:
            exe = core.build(self.iso, self.work,
                             sdl3=self.sdl3 or None,
                             fonts=self.fonts or None,
                             progress=prog.stage)
        except Exception as e:  # noqa: BLE001
            prog.finish()
            detail = tail(log)
            error(f"{e}\n\nLast lines of the build log:\n\n{detail}")
            return
        prog.finish()
        self.save()
        if ask(f"The build finished.\n\n{exe}\n\nStart the game now?"):
            self.run()

    def run(self) -> None:
        exe = Path(self.work) / "recomp-build" / ("wiiboot.exe" if os.name == "nt" else "wiiboot")
        if not exe.is_file():
            if ask("The game has not been built yet.\n\nBuild it now?"):
                self.build()
            return
        try:
            core.install_fonts(Path(self.work), Path(self.fonts) if self.fonts else None)
            core.run_game(self.work, sdl3=self.sdl3 or None, detached=True)
        except Exception as e:  # noqa: BLE001
            error(str(e))
            return
        info("Custom Robo is starting.\n\n"
             "Controls: keyboard and any SDL game controller.\n"
             "The save file is kept in the working folder under memcard/.")

    def open_work(self) -> None:
        Path(self.work).mkdir(parents=True, exist_ok=True)
        try:
            subprocess.Popen(["xdg-open", self.work],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            info(self.work)

    def main(self) -> int:
        if not (YAD or ZENITY):
            error("This launcher needs yad or zenity for its dialogs.\n\n"
                  "Install one of them and try again.")
            return 1
        while True:
            choice = menu([
                "Build from disc image",
                "Run game",
                "Choose working folder",
                "Install console fonts from Dolphin",
                "Open working folder",
                "Quit",
            ], f"Disc image: {self.iso or '(not chosen)'}\n"
               f"Working folder: {self.work}\n\n"
               "Build extracts your disc, recompiles the game natively, "
               "and compiles it for this computer.")
            if choice is None or choice == "Quit":
                break
            if choice == "Build from disc image":
                self.build()
            elif choice == "Run game":
                self.run()
            elif choice == "Choose working folder":
                self.choose_work()
            elif choice == "Install console fonts from Dolphin":
                self.choose_fonts()
            elif choice == "Open working folder":
                self.open_work()
        return 0


if __name__ == "__main__":
    raise SystemExit(Launcher().main())
