#!/usr/bin/env python3
"""Build a synthetic GameCube disc, to prove the port's pipeline works.

The real disc is the user's own (BYOA), but the *toolchain* can be checked
without it: this writes a disc image whose main.dol is a hand-assembled
PowerPC program that prints a line and then asks the console to leave.
Run through wiiboot, it prints and exits.

That exercises the whole chain: wiikit.disc (a GameCube image: no
partitions, no encryption, offsets in bytes), wiikit.recomp (PowerPC to
C++), the CMake build, and the runtime (the disc's file system, the boot
globals, the console hook).

The program calls two of the SDK's functions, `__write_console` and
`__OSReboot`. A DOL carries no symbol table, so the recompiler finds the
functions by discovery and the names come from a symbols.tsv, as they do
for a stripped game. This script writes that file too, with the two
functions named.

    python tools/make_testdisc.py build/testdisc.iso
    tools/test_pipeline.sh
"""
import os
import struct
import sys

# --- the PowerPC program ---------------------------------------------------
# The SDK's console write: int __write_console(__file_handle handle,
# u8 *buf, size_t *n, __idle_proc proc). The handle is in r3, the buffer
# in r4, and r5 points at the number of bytes to write (not the number
# itself: MSL passes a size_t *, and Dolphin's HLE reads it the same way).
#
#   lis    r4, hi(msg)       ; the message
#   ori    r4, r4, lo(msg)
#   lis    r5, hi(len)       ; the address of the length
#   ori    r5, r5, lo(len)
#   li     r3, 0            ; the handle
#   bl     __write_console
#   li     r3, 0
#   bl     __OSReboot
#   b      .               ; and a loop, should it return
#
# The message and its length live in the data section.

TEXT_ADDR = 0x80003100
# The data section goes well clear of the boot globals: the runtime writes
# the disc's header and the arena's bounds over 0x80000000-0x800000FC
# after the DOL is loaded, so a section there would be overwritten.
DATA_ADDR = 0x80010000
BSS_ADDR = 0x80000000
BSS_SIZE = 0x1000

MESSAGE = b"Custom Robo test disc: the pipeline works.\n"
FILE_DATA = b"a file on the disc\n"

# The data section: the message, then its length, at the end.
LEN_OFF = 0x40                                # the length word's offset
DATA = MESSAGE + b"\0" * (LEN_OFF - len(MESSAGE)) + struct.pack(">I", len(MESSAGE))
LEN_ADDR = DATA_ADDR + LEN_OFF

# The two functions the program calls, and the addresses the linker would
# have given them. The recompiler puts each function where the DOL says,
# so these are the addresses the program calls.
WRITE_CONSOLE_ADDR = TEXT_ADDR + 0x40
REBOOT_ADDR = TEXT_ADDR + 0x60


def li(r, v):
    """addi rD, 0, simm: a signed 16-bit immediate."""
    return (0x38000000 | (r << 21) | (v & 0xFFFF)) & 0xFFFFFFFF


def lis_ori(r, addr):
    """lis rD, hi ; ori rD, rD, lo: a 32-bit address.

    `lis` is `addis rD, 0, hi`, and its immediate is sign-extended, so the
    high half is the address's high half with its top bit set: for
    0x80000018 that is 0x8000, which reads back as -32768."""
    hi, lo = (addr >> 16) & 0xFFFF, addr & 0xFFFF
    return [(0x3C000000 | (r << 21) | (hi & 0xFFFF)) & 0xFFFFFFFF,
            (0x60000000 | (r << 21) | (r << 16) | lo) & 0xFFFFFFFF]


def bl(target, pc):
    """bl with a PC-relative displacement and the link register set."""
    return (0x48000001 | ((target - pc) & 0x03FFFFFC)) & 0xFFFFFFFF


