# Next session

The disc. Everything else is ready: the toolchain is checked end to end
(`tools/test_pipeline.sh`), and the port's layer and scripts are in place.

## 1. The disc

```sh
python -m wiikit.disc "Custom Robo (USA).rvz" --info
python -m wiikit.disc "Custom Robo (USA).rvz" --extract build/extract
python -m wiikit.dol build/extract/sys/main.dol --info
```

What to write down in `01-disc-layout.md`:

* the file count and the size;
* **whether the DOL has a symbol table.** A stripped DOL is the norm and
  wiikit's discovery handles it, but this disc was built from a
  development tree (`IS USBServer.ini`, `dvddata - Common.lnk`,
  `debug_ascii.tpl`), so it may have kept one. If it has, the port is
  easier by a wide margin;
* the SDK: the `.comment` string, if there is one, and the library
  dates;
* the AX u-code, with `tools/axucode.py --disc "Custom Robo (USA).rvz"`
  (it runs the game in Dolphin and reads the hash Dolphin logs).

## 2. The recompile

```sh
python -m wiikit.recomp build/extract/sys/main.dol --out build/recomp \
    --symbols build/names.tsv
```

The numbers to compare with the other GameCube port: 4 222 units and no
gaps on a 2004 GameCube game.

The names come from Dolphin's signatures first:

```sh
python tools/sigmatch.py build/extract/sys/main.dol \
    --dsy /path/to/Dolphin/Sys/totaldb.dsy --out build/sig_guess.tsv
```

`tools/sigmatch.py`, `tools/fstmap.py` and `tools/names.py` are the other
port's; they are game-agnostic and can be brought over as they are
needed.

## 3. The boot

```sh
tools/build.sh
tools/run.sh --debug
```

What to expect, and what to write down in `00-sessions.md`:

* the Nintendo and Dolby screens, the memory card check (it will say
  there is no card: see `10-wiikit.md`, saving is what is missing), the
  logos, the title, the menu;
* the sound: whether it mixes, and how it compares with Dolphin;
* the frame rate, and the game at 60 Hz (this disc is NTSC).

## 4. Then

* **Saving.** The memory card, which is wiikit's work and the game's
  completion.
* **Play past the opening**: the scenarios, the battles, the parts.
* **The controller's layout.** The C stick turns the camera; the face
  buttons are A, B, X, Y; the shoulder buttons fire the weapons.
