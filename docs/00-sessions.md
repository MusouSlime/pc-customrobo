# Session log

## Session 1 — the memory card

Goal: the game saves to a memory card, and wiikit's table of layers had
the cards as a thing still to come: the EXI's channels carried only the
boot ROM's chip, so a GameCube game could not save. The card is the
console's own, so the work is wiikit's, and it was done there (on a
branch in the submodule, `feature/gamecube-memory-card`, for upstream).

What was added to wiikit:

* **The card's storage** (`runtime/memcard.cpp`): a file in Dolphin's raw
  format — the whole card, its blocks of 8 KB, without a header of its
  own. A card that is not there yet is made and formatted, as the
  console's BIOS would format one: the header block, two directory
  blocks and two block allocation tables, the rest empty. The format is
  the SDK's: the serial, the time of the format, the size, and the
  checksums the SDK's own card code verifies before it uses a card.

* **The EXI device** that speaks the card's protocol: the size (the
  command 0x00), the status (0x83), the card's own id (0x85), the
  reads (0x52) and the writes (0xF2), the erase (0xF1) and the chip
  erase (0xF4), and the interrupt the card raises.

* **The u-code that unlocks it.** The SDK loads a second micro-code into
  the DSP to unlock the card (Dolphin's CARD u-code, hash 0x65d6cc6f).
  wiikit's DSP now parses the SDK's boot task — the ten mails, a tag and
  a value in five pairs — and hashes the u-code the way the DSP's own
  hardware does, so that the card's u-code is known when it is booted.
  The runtime then answers it as the SDK expects: it announces itself
  (0xDCD10000), the CPU starts it with 0xFF000000, and it answers
  0xDCD10003 when the card is unlocked.

  The card is unlocked from the start, as it is in Dolphin: the real
  card's handshake, which the micro-code's own work carries out, is not
  needed, and the SDK cannot tell the difference.

* **The EXI's status register** now answers the external-device bit (a
  card is there) and the card's interrupt, and the channel's chip select
  releases the card when it changes.

