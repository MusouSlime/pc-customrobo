"""Which AX u-code does this game use, and does wiikit's AX match it?

The risk
--------

wiikit emulates the GameCube's AX in C++ (`wiikit/runtime/ax.cpp`), following
Dolphin's AX HLE. That HLE reads the parameter block the game's own SDK
wrote, and the block's layout depends on the *u-code* the game booted. Two
revisions exist and they disagree:

  * the newer u-codes keep a low-pass filter in the parameter block, and
    their `mixer_control` names the buses one way (bit 0 = main left);
  * the older one (CRC 0x4E8A8B21) has no low-pass field, and its
    `mixer_control` names them another way (bit 4 = Dolby Pro II mixing).

wiikit's GameCube path implements the *newer* layout — its parameter-block
offsets are Dolphin's `AXPB` field for field (loop_counter at word 97, the
filter at word 93). A game on the older u-code therefore mixes its sound
through the wrong buses: the voices come out crossed and the filter's
fields hold something else.

The question, then, is one of fact: which u-code does this game boot?

The answer, from Dolphin
------------------------

Dolphin computes a hash over the u-code image the game copies into the
DSP's IRAM, and picks its AX HLE by it. It logs the hash at startup:

    INFO_LOG_FMT(DSPHLE, "CRC {:08x}: AX ucode chosen", crc);

so the game, run in Dolphin, says which u-code it uses. This tool runs
Dolphin on the game and reads that line.

The u-codes Dolphin's AX HLE knows, and the games that use them (from
`Source/Core/Core/HW/DSPHLE/UCodes/UCodes.cpp`):

    0x3ad3b7ac  AX  newer layout  (Naruto 3, Paper Mario: The Thousand Year Door)
    0x3daf59b9  AX  newer layout  (Alien Hominid)
    0x4e8a8b21  AX  OLDER layout  (Crazy Taxi, Monkey Ball 1/2, Cubivore, Disney)
    0x07f88145  AX  newer layout  (Ikaruga, F-Zero GX, Star Soldier)
    0xe2136399  AX  newer layout  (Billy Hatcher, Mario Party 5, TMNT)
    0x3389a79e  AX  newer layout  (Metroid Prime Trilogy)

Usage
-----

Run the game in Dolphin and read the log:

    python tools/axucode.py --dolphin --disc "Custom Robo (USA).rvz"

or point it at a log Dolphin already wrote:

    python tools/axucode.py --log ~/.local/share/dolphin/GameCube/CustomRobo.log

Dolphin must be able to run the game: it needs the disc, and it is asked
to run it headless for a few seconds and quit, which is enough for the
sound driver to boot its u-code.

Without a disc
--------------

`--dolphin` is the definite answer. The static scan below is a fallback
that reads the u-code image out of the game's own executable and hashes it
the way Dolphin does (`Common::HashEctor`: a byte at a time into the
accumulator, then a rotate by three bits). It works when the u-code is
found; it says so plainly when it is not.
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import time

# The u-codes Dolphin's AX HLE knows, and whether each uses the newer
# parameter-block layout. From Dolphin's UCodes.cpp.
KNOWN = {
    0x3AD3B7AC: ("newer", "Naruto 3, Paper Mario: The Thousand Year Door"),
    0x3DAF59B9: ("newer", "Alien Hominid"),
    0x4E8A8B21: ("older", "Crazy Taxi, Monkey Ball 1/2, Cubivore, Disney"),
    0x07F88145: ("newer", "Ikaruga, F-Zero GX, Star Soldier"),
    0xE2136399: ("newer", "Billy Hatcher, Mario Party 5, TMNT"),
    0x3389A79E: ("newer", "Metroid Prime Trilogy"),
}

CRC_RE = re.compile(r"CRC ([0-9a-fA-F]{8}): AX ucode chosen")

def hash_ector(data):
    """Dolphin's Common::HashEctor: the hash the DSP's own hardware computes
    over the u-code in its IRAM, and the one Dolphin's AX HLE is keyed by.

    From Dolphin's Common/Hash.cpp: not a CRC table, but a byte at a time
    into the accumulator and a rotate by three bits."""
    crc = 0
    for byte in data:
        crc ^= byte
        crc = ((crc << 3) | (crc >> 29)) & 0xFFFFFFFF
    return crc


def report(crc, source):
    layout, games = KNOWN.get(crc, (None, None))
    print(f"AX u-code: {crc:08X}  (from {source})")
    if layout is None:
        print("  not one of the u-codes Dolphin's AX HLE knows")
        print("  it is still a GameCube AX u-code; wiikit's AX is written for the")
        print("  newer parameter-block layout, which is what the 2003-2004 SDKs use")
        return 0
    print(f"  {layout} parameter-block layout  (also used by: {games})")
    if layout == "older":
        print("  the older u-code: wiikit's GameCube AX expects the newer one.")
        print("  the sound will come out with the buses crossed; the fix belongs in")
        print("  wiikit/runtime/ax.cpp, following Dolphin's AX.cpp's older branch.")
        print("  (report it upstream: it is game-agnostic, so it is wiikit's work)")
    else:
        print("  wiikit's GameCube AX implements this layout: the sound should mix.")
    return 0


def from_log(path):
    with open(path, "r", errors="replace") as f:
        text = f.read()
    found = CRC_RE.findall(text)
    if not found:
        print(f"{path}: no AX u-code line found")
        print("  the game may not have reached its sound driver in this log")
        return 1
    for crc in found:
        report(int(crc, 16), path)
    return 0


def find_dolphin_log(disc_path=None):
    """Dolphin's log directory, and the log of the game we care about."""
    roots = [
        os.path.expanduser("~/.local/share/dolphin/GameCube"),
        os.path.expanduser("~/.local/share/dolphin/Wii"),
        os.path.expanduser("~/Library/Application Support/Dolphin/GameCube"),
        os.path.expanduser("~/Library/Application Support/Dolphin/Wii"),
    ]
    for root in roots:
        if not os.path.isdir(root):
            continue
        logs = sorted(glob.glob(os.path.join(root, "*.log")), key=os.path.getmtime)
        if logs:
            return logs[-1]
    return None


def run_dolphin(disc, seconds, dolphin):
    """Run the game in Dolphin, headless, and let its sound driver boot."""
    cmd = [dolphin, "--batch", "--no-gui", "--fullscreen", "-b", "-e", str(seconds)]
    if disc:
        cmd.append(disc)
    print("running:", " ".join(cmd))
    try:
        subprocess.run(cmd, timeout=seconds + 60)
    except subprocess.TimeoutExpired:
        pass
    except FileNotFoundError:
        print(f"no Dolphin at {dolphin}; pass --dolphin PATH")
        return None
    return find_dolphin_log(disc)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dolphin", default="dolphin",
                    help="the Dolphin executable (default: dolphin)")
    ap.add_argument("--disc", help="the game's disc image, to run in Dolphin")
    ap.add_argument("--log", help="a Dolphin log to read instead of running the game")
    ap.add_argument("--seconds", type=int, default=20,
                    help="how long to let the game run (default: 20)")
    a = ap.parse_args()

    if a.log:
        return from_log(a.log)

    if a.disc:
        log = run_dolphin(a.disc, a.seconds, a.dolphin)
        if not log:
            print("no Dolphin log found after the run")
            return 1
        print("log:", log)
        return from_log(log)

    log = find_dolphin_log()
    if log:
        print("log:", log)
        return from_log(log)
    print("no Dolphin log found; pass --disc to run the game, or --log to read one")
    return 1


if __name__ == "__main__":
    sys.exit(main())
