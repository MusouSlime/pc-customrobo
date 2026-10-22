# What this port asks of wiikit

wiikit is the game-agnostic toolkit; the GameCube is the Wii's older
self, and wiikit already serves it. This page is the list of what Custom
Robo needs from it, and what it gives back.

## What wiikit already has

| The game needs | wiikit |
| --- | --- |
| The GameCube's disc (no partitions, no encryption, byte offsets) | `wiikit.disc` serves it; `runtime/disc.cpp` rebuilds it from the extracted tree |
| One `main.dol`, no REL modules | `wiikit.recomp` takes a DOL directly; no relocatable module is involved |
| A stripped executable | `recomp/discover.py` finds the functions from the code |
| The GameCube's clocks, its IPL's globals, no IOS | `runtime/boot.cpp` |
| The disc drive at its registers | `runtime/hw.cpp` (DI) |
| 16 MB of ARAM | `runtime/hw.cpp` |
| Four controllers on SI | `runtime/hw.cpp`; a standard controller on each port the host has a pad for |
| The AX mixer, over ARAM, with the SDK's parameter blocks | `runtime/ax.cpp` |
| THP movies, the SDK's own player, in the DOL | recompiled with the game |
| The window, the renderer, the sound | `runtime/video.cpp`, `runtime/audio.cpp` (SDL3, OpenGL 4.5) |

The GameCube path was validated on wiikit's other GameCube port: a 2004
game that boots, plays and sounds, at 50 frames a second.

## What it does not have, and Custom Robo wants

### 1. Memory cards (EXI and the CARD u-code)

**Done, in this port's session 1** (wiikit's branch
`feature/gamecube-memory-card`, to go upstream). The card is the
console's own, so it is wiikit's work and every GameCube port needs it:
the card's storage and its format, the EXI device that speaks its
protocol, and the u-code the SDK loads into the DSP to unlock it. See
`00-sessions.md` for what was added and how it was checked.

What the game needs of it: a card in slot A that it can write its save
to, and read back. The card is in `build/memcard/A.raw` (Dolphin's raw
format), or where wiiboot's `--memcard` says.

### 2. The AX u-code's revision

wiikit's GameCube AX implements the *newer* parameter-block layout: its
offsets are Dolphin's `AXPB` field for field (the loop counter at word
97, the low-pass filter at word 93).

Dolphin's AX knows two layouts. The older one (CRC `0x4E8A8B21`, used by
Crazy Taxi, Monkey Ball 1/2, Cubivore and Disney's games) has no
low-pass field and names the mixer buses differently. A game on that
u-code mixes its sound through the wrong buses: the voices come out
crossed.

Which u-code Custom Robo boots is a question of fact, and
`tools/axucode.py` answers it: run the game in Dolphin and read the
hash it logs (`CRC xxxxxxxx: AX ucode chosen`). A 2004 game is most
likely on one of the newer u-codes; the older one was current in
2001-2002. If it is the older one, the fix is in wiikit's `ax.cpp`,
following Dolphin's `AX.cpp`'s older branch, and it should go upstream.

### 3. Android

wiikit's renderer is OpenGL 4.5 core with GLSL 450 and SDL3: a desktop
renderer. Android's GLES 3.x is a different backend, so an Android port
means a new renderer (or a Vulkan one), which is a large piece of work
that belongs to wiikit and would serve every port.

The desktop targets — Linux, Windows, macOS — are what wiikit gives
today.

## What this port keeps for itself

`tools/crbr.cpp`, the port's layer (linked in through `WIIKIT_EXTRA`):

* **The camera's direction.** The C stick turns the camera the way games
  of 2004 did: pushed right, the view swings left. Games since turn it
  the other way, and this one has no option for it, so the port turns the
  C stick's X around. `CRBR_CAMERA=console` keeps the console's way.

`tools/memcard_test.cpp` is the port's own test of wiikit's card: it
drives the EXI's registers the way the SDK drives them. The card itself
is wiikit's; the test is the port's, because a test of it belongs with
the port that needs it.
