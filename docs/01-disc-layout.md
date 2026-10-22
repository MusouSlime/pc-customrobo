# The disc

The disc is **GXCE01**, *Custom Robo* (USA), Nintendo's release of March
2004. One disc, 940 MiB. The Japanese release, *Custom Robo: Battle
Revolution* (GXCJ01), is the same game a few weeks earlier.

## What is on it

The file system's shape is known from the disc's catalog
(gcwiifst.home.blog), which lists it in full:

    apploader.img  bi2.bin  boot.bin  fst.bin  main.dol

and then the game's own files: `sound/` (the `.ssm` and `.hps` banks),
`sprite/` (the `.tpl` textures), `scenario_us/` and `scenario_jp/` (the
scenarios), `thpdemo/opening_a.thp` and `opening_b.thp` (the two movies),
`message/font.bmc`, the `.BIN` models and the rest.

**There are no REL modules.** Every game is in `main.dol`, which is what
makes the port's first step simple: wiikit's recompiler takes a DOL
directly, and there is no relocatable module to link, relocate or
recompile.

Two things in the listing are worth a second look when the disc is read:

* **The disc carries developer leftovers**: `IS USBServer.ini`,
  `dvddata - Common.lnk` (a Windows shortcut), `debug_ascii.tpl`,
  `mess_test.bmg`, `SNT_TEST.bmg`. A retail disc built from a development
  tree. Whether the executable kept symbols from that tree is the first
  question of the next session: a symbolised DOL makes the whole port
  easier.
* **`.ssm` and `.hps`**: the SDK's own sound-bank formats, the same ones
  Super Smash Bros. Melee uses. So the sound is the SDK's AX library with
  the game's own banks, and wiikit's AX is the right thing to look at.

## Reading it

```sh
python -m wiikit.disc "Custom Robo (USA).rvz" --info
python -m wiikit.disc "Custom Robo (USA).rvz" --extract build/extract
```

A GameCube image is not partitioned and not encrypted, and its offsets are
in bytes where a Wii partition's are shifted right by two. wiikit's
reader handles `.iso`, `.wbfs`, `.rvz` and `.wia`, and a GameCube disc in
any of them.

An `.rvz` compressed with zstd needs Python 3.14 (the `compression.zstd`
module); this host has 3.14.

## The runtime's needs

wiiboot wants three files that are not on the disc: the boot ROM's fonts
(`font_western.bin`, `font_japanese.bin`) and the DSP ROM's resampling
table (`dsp_coef.bin`). They are free, and Dolphin's `Sys/GC` carries
them; `tools/setup.sh` copies them into `build/fonts`, where wiiboot
looks for them (`EXTRACT_DIR/../fonts`).

## The region

The disc's fourth letter is `E`, so NTSC, 60 Hz. wiikit reads the region
from BI2 for a GameCube disc.
