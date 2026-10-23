# Launchers

Both launchers are **thin**: they contain the port's Python source, wiikit,
the port hooks, the launcher UI, CMake and Ninja, but not the game or a
prebuilt game binary. The Linux package uses the system compiler; the Windows
package carries a portable clang and SDL3 so it can build on a clean PC. You
point them at your own Custom Robo (USA) disc image; they extract it,
statically recompile the game, compile the result for your machine, and run
it.

Nothing derived from the disc is shipped in this repository or in either
package. The working folder you choose contains extracted game files; keep it
private.

## Linux — AppImage

Build it:

```sh
launcher/build-appimage.sh
# -> build/CustomRoboLauncher-x86_64.AppImage
```

The script downloads `appimagetool` once if it is not already on the system;
set `APPIMAGETOOL=/path/to/appimagetool` to use your own copy. It also needs
ImageMagick for the icon. CMake and Ninja are downloaded once into
`build/tools` and bundled into the AppImage.

Run it:

```sh
./build/CustomRoboLauncher-x86_64.AppImage
# if FUSE is unavailable:
./build/CustomRoboLauncher-x86_64.AppImage --appimage-extract-and-run
```

The launcher uses `yad` (or `zenity`) for native dialogs. It needs Python 3
and clang++; CMake, Ninja, SDL3 and the OpenGL headers are bundled, so no
CMake, Ninja or SDL3 development package is needed at run time. If Python is
missing, the AppRun bootstrap offers to install `python3` with the system
package manager. The menu also has **Install compiler (clang)**. If Dolphin is
installed, the launcher finds its `Sys/GC` fonts automatically; otherwise it
asks for the folder once.

The AppImage is intentionally small: the user's compiler produces a binary
that matches their C++ runtime and graphics stack, instead of shipping a
foreign build. CMake and Ninja are bundled because they are portable and
otherwise easy to forget.

## Windows — zip package

Build it:

```sh
launcher/build-windows-package.sh
# -> build/CustomRoboLauncher-windows.zip
```

Unzip it and run `Custom Robo Launcher.cmd`. The WinForms UI has fields for the
disc image, working folder, Dolphin fonts and the SDL3 development folder; the
last one can stay empty because SDL3 is bundled.

The Windows package is self-contained for the build: it carries Python 3.12,
clang 23 (llvm-mingw UCRT), SDL3, CMake and Ninja. You do not need MSYS2,
Visual Studio, or any separately installed Python, compiler, CMake, Ninja or
SDL3. Only Dolphin's `Sys\GC` fonts and your disc image are external. The
**Install Python** button remains as a fallback for a system Python.

The Windows build path in wiikit exists, but has had less testing than the
Linux one. If a build fails, the launcher's log panel shows the failing
command; that is the place to start.

## Shared command line

Both GUIs are front ends over `launcher/core.py`, which can also be used
directly:

```sh
python3 launcher/core.py build --iso "Custom Robo (USA).iso" \
    --work ~/.local/share/custom-robo
python3 launcher/core.py run --work ~/.local/share/custom-robo
```

Useful options:

- `--source PATH` — the port source (default: the package's `project/`).
- `--sdl3 PATH` — SDL3 tree (default: bundled, `~/.local/opt/sdl3`, or a
  system install).
- `--fonts PATH` — Dolphin's `Sys/GC`.
- `--clean` — delete the extracted disc, recompiled sources and build first.

A normal build is incremental: running it again after a change only recompiles
what changed.

## Saves and unlocks

The memory card is `WORK/memcard/A.raw`. It persists between runs. The port
unlocks all robos, parts, holosseums and the Parts Index by default. The
Linux menu's **Unlocks: on/off** item and the Windows **Unlock all robos,
parts and stages** checkbox control it per run; `CRBR_UNLOCK=0` in the
environment—or `core.py run --no-unlock`—does the same without the GUI.

## What is in the packages

```
launcher/core.py             shared extract/recompile/configure/compile/run
launcher/linux_ui.py         yad/zenity UI
launcher/windows/*.ps1       WinForms UI
project/wiikit/              recompiler and native runtime
project/tools/               port hooks, unlock writes, names-hooks.txt
deps/cmake/                  bundled CMake (both packages)
deps/ninja(.exe)             bundled Ninja (both packages)
deps/llvm-mingw/             Windows package: portable clang + UCRT sysroot
deps/sdl3/                   Windows package: SDL3 development files
deps/python/                 Windows package: embedded Python
sdl3/                        Linux package only
gl/include/GL/               OpenGL headers
```
