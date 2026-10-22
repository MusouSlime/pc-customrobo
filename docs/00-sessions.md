# Session log

## Session 0 — the toolchain, without the disc

Goal: make sure the whole chain works before the disc arrives, so that the
disc's arrival is the only thing between here and a running game. The
route is wiikit's static recompilation, and the host is rpm-ostree
(Bazzite), so nothing could be installed system-wide.

What was done:

* **The toolchain.** SDL3 (the window and the sound) and the OpenGL
  headers (which wiikit's runtime includes as `<GL/glcorearb.h>`) are
  unpacked from Fedora's packages into `~/.local/opt`, rather than
  installed: `tools/setup.sh` does it, and points CMake and pkg-config at
  them. Dolphin's `Sys/GC` (installed as a flatpak) carries the boot ROM's
  fonts and the DSP ROM's resampling table, which wiiboot wants in
  `build/fonts`; `tools/setup.sh` copies them.
* **The chain, checked.** `tools/make_testdisc.py` writes a synthetic
  GameCube disc whose `main.dol` is a hand-assembled PowerPC program that
  prints a line through the SDK's `__write_console` and then asks the
  console to leave. `tools/test_pipeline.sh` then runs the whole chain on
  it: `wiikit.disc` reads and extracts it, `wiikit.recomp` translates the
  PowerPC to C++, CMake and Ninja build it against SDL3, and wiiboot runs
  it. The output is the line, and the chain is whole.

  ```
  == 6. run
  wiiboot: WIITKIT TEST [GXTET0], entry 80003100
  Custom Robo test disc: the pipeline works.
  wiikit: the game asked to leave (return to menu, restart or shut down)
  PASS: the toolchain is whole.
  ```

  The game also boots with the renderer on (`--window 640x480`), which is
  what a real game needs.

* **The port's layer** (`tools/crbr.cpp`, linked in through
  `WIIKIT_EXTRA`) builds and loads: the runtime says "game layer Custom
  Robo". It holds the camera's direction for now, which is the C stick
  turning the view the way games of 2004 did.

What was learned on the way, all of it about the *test* disc and not about
the port:

* **A DOL's data section is section 7**, and its three header words sit at
  7*4, 0x48+7*4 and 0x90+7*4. The offsets of the sections are 18 words
  from the start, then the addresses, then the sizes.
* **The GameCube's FST has no header**: the root entry's size word is the
  number of entries, and the names follow the entries.
* **`__write_console` takes the size by pointer.** Its signature is the
  SDK's `int __write_console(__file_handle, u8 *buf, size_t *n, proc)`,
  so r5 points at the number of bytes, and the runtime reads it from
  there — the same way Dolphin's HLE does. A program that passes the
  length by value crashes the runtime: the hook dereferences it.
* **The runtime writes the disc's header and the arena's bounds over
  0x80000000-0x800000FC** after the DOL is loaded, so a data section
  there is overwritten. The test disc's data goes elsewhere.

Left: the disc. The port's first real session is the next one, and it
starts with the disc (`01-disc-layout.md`).