How it was checked: `tools/test_memcard.sh` drives the EXI's registers
the way the SDK drives them and checks the card's answers, its blocks
and the file it is in — the size, the status, a block written and read
back, the data in the file, and the header's, the directory's and the
table's checksums, which are the ones the SDK's card code verifies:

    the card is present (the status' EXT bit)      ok
    the card answers 0x10 (251 blocks)             ok
    the card is ready                              ok
    the card is unlocked                           ok
    the block reads back as it was written         ok
    the block is in the card's file                ok
    the header's checksums are right               ok
    the directory's checksums are right            ok
    the table's checksums are right                ok
    the table says 251 free blocks                 ok

    PASS

Two things the test found, both of them worth knowing:

* **The EXI's DMA moves whole 32-byte units.** The length register is
  masked to a multiple of 32, so a transfer of 26 bytes moves none.
* **The card's checksum is a sum kept in the card's own order.** The
  console compares the sums byte-swapped, and a sum of 0xFFFF means
  none; getting that wrong makes a card the SDK rejects.

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

# Session 2: the card screen, saving, and the disc

## The black memory card screen

The screen was not blank: the game was drawing a dialog the whole
time ("There is no save data on the Memory Card in Slot A", then "Will
you begin without creating save data? YES / NO"). It rendered black
because of the depth range, not the card.

**The GX viewport's z range is not always inside 0..1.** This game sets
the XF viewport to `wd 320, ht -240, zRange 999*2^24, xOrig 662,
yOrig 582, farZ 1000*2^24` and lets the scissor offset (342) put the
viewport back at 0,0. The runtime's vertex shader computes
`gl_Position.z = w*farZ/2^24 + z*zRange/2^24`, which is 1..1000 for
this game, not 0..1. GL clips every fragment at `z > w`, so every draw
in the dialog (and any other screen using the oversized range) vanished.

The fix is `glEnable(GL_DEPTH_CLAMP)` in `setup()`. It leaves normal
depth ranges alone and turns near/far clipping off for the oversized
ones, so those fragments reach the depth buffer (clamped to 1.0).
That is enough for the 2D screens, which draw with the depth test off.
A fuller fix (remapping the range in the vertex shader as Dolphin does)
matters only if a 3D scene z-fights; none is known yet.

A second trap found on the way: the shader cache is keyed by the GX
register configuration, not by the generator. After changing
`gxshader.cpp`, delete `build/shadercache` or the old binary is reused.

Debug switches added while chasing this (all opt-in):
`WIIKIT_VTXLOG` (every vertex of a draw), `WIIKIT_NOCULL`,
`WIIKIT_FORCEWHITE` (force the TEV output red), and the drawlog now
prints the scissor, its offset, texmap 0 and the TEV env registers.

## The card

The mount now completes (`__CARDMountCallback(0) result 0`,
`CARDMountAsync(0) -> 0`, `CARDCheckExAsync(0) -> 0`) and the game
reaches its card dialog. The card is formatted but has no `GXCE`
directory, so the game offers to start without saving. Creating the
save is the next piece of work.

# Session 3: saves, battles, and content

Saving now completes end to end. The missing piece was the EXI interrupt:
`exi_irq()` had to assert `PI_EXI` when the card had an interrupt pending and
the EXI mask was set. With that, `__CARDExiHandler`, `__CARDWritePage` and
`__CARDUpdateDir` run, and `build/memcard/A.raw` contains the `GXCE01`
directory entry and the `CustomRobo-BattleRevolution` file (start block 5,
15 blocks).

A battle loads and renders: Vs. Mode -> Single Battle -> P1 vs CPU -> 3-Set
Match -> Basic Arena gives a working 1P vs CPU match (1000 HP each, 120 s).

The USA unlock table is applied in `tools/crbr.cpp` on `VIWaitForRetrace`
(default on; `CRBR_UNLOCK=0` restores normal progression):

    0x80321D44 = 0xFFFFFFFF   Unlock Bonuses
    0x803BF79C/7BC/7DC/7FC    all bodies/guns/bombs/pods (Arcade & Vs.)
    0x803BF81C = 0x0002FFFF   all legs
    0x803BF83C = 0x0003FFFF   all holosseums (Vs.)
    0x803BFB9C/BBC/BDC/BFC/1C shop stock for all parts
    0x803BF8EC..90C           every Parts Glossary entry

Verified in game: Vs. Mode stage select shows the nine Vs. holosseums;
Parts Glossary shows real names and models for bodies and guns instead of
`???`; Arcade Mode and Parts Index are available. The remaining stage-select
slots are story-only placeholders, not Vs. holosseums.

# Session 4: launchers

The launchers are thin. They carry the port's Python tools, wiikit, the port
hooks and a minimal hook-name table, but no game data, no compiler and no
prebuilt game binary. They take the user's own disc image and do the whole
pipeline in a writable working folder:

    extract -> recompile -> CMake/Ninja compile -> install fonts -> run

`launcher/core.py` is the shared implementation. `launcher/linux_ui.py`
drives it with yad (or zenity); `launcher/windows/CustomRoboLauncher.ps1`
drives it with WinForms.

**What the packages carry.** The Linux AppImage bundles the project source,
`tools/names-hooks.txt`, SDL3 and the OpenGL headers (about 10 MiB unpacked,
3.2 MiB compressed). The Windows zip carries the source, the WinForms UI and
the GL headers; the user supplies the SDL3 development package that matches
their compiler.

**Why a minimal name table.** The recompiler only needs names to resolve the
runtime and port hooks. `tools/names-hooks.txt` contains the 26 hook names
that exist in this DOL; recompiling with it still reports the same 80 resolved
switch tables as the full `build/names.tsv` (26 hooks, 0 data symbols). The
full 633-name table is derived from the disc and stays in `build/`.

**Builds and runs.** A build from the ISO through `core.py` was tested into a
clean working folder: 3558 units, 80 switch tables, 84 Ninja targets, working
`wiiboot`. Both the repository SDL3 and the AppImage's bundled SDL3 launch the
game; `run.log` catches an immediate missing-library failure instead of the
launcher closing silently. The AppImage UI was started with
`--appimage-extract-and-run` and stayed up with its menu.

**Windows.** wiikit already has `_WIN32` paths in `os.cpp`, `mem.cpp` and the
CMake (`winmm`), and the WinForms launcher is complete, but no Windows build
has been run on this host. The package therefore says so in its README and
shows the failing compiler command in the log panel. Recommended environment:
MSYS2 UCRT64 with clang, CMake, Ninja, SDL3 and Python.

**Saves and unlocks.** The working card is `WORK/memcard/A.raw`; the launcher
does not reset it. The unlock writes remain default-on (`CRBR_UNLOCK=0`
restores normal progression).
