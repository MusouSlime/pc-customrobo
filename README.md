# pc-customrobo

Toward a native PC port of **Custom Robo** (GameCube, 2004, Noise and
StudioFAKE, published by Nintendo), by static recompilation.

The route is wiikit's: the game's own PowerPC code, translated to C++ and
built for the PC, running on a replacement for the GameCube's hardware.
Nothing is emulated at the instruction level, and nothing of the game is
rewritten.

The disc is **GXCE01**: one `main.dol`, no REL modules, one disc. The
GameCube is the Wii's older self (the same processor, GPU and DSP), and
wiikit supports it: its disc reader, its recompiler, its runtime (the
disc drive at its registers, ARAM, the controllers on SI, the AX mixer)
and its renderer all serve a GameCube game.

## BYOA — Bring Your Own Assets

This repository holds documentation and tools only. No game data, no
executables, no assets. You need your own original disc.

## Layout

    docs/     the disc, the executable, the route, the session log
    tools/    this game's tools and layer, and the port's scripts
    launcher/ the Linux AppImage and Windows launchers
    wiikit/   the game-agnostic GameCube and Wii toolkit (a submodule)
    build/    (not in git) the disc, everything derived from it, the build

## Getting started

```sh
tools/setup.sh              # SDL3, the OpenGL headers, Dolphin's fonts
tools/test_pipeline.sh      # check the toolchain, without the disc
tools/test_memcard.sh       # check the memory card, without the disc
```

Then put the disc's image in `build/` and follow `docs/01-disc-layout.md`:

```sh
python -m wiikit.disc "Custom Robo (USA).rvz" --extract build/extract
python -m wiikit.dol build/extract/sys/main.dol --info
tools/build.sh
tools/run.sh
```

The toolchain is: CMake, Ninja, a C++20 compiler (clang), SDL3 and OpenGL
4.5. On this host the packages are unpacked into `~/.local/opt` (the system
is rpm-ostree), and `tools/setup.sh` does it.

## Launchers

There are thin launchers for Linux and Windows. They carry the port's tools,
CMake and Ninja, and (on Linux) SDL3 and the OpenGL headers, ask for your own
disc image, and do the extraction, recompilation and build in a working folder.
No game data or compiled game code is included.

```sh
launcher/build-appimage.sh          # -> build/CustomRoboLauncher-x86_64.AppImage
launcher/build-windows-package.sh   # -> build/CustomRoboLauncher-windows.zip
```

The AppImage uses `yad`/`zenity` and needs Python 3 and clang installed;
CMake, Ninja and SDL3 are bundled. The Windows package uses a WinForms UI,
can install Python 3 from the launcher, and needs clang and an SDL3
development package; CMake and Ninja are bundled. See
`launcher/README.md` and `launcher/windows/README.txt`.

Both GUIs are front ends over `launcher/core.py`, which is also usable alone:

```sh
python3 launcher/core.py build --iso "Custom Robo (USA).iso" \
    --work ~/.local/share/custom-robo
python3 launcher/core.py run --work ~/.local/share/custom-robo
```

## The memory card

The game saves to a memory card, and wiikit did not have one: the EXI's
channels carried only the boot ROM's chip. The card is the console's own,
so the work was done in wiikit (on the branch
`feature/gamecube-memory-card` of the submodule, for upstream), and this
port has a test of it: `tools/test_memcard.sh` drives the EXI's registers
the way the SDK drives them and checks the card's answers, its blocks,
its checksums and the file it is in.

The card is in `build/memcard/A.raw` (Dolphin's raw format), or where
wiiboot's `--memcard` says.

## Content unlocks

The port boots with all modes, holosseums, robos and parts unlocked. This is
the USA version's own unlock table, applied through `VIWaitForRetrace` so a
menu or save load cannot take it back:

- Unlock Bonuses (`0x80321D44`)
- owned bodies/guns/bombs/pods/legs (Arcade & Vs. Mode)
- all holosseums (Vs. Mode)
- shop stock for all parts
- every Parts Glossary entry

Set `CRBR_UNLOCK=0` to boot with normal story progression instead. The
unlocks are runtime state; a normal in-game save still saves story progress.

## Status

The disc is read, recompiled (one DOL, 3558 units) and runs: it boots,
renders, plays audio, takes input, and loads a battle. Saving works on the
memory card. See `docs/00-sessions.md` for the session log.

**Session 1 — the memory card.** Done, and checked without the disc:
`tools/test_memcard.sh` passes.

**Session 0 — the toolchain.** Checked without the disc: a synthetic
GameCube disc is built, read, recompiled, built and run, and the guest's
own code prints through the runtime.

## Documentation

    00-sessions.md      the log
    01-disc-layout.md   what is on the disc
    02-executable.md    the DOL
    03-next-session.md  the plan
    10-wiikit.md        what this port asks of wiikit

## Licence

MIT. This covers the documentation and tools in this repository only. It
says nothing about Custom Robo itself, which remains the property of its
rights holders.
