# The executable

`sys/main.dol`: the game's own code, and (with the SDK it links) most of
everything else.

## What is known before the disc is read

* **One DOL, no RELs.** The whole game is in it, with the SDK's libraries
  (os, gx, pad, dvd, card, ar, ax, thp) linked in.
* **Stripped, most likely.** Retail GameCube executables are. wiikit
  handles that: its discovery finds the functions from the code, and the
  names come from elsewhere (see below).
* **2004, so the SDK of 2003-2004.** That matters for one thing: the AX
  u-code the game boots, and the parameter block's layout that goes with
  it (see `10-wiikit.md`).

## The names of a stripped executable

A stripped DOL has no symbol table, and the recompiler needs the names
for two things: the hook list (the runtime replaces some functions by
name) and the logs. wiikit's approach, as on its other ports:

* **Discovery** finds the functions from the code: the entry point, every
  `bl` target, and every stack-frame prologue after a terminator. On the
  other GameCube port this found 4 222 of 4 222 functions with no gaps.
* **Dolphin's signatures** (`Sys/totaldb.dsy`) name the SDK's functions
  by their shape: 816 names on that port.
* **The disc itself**, if it kept a symbol table of its own: the other
  port found one left on the disc (`data/rkrpg_1.fst`, another build's),
  aligned by order and size, which named 4 136 of 4 222. This disc's
  developer leftovers make it worth a look.
* **Hand-given names**, for what matters.

The tools for the last three are the other port's (`sigmatch.py`,
`fstmap.py`, `names.py`); they are game-agnostic and can be brought over
as they are needed.

## Commands

```sh
python -m wiikit.dol build/extract/sys/main.dol --info
python -m wiikit.recomp build/extract/sys/main.dol --out build/recomp \
    --symbols build/names.tsv
```

The recompiler writes its own `symbols.tsv` next to the generated code:
the units it found, named, for the runtime's logs.