def build_text():
    """The program's words.

    Three functions: the entry point, and the two the program calls. The
    two are the SDK's `__write_console` and `__OSReboot`, which the
    runtime replaces with its own; their bodies are never run, but they
    must exist, at the addresses the program calls.

    The gaps between the functions are zero words, which are not code:
    the recompiler's discovery reads a zero word as the end of a
    function, so each function starts at its own address."""
    words = []
    words += lis_ori(4, DATA_ADDR)     # r4 = the message
    words += lis_ori(5, LEN_ADDR)      # r5 = the address of the length
    words.append(li(3, 0))             # r3 = the handle
    words.append(0xFFFFFFFF)           # bl __write_console  (patched)
    words.append(li(3, 0))
    words.append(0xFFFFFFFF)           # bl __OSReboot       (patched)
    words.append(0x48000000)           # b .

    def pad_to(addr):
        while TEXT_ADDR + 4 * len(words) < addr:
            words.append(0x00000000)   # a zero word: not code

    pad_to(WRITE_CONSOLE_ADDR)
    words.append(0x4E800020)           # blr: __write_console's body
    pad_to(REBOOT_ADDR)
    words.append(0x4E800020)           # blr: __OSReboot's body
    for addr in sorted(OS_STUBS.values()):
        pad_to(addr)
        words.append(0x4E800020)       # blr: the OS stub's body
    pad_to(TEXT_ADDR + 0x100)
    return words


# The SDK's OS functions the runtime needs to see, so that its hooks bind.
# A real game links them from the SDK's os library; the test disc has stubs
# at these addresses, which the runtime replaces with its own. The test
# program never calls them.
OS_STUBS = {
    "OSLoadContext": 0x80003180,
    "OSSaveContext": 0x80003190,
    "OSCreateThread": 0x800031A0,
}


