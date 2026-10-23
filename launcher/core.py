#!/usr/bin/env python3
"""Shared build/run core for the Custom Robo launchers.

The launchers are thin: the AppImage and the Windows package carry the port's
tools, wiikit and (for Linux) SDL3 + GL headers, but not a compiler.  This
module turns a user's disc image into a running native build.

    python3 core.py build --iso "Custom Robo.iso" --work ~/.local/share/custom-robo
    python3 core.py run   --work ~/.local/share/custom-robo
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

FONT_FILES = ("font_western.bin", "font_japanese.bin", "dsp_coef.bin")


# ---------------------------------------------------------------------------
# paths


def bundle_root() -> Path:
    """The directory holding launcher/, project/, and optional sdl3/ and gl/."""
    env = os.environ.get("CUSTOM_ROBO_BUNDLE")
    if env:
        return Path(env).resolve()
    here = Path(__file__).resolve().parent          # .../launcher
    if (here / "project").is_dir():
        return here
    return here.parent


def project_root() -> Path:
    env = os.environ.get("CUSTOM_ROBO_PROJECT")
    if env:
        return Path(env).resolve()
    root = bundle_root()
    for candidate in (root / "project", root):
        if (candidate / "wiikit").is_dir():
            return candidate
    raise RuntimeError("the port's source (wiikit/ and tools/) is missing from this package")


def default_work() -> Path:
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(base) / "CustomRoboLauncher"
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "custom-robo"


def settings_path() -> Path:
    if os.name == "nt":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
    else:
        base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "custom-robo" / "launcher.json"


def load_settings() -> dict:
    try:
        return json.loads(settings_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_settings(data: dict) -> None:
    p = settings_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# environment


def find_fonts_dir(work: Path) -> Path | None:
    """A Dolphin Sys/GC directory with the three files wiiboot needs."""
    work = Path(work)
    if all((work / "fonts" / n).is_file() for n in FONT_FILES):
        return work / "fonts"

    home = Path.home()
    candidates: list[Path] = []
    root = bundle_root()
    candidates.append(root / "build" / "fonts")
    if os.name == "nt":
        for base in (os.environ.get("APPDATA"), os.environ.get("LOCALAPPDATA"),
                     str(home / "AppData" / "Roaming"), str(home / "AppData" / "Local")):
            if base:
                candidates += [Path(base) / "Dolphin Emulator" / "Sys" / "GC",
                               Path(base) / "Dolphin" / "Sys" / "GC"]
        candidates += [home / "Documents" / "Dolphin Emulator" / "Sys" / "GC"]
    else:
        candidates += [
            home / ".local" / "share" / "dolphin" / "Sys" / "GC",
            home / ".var" / "app" / "org.DolphinEmu.dolphin-emu" / "data" / "dolphin-emu" / "Sys" / "GC",
            Path("/usr/share/dolphin-emu/Sys/GC"),
            Path("/usr/share/dolphin/Sys/GC"),
        ]
        candidates += [Path(p) for p in glob.glob(
            str(home / ".local/share/flatpak/app/org.DolphinEmu.dolphin-emu/*/*/files/share/dolphin-emu/Sys/GC"))]
    for d in candidates:
        if all((d / n).is_file() for n in FONT_FILES):
            return d
    return None


def install_fonts(work: Path, source: Path | None = None) -> Path:
    work = Path(work)
    dst = work / "fonts"
    dst.mkdir(parents=True, exist_ok=True)
    src = Path(source) if source else find_fonts_dir(work)
    if src is None:
        raise RuntimeError(
            "Dolphin's GC system files were not found.\n\n"
            "Install Dolphin, or point the launcher at a folder containing "
            "font_western.bin, font_japanese.bin and dsp_coef.bin."
        )
    if src.is_file():
        src = src.parent
    if src.resolve() == dst.resolve():
        return dst
    missing = [n for n in FONT_FILES if not (src / n).is_file()]
    if missing:
        raise RuntimeError(f"{src} is missing: {', '.join(missing)}")
    for n in FONT_FILES:
        shutil.copy2(src / n, dst / n)
    return dst


def sdl3_dirs() -> list[Path]:
    root = bundle_root()
    out = [root / "sdl3", root / "deps" / "sdl3"]
    if os.name != "nt":
        out.append(Path.home() / ".local" / "opt" / "sdl3")
        out += [Path("/usr"), Path("/usr/local")]
    return out


def sdl3_cmake_dir(d: Path) -> Path | None:
    d = Path(d)
    for cfg in (d / "lib64" / "cmake" / "SDL3", d / "lib" / "cmake" / "SDL3",
                d / "cmake" / "SDL3", d / "SDL3"):
        if cfg.is_dir():
            return cfg
    return None


def find_sdl3(override: str | None = None) -> Path:
    candidates = [Path(override)] if override else []
    env = os.environ.get("SDL3_DIR")
    if env:
        candidates.append(Path(env))
    candidates += sdl3_dirs()
    for d in candidates:
        if d and sdl3_cmake_dir(d):
            return d
    raise RuntimeError(
        "SDL3 development files were not found.\n\n"
        "On Linux, install SDL3-devel or unpack it in ~/.local/opt/sdl3.\n"
        "On Windows, install the SDL3 VC/development package and choose its "
        "folder in the launcher."
    )


def find_gl_include(override: str | None = None) -> Path | None:
    root = bundle_root()
    for d in ([Path(override)] if override else []) + [
            root / "gl" / "include", root / "deps" / "gl" / "include",
            Path.home() / ".local" / "opt" / "gl" / "include"]:
        if (d / "GL" / "glcorearb.h").is_file():
            return d
    return None


def bundled_tool(name: str) -> str | None:
    """The CMake/Ninja copy carried by the AppImage or Windows package."""
    root = bundle_root()
    exe = name + (".exe" if os.name == "nt" else "")
    if name == "cmake":
        candidates = [root / "deps" / "cmake" / "bin" / exe,
                      root / "tools" / "cmake" / "bin" / exe]
    elif name == "ninja":
        candidates = [root / "deps" / exe, root / "deps" / "ninja" / exe,
                      root / "tools" / exe]
    else:
        candidates = []
    for p in candidates:
        if p.is_file():
            return str(p)
    return None


def check_tool(name: str, override: str | None = None) -> str:
    if override:
        return override
    p = bundled_tool(name) or shutil.which(name)
    if not p:
        raise RuntimeError(f"{name} was not found (the bundled copy is missing too)")
    return p


def python_exe() -> str:
    return sys.executable or check_tool("python3")


# ---------------------------------------------------------------------------
# running


def _append(path: Path, text: str) -> None:
    with open(path, "a", encoding="utf-8", errors="replace") as f:
        f.write(text)


def run(cmd: list[str], log: Path, env: dict | None = None, cwd: Path | None = None) -> None:
    pretty = " ".join(str(c) for c in cmd)
    _append(log, f"\n$ {pretty}\n")
    with open(log, "a", encoding="utf-8", errors="replace") as f:
        r = subprocess.run([str(c) for c in cmd], stdout=f, stderr=subprocess.STDOUT,
                           env=env, cwd=str(cwd) if cwd else None)
    if r.returncode:
        raise RuntimeError(f"command failed ({r.returncode}): {pretty}\n\nSee {log}")


def build_env(project: Path, sdl3: Path, gl_include: Path | None) -> dict:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(project) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    # Let CMake find a bundled Ninja (it only searches PATH for the generator).
    tool_dirs = [str(d) for d in (bundle_root() / "deps" / "cmake" / "bin",
                                  bundle_root() / "deps") if d.is_dir()]
    if tool_dirs:
        env["PATH"] = os.pathsep.join(tool_dirs) + os.pathsep + env.get("PATH", "")
    if os.name == "nt":
        env["CMAKE_PREFIX_PATH"] = str(sdl3) + (os.pathsep + env["CMAKE_PREFIX_PATH"] if env.get("CMAKE_PREFIX_PATH") else "")
        for p in (sdl3 / "bin", sdl3 / "lib"):
            if p.is_dir():
                env["PATH"] = str(p) + os.pathsep + env.get("PATH", "")
        if gl_include:
            env["CUSTOM_ROBO_GL_INCLUDE"] = str(gl_include)
    else:
        pkg = sdl3 / "lib64" / "pkgconfig"
        if not pkg.is_dir():
            pkg = sdl3 / "lib" / "pkgconfig"
        env["PKG_CONFIG_PATH"] = str(pkg) + (os.pathsep + env["PKG_CONFIG_PATH"] if env.get("PKG_CONFIG_PATH") else "")
        env["CMAKE_PREFIX_PATH"] = str(sdl3) + (os.pathsep + env["CMAKE_PREFIX_PATH"] if env.get("CMAKE_PREFIX_PATH") else "")
        lib = sdl3 / "lib64"
        if not lib.is_dir():
            lib = sdl3 / "lib"
        env["LD_LIBRARY_PATH"] = str(lib) + (os.pathsep + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    return env


# ---------------------------------------------------------------------------
# the build


def build(iso: str, work: str, *, source: str | None = None, log_path: str | None = None,
          sdl3: str | None = None, gl_include: str | None = None,
          fonts: str | None = None, clean: bool = False, progress=None) -> Path:
    """Extract, recompile and compile.  Returns the wiiboot executable."""
    project = Path(source).resolve() if source else project_root()
    work = Path(work).expanduser().resolve()
    work.mkdir(parents=True, exist_ok=True)
    log = Path(log_path).expanduser() if log_path else work / "build.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("", encoding="utf-8")

    py = python_exe()
    cmake = check_tool("cmake")
    ninja = check_tool("ninja")
    cxx = os.environ.get("CXX") or check_tool("clang++")
    sdl = find_sdl3(sdl3)
    gl = find_gl_include(gl_include)
    env = build_env(project, sdl, gl)

    def step(msg: str):
        _append(log, f"\n== {msg}\n")
        if progress:
            progress(msg)

    iso_p = Path(iso).expanduser().resolve()
    if not iso_p.is_file():
        raise RuntimeError(f"disc image not found: {iso_p}")

    # Do this before the long compile so a missing boot ROM fails early.
    install_fonts(work, Path(fonts) if fonts else None)

    extract = work / "extract"
    recomp = work / "recomp"
    builddir = work / "recomp-build"

    if clean:
        for d in (extract, recomp, builddir):
            shutil.rmtree(d, ignore_errors=True)

    step("Extracting the disc")
    shutil.rmtree(extract, ignore_errors=True)
    run([py, "-m", "wiikit.disc", str(iso_p), "--extract", str(extract)], log, env, project)
    dol = extract / "sys" / "main.dol"
    if not dol.is_file():
        raise RuntimeError("the disc image has no sys/main.dol")

    step("Naming the functions")
    names_src = project / "tools" / "names-hooks.txt"
    names = work / "names.tsv"
    if not names_src.is_file():
        raise RuntimeError(f"the hook name table is missing: {names_src}")
    shutil.copy2(names_src, names)

    step("Recompiling the game")
    run([py, "-m", "wiikit.recomp", str(dol), "--out", str(recomp),
         "--symbols", str(names), "--hooks", str(project / "tools" / "crbr-hooks.txt")],
        log, env, project)

    step("Configuring the native build")
    flags = "-O1"
    if gl:
        flags += f' -I"{gl}"'
    cm_args = [cmake, "-S", str(recomp), "-B", str(builddir), "-G", "Ninja",
               f"-DCMAKE_MAKE_PROGRAM={ninja}",
               f"-DCMAKE_CXX_COMPILER={cxx}", "-DCMAKE_BUILD_TYPE=Release",
               f"-DCMAKE_CXX_FLAGS_RELEASE={flags}",
               f"-DWIIKIT_EXTRA={project / 'tools' / 'crbr.cmake'}"]
    if os.name == "nt":
        cfg = sdl3_cmake_dir(sdl)
        if cfg:
            cm_args.append(f"-DSDL3_DIR={cfg}")
    run(cm_args, log, env, project)

    step("Compiling the game (this takes a few minutes)")
    run([ninja, "-C", str(builddir)], log, env, project)

    step("Installing the console fonts")
    install_fonts(work, None)

    exe = builddir / ("wiiboot.exe" if os.name == "nt" else "wiiboot")
    if not exe.is_file():
        raise RuntimeError(f"the build did not produce {exe}")
    _append(log, f"\n== built: {exe}\n")
    return exe


def run_game(work: str, *, source: str | None = None, sdl3: str | None = None,
             extra: list[str] | None = None, detached: bool = False):
    work = Path(work).expanduser().resolve()
    project = Path(source).resolve() if source else project_root()
    exe = work / "recomp-build" / ("wiiboot.exe" if os.name == "nt" else "wiiboot")
    if not exe.is_file():
        raise RuntimeError("the game has not been built yet")
    extract = work / "extract"
    fonts = work / "fonts"
    if not extract.is_dir():
        raise RuntimeError("the extracted disc is missing; build again")
    if not all((fonts / n).is_file() for n in FONT_FILES):
        install_fonts(work)
    sdl = find_sdl3(sdl3)
    env = build_env(project, sdl, find_gl_include(None))
    cmd = [str(exe), str(extract), "--fonts", str(fonts)]
    names = work / "names.tsv"
    if names.is_file():
        cmd += ["--symbols", str(names)]
    if extra:
        cmd += extra
    if not any(a in ("--window", "--fullscreen") for a in (extra or [])):
        cmd += ["--window", "1280x720"]
    if detached:
        runlog = work / "run.log"
        with open(runlog, "w", encoding="utf-8", errors="replace") as f:
            p = subprocess.Popen(cmd, env=env, cwd=str(work),
                                 stdout=f, stderr=subprocess.STDOUT,
                                 start_new_session=(os.name != "nt"))
        # Catch a missing library or bad argument instead of failing silently.
        time.sleep(1.5)
        if p.poll() is not None and p.returncode != 0:
            try:
                text = runlog.read_text(encoding="utf-8", errors="replace")
            except OSError:
                text = ""
            raise RuntimeError(f"the game exited immediately ({p.returncode}).\n\n"
                               + "\n".join(text.splitlines()[-20:]))
        return p
    return subprocess.run(cmd, env=env, cwd=str(work))


# ---------------------------------------------------------------------------
# CLI (used by the Windows launcher)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build")
    b.add_argument("--iso", required=True)
    b.add_argument("--work", default=str(default_work()))
    b.add_argument("--source")
    b.add_argument("--log")
    b.add_argument("--sdl3")
    b.add_argument("--gl-include")
    b.add_argument("--fonts")
    b.add_argument("--clean", action="store_true")

    r = sub.add_parser("run")
    r.add_argument("--work", default=str(default_work()))
    r.add_argument("--source")
    r.add_argument("--sdl3")
    r.add_argument("--detach", action="store_true")
    r.add_argument("args", nargs=argparse.REMAINDER)

    f = sub.add_parser("fonts")
    f.add_argument("--work", default=str(default_work()))
    f.add_argument("--source")

    a = ap.parse_args(argv)
    try:
        if a.cmd == "build":
            exe = build(a.iso, a.work, source=a.source, log_path=a.log, sdl3=a.sdl3,
                        gl_include=a.gl_include, fonts=a.fonts, clean=a.clean,
                        progress=lambda m: print(f"== {m}", flush=True))
            print(f"built: {exe}")
        elif a.cmd == "fonts":
            print(install_fonts(Path(a.work), Path(a.source) if a.source else None))
        else:
            extra = a.args[1:] if a.args and a.args[0] == "--" else a.args
            run_game(a.work, source=a.source, sdl3=a.sdl3, extra=extra, detached=a.detach)
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
