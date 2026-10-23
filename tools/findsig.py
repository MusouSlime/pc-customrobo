"""Find a function in the DOL by Dolphin's signature database.

tools/sigmatch.py names the functions whose signature is in Dolphin's
database, but a function whose signature the database has under another
size (the SDK's own build differs from the one the database was made
from) is missed. This looks one name up and tries every size the
database has for it, over every candidate function.

    python tools/findsig.py OSCreateThread build/extract/sys/main.dol
"""
import argparse
import collections
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))  # wiikit/

from wiikit.dol import Image
from wiikit.ppc import decode


def checksum(words):
    """Dolphin's HashSignatureDB::ComputeCodeChecksum."""
    s = 0
    for o in words:
        op = o & 0xFC000000
        a = op >> 26
        op2 = op3 = 0
        if a == 4:
            op2 = o & 0x3F
            if op2 in (0, 8, 16, 21, 22):
                op3 = o & 0x7C0
        elif a == 19:
            op2 = o & 0x3F
            if op2 == 16:
                op3 = o & 0x1E0
        elif a == 31:
            op3 = o & 0x3FF
        elif a == 30:
            op3 = o & 0x3FF
        s = (s + op + op2 + op3) & 0xFFFFFFFF
        s = (s * 3 + (o & 0xFC000000) // 0x1000000) & 0xFFFFFFFF
    return s


def read_dsy(path):
    """{(checksum, size): name} from Dolphin's totaldb.dsy."""
    out = {}
    with open(path, "rb") as f:
        count = struct.unpack("<I", f.read(4))[0]
        for _ in range(count):
            csum, size = struct.unpack("<II", f.read(8))
            name = f.read(128).split(b"\0")[0].decode("latin1")
            out.setdefault((csum, size), name)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("name", help="the function to look for")
    ap.add_argument("dol")
    ap.add_argument("--dsy", default=os.path.expanduser(
        "~/.local/share/dolphin/Sys/totaldb.dsy"))
    ap.add_argument("--min-size", type=int, default=16)
    a = ap.parse_args()

    if not os.path.exists(a.dsy):
        print(f"no {a.dsy}: pass --dsy")
        return 1

    dsy = read_dsy(a.dsy)
    wanted = {k: v for k, v in dsy.items() if v.split(" ")[0] == a.name or v == a.name}
    if not wanted:
        print(f"{a.name}: not in the database")
        return 1
    print(f"the database has {a.name} in {len(wanted)} forms:")
    for (csum, size) in wanted:
        print(f"  size {size:#x} checksum {csum:08X}")

    img = Image(a.dol)
    # every function: the entry point and every bl target, as sigmatch does
    starts = set()
    for seg in img.text_segments():
        for off in range(0, len(seg.data) - 3, 4):
            a_ = seg.vaddr + off
            w = struct.unpack_from(">I", seg.data, off)[0]
            i = decode(w)
            if i.op == "b" and i.f.get("LK"):
                t = (a_ + (i.f["LI"] if i.f["LI"] < 0 else i.f["LI"] - 0x1000000)) & 0xFFFFFFFF
                if t in img.words if hasattr(img, "words") else True:
                    starts.add(t)
    # the candidates: the entry points the discovery found
    from wiikit.recomp.discover import discover
    units, _ = discover(img, log=lambda m: None)
    for s_, _e in units:
        starts.add(s_)

    hits = []
    for start in sorted(starts):
        seg = img.segment_at(start)
        if not seg:
            continue
        for (csum, size) in wanted:
            if size < a.min_size:
                continue
            off = start - seg.vaddr
            if off + size * 4 > len(seg.data):
                continue
            words = [struct.unpack_from(">I", seg.data, off + k * 4)[0] for k in range(size)]
            if checksum(words) == csum:
                hits.append((start, size))
    for start, size in hits:
        print(f"  {start:08X}: {a.name}, {size} words")
    if not hits:
        print("  no match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