def check_text(words):
    """Check the program's instructions with wiikit's own decoder.

    A wrong encoding here is silent: the recompiler would translate a
    garbage word, and the discovery would not find the function the call
    points at. So the words are decoded and the two calls are checked."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    from wiikit.ppc import branch_target, decode

    for i, w in enumerate(words):
        if w == 0:
            continue                                  # padding: not code
        ins = decode(w)
        if ins.op in (".long", "fnmadd"):
            raise SystemExit(f"the word at {TEXT_ADDR + 4 * i:#010x} does not decode: {w:#010x}")
    for i, target in ((5, WRITE_CONSOLE_ADDR), (7, REBOOT_ADDR)):
        a = TEXT_ADDR + 4 * i
        ins = decode(words[i])
        got = branch_target(ins, a)
        if got != target:
            raise SystemExit(f"the call at {a:#010x} goes to {got:#010x}, not {target:#010x}")


def build_dol(words):
    """A GameCube DOL: the header, then the text and the data.

    The header holds, for each of the 18 sections (7 text, 11 data), its
    offset in the file, its address in memory and its size; then the BSS's
    address and size, and the entry point."""
    # The two calls: their targets are known now, so patch them in. The
    # calls are the fifth and the eighth words.
    words = list(words)
    words[5] = bl(WRITE_CONSOLE_ADDR, TEXT_ADDR + 5 * 4)
    words[7] = bl(REBOOT_ADDR, TEXT_ADDR + 7 * 4)
    check_text(words)

    text = b"".join(struct.pack(">I", w) for w in words)
    data = DATA

    text_off = 0x100
    data_off = text_off + len(text)

    header = bytearray(0x100)
    # The DOL's header: 18 sections' offsets, then their addresses, then
    # their sizes. Sections 0-6 are text and 7-17 are data, so the data
    # section's three words sit at 7*4, 0x48+7*4 and 0x90+7*4.
    struct.pack_into(">I", header, 0x00, text_off)                 # section 0: text
    struct.pack_into(">I", header, 0x48, TEXT_ADDR)
    struct.pack_into(">I", header, 0x90, len(text))
    struct.pack_into(">I", header, 7 * 4, data_off)                # section 7: data
    struct.pack_into(">I", header, 0x48 + 7 * 4, DATA_ADDR)
    struct.pack_into(">I", header, 0x90 + 7 * 4, len(data))
    struct.pack_into(">I", header, 0xD8, BSS_ADDR)                 # the BSS's address
    struct.pack_into(">I", header, 0xDC, BSS_SIZE)                 # its size
    struct.pack_into(">I", header, 0xE0, TEXT_ADDR)                # the entry point

    return bytes(header) + text + data


def build_fst(file_off):
    """A GameCube FST: the entries, then the names.

    The FST is one 12-byte entry per file and directory, then the names.
    Each entry is three 32-bit words: the name's offset (with the top byte
    set for a directory), the file's offset, and its size.

    The root's entry comes first, and its size word is the number of
    entries; the names follow the entries, so they start at twelve times
    that count."""
    names = b"hello.bin\0"
    name_off = 0

    # The root: a directory, with no name of its own.
    root = bytearray(12)
    struct.pack_into(">I", root, 0x00, 0x01000000)  # a directory, no name
    struct.pack_into(">I", root, 0x04, 0)           # its parent
    struct.pack_into(">I", root, 0x08, 2)           # its size: the entries

    # One file: hello.bin.
    file_entry = bytearray(12)
    struct.pack_into(">I", file_entry, 0x00, name_off)   # its name's offset
    struct.pack_into(">I", file_entry, 0x04, file_off)   # its offset
    struct.pack_into(">I", file_entry, 0x08, len(FILE_DATA))   # its size

    return bytes(root) + bytes(file_entry) + names


def build_disc(dol):
    """A GameCube disc image: the header, BI2, the apploader, the DOL, the
    FST, and the one file's data.

    The file's offset is in the FST, and the FST's size is in the header,
    so the layout is settled first and the FST written last."""
    HEADER_SIZE = 0x440
    BI2_OFF = 0x440
    APP_OFF = 0x2440

    dol_off = APP_OFF + 0x100
    fst_off = dol_off + len(dol)
    file_off = fst_off + 0x100                       # the file's data follows

    header = bytearray(HEADER_SIZE)
    header[0:6] = b"GXTST0"                          # the game id
    header[3] = ord("E")                             # USA
    struct.pack_into(">I", header, 0x1C, 0xC2339F3D)  # the GameCube's magic
    header[0x20:0x20 + 12] = b"WIITKIT TEST"          # the title
    struct.pack_into(">I", header, 0x420, dol_off)    # the DOL's offset
    struct.pack_into(">I", header, 0x424, fst_off)    # the FST's offset
    struct.pack_into(">I", header, 0x428, 0x100)      # the FST's size
    struct.pack_into(">I", header, 0x42C, 0x100)      # its maximum size

    bi2 = bytearray(0x2000)
    struct.pack_into(">I", bi2, 0x18, 1)               # the region: USA

    fst = build_fst(file_off)

    image = bytearray(file_off + len(FILE_DATA))
    image[0:HEADER_SIZE] = header
    image[BI2_OFF:BI2_OFF + len(bi2)] = bi2
    image[dol_off:dol_off + len(dol)] = dol
    image[fst_off:fst_off + len(fst)] = fst
    image[file_off:file_off + len(FILE_DATA)] = FILE_DATA
    return bytes(image)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/testdisc.iso"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)

    dol = build_dol(build_text())
    image = build_disc(dol)

    with open(out, "wb") as f:
        f.write(image)
    print(f"wrote {out}: {len(image)} bytes")

    # The names for the stripped executable: the two functions the program
    # calls. The recompiler finds them by discovery; the names make the
    # runtime's hook list match them.
    names = os.path.join(os.path.dirname(os.path.abspath(out)), "testnames.tsv")
    with open(names, "w") as f:
        f.write("addr\tname\n")
        f.write(f"{WRITE_CONSOLE_ADDR:08X}\t__write_console\n")
        f.write(f"{REBOOT_ADDR:08X}\t__OSReboot\n")
        for name, addr in sorted(OS_STUBS.items(), key=lambda kv: kv[1]):
            f.write(f"{addr:08X}\t{name}\n")
    print(f"wrote {names}")


if __name__ == "__main__":
    sys.exit(main())
