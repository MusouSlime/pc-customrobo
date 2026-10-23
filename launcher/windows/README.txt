Custom Robo: Battle Revolution — Windows launcher
==================================================

This is a thin launcher. It does not contain the game, a compiler, or SDL3.
It takes YOUR legally owned Custom Robo (USA) disc image, recompiles the
game for this PC with the tools below, and then runs the result.

Start it with "Custom Robo Launcher.cmd".

What you need
-------------
  * Windows 10 or 11, 64-bit
  * Python 3.10 or newer (python.org; tick "Add Python to PATH")
  * A C++ toolchain: clang++ with a working linker
  * CMake 3.20 or newer
  * Ninja
  * The SDL3 development package for the same toolchain
  * Dolphin installed once (the launcher needs its Sys\GC files:
    font_western.bin, font_japanese.bin, dsp_coef.bin)

Recommended: MSYS2 (UCRT64)
---------------------------
  1. Install MSYS2 from https://www.msys2.org/
  2. Open "MSYS2 UCRT64" and run:

       pacman -Syu
       pacman -S mingw-w64-ucrt-x86_64-clang \
                 mingw-w64-ucrt-x86_64-cmake \
                 mingw-w64-ucrt-x86_64-ninja \
                 mingw-w64-ucrt-x86_64-SDL3 \
                 python

  3. Start "Custom Robo Launcher.cmd" from that same MSYS2 UCRT64 shell.
  4. In the launcher, set "SDL3 folder" to C:\msys64\ucrt64.
     (The launcher checks lib\cmake\SDL3 and cmake\SDL3.)

If you use Visual Studio's LLVM/clang, install the SDL3 VC development
package and choose the folder that contains cmake\SDL3. Run the launcher
from an "x64 Native Tools Command Prompt for VS" so the compiler and linker
environment is set up.

Notes
-----
  * The port's Windows build path exists in wiikit, but has had less testing
    than the Linux build. If compilation fails, the log panel shows the exact
    command and error; that is the place to start.
  * Saves are written under the working folder in memcard\A.raw.
  * All content is unlocked by default. Set CRBR_UNLOCK=0 before Run to use
    normal progression.
  * The launcher never uploads or includes your disc image. The working
    folder contains files extracted from it; keep it private.

Folder layout
-------------
  Custom Robo Launcher.cmd
  launcher\core.py                  shared build/run logic
  launcher\windows\...              this GUI
  project\wiikit\                   static recompiler and runtime
  project\tools\                    port hooks and build files
  deps\gl\include\GL\               OpenGL headers for the runtime
