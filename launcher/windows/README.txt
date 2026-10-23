Custom Robo: Battle Revolution — Windows launcher
==================================================

This package is self-contained for building the game. It takes YOUR legally
owned Custom Robo (USA) disc image, recompiles the game for this PC with the
tools in this folder, and then runs the result.

Start it with "Custom Robo Launcher.cmd".

What you need
-------------
  * Windows 10 or 11, 64-bit
  * Your Custom Robo (USA) disc image
  * Dolphin installed once, for its Sys\GC files:
    font_western.bin, font_japanese.bin, dsp_coef.bin

No MSYS2, Visual Studio, Python, CMake, Ninja or SDL3 installation is needed.
The package carries:

  * Python 3.12 (embeddable)
  * clang 23 / llvm-mingw, UCRT x86_64
  * SDL3 3.4.18 development files and SDL3.dll
  * CMake 3.31.6
  * Ninja 1.12.1
  * The OpenGL headers

The launcher runs `launcher\core.py` with `deps\python\python.exe`, uses
`deps\llvm-mingw\bin\clang++.exe`, and points CMake at `deps\sdl3`. The
"Install Python" button remains available if you prefer a system Python, but
the bundled copy is used first.

Notes
-----
  * The port's Windows build path exists in wiikit, but has had less testing
    than the Linux build. If compilation fails, the log panel shows the exact
    command and error; that is the place to start.
  * Saves are written under the working folder in memcard\A.raw.
  * The **Unlock all robos, parts and stages** checkbox is on by default.
    Turn it off before Run for normal progression; `CRBR_UNLOCK=0` does the
    same if you run `core.py` directly.
  * The launcher never uploads or includes your disc image. The working
    folder contains files extracted from it; keep it private.

Folder layout
-------------
  Custom Robo Launcher.cmd
  launcher\core.py                  shared build/run logic
  launcher\windows\...              this GUI
  project\wiikit\                   static recompiler and runtime
  project\tools\                    port hooks and build files
  deps\python\                      bundled Python 3.12
  deps\llvm-mingw\                  bundled clang + UCRT sysroot
  deps\sdl3\                        bundled SDL3 development files
  deps\cmake\                       bundled CMake
  deps\ninja.exe                    bundled Ninja
  deps\gl\include\GL\               OpenGL headers for the runtime

Third-party licenses are next to their components under deps\.
