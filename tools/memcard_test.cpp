// A test of wiikit's memory card: the EXI's registers and the card's
// commands, driven the way the SDK drives them.
//
// The card is the GameCube's own: an EXI device on channel 0, device 0
// (slot A). The SDK talks to it in a small protocol, and this test drives
// that protocol directly, so that the card can be checked before the game
// that uses it arrives.
//
// The test writes the card's own way:
//
//   * the size: the command 0x00 (the Nintendo ID), which answers the
//     card's size in Mbits;
//   * the status: the command 0x83;
//   * a block: the command 0xF2 (a page program) with its address, then
//     the data, and the chip released;
//   * and it reads the block back with the command 0x52.
//
// The card is in the file build/memcard/A.raw, and the test checks that
// what it wrote is there.
//
// Built by the port's own cmake (crbr.cmake), run by tools/test_memcard.sh.
#include "mem.h"
#include "ppc.h"
#include "rt.h"
#include <cstdio>
#include <cstring>

namespace {

// The EXI's channel 0, at 0xCC006800: the status, the DMA address, the
// DMA length, the control, and the immediate data.
constexpr uint32_t EXI0 = 0xCC006800;
constexpr int CSR = 0x00, MAR = 0x04, LEN = 0x08, CR = 0x0C, IMM = 0x10;

// The control's bits: start, DMA, the direction, the length.
constexpr uint32_t TSTART = 0x001, DMA = 0x002, RW_WRITE = 0x004, RW_READ = 0x000;

// The chip select: the card is device 0, and the field's value for it is 1
// (the field is at the status' bits 7-9).
constexpr uint32_t CS_CARD = 0x80;

// The EXI's DMA moves whole 32-byte units: the length register is masked
// to a multiple of 32.
constexpr uint32_t DMA_UNIT = 32;

int failures = 0;

void check(bool ok, const char* what) {
    std::printf("%-46s %s\n", what, ok ? "ok" : "FAILED");
    if (!ok) ++failures;
}

void exi_write(int off, uint32_t v) { ppc_io_write(EXI0 + off, v, 4); }
uint32_t exi_read(int off) { return ppc_io_read(EXI0 + off, 4); }

// Send a byte to the card: the chip is selected, the byte is written.
void card_send(uint8_t b) {
    exi_write(IMM, (uint32_t)b << 24);
    exi_write(CR, TSTART | RW_WRITE);
}

// Read a byte from the card.
uint8_t card_read() {
    exi_write(CR, TSTART | RW_READ);
    return (uint8_t)(exi_read(IMM) >> 24);
}

// The address the card wants: four bytes, the high one first.
void card_address(uint32_t addr) {
    card_send((uint8_t)(addr >> 17));
    card_send((uint8_t)(addr >> 9));
    card_send((uint8_t)(addr >> 7));
    card_send((uint8_t)addr);
}

// A command: the chip is released and selected again, so that the card
// starts at the command byte.
void card_command(uint8_t cmd) {
    exi_write(CSR, 0);
    exi_write(CSR, CS_CARD);
    card_send(cmd);
}

// Read a whole block of the card, the way the SDK reads one.
void card_read_block(uint32_t block, uint8_t* out, uint32_t size) {
    card_command(0x52);                                // the read array
    card_address(block * 0x2000);
    char zeros[0x2000] = {};
    mem_write(0x80020000, zeros, sizeof zeros);
    exi_write(MAR, 0x00020000);
    exi_write(LEN, size);
    exi_write(CR, TSTART | DMA | RW_READ);
    exi_write(CSR, 0);
    mem_read(0x80020000, out, size);
}

uint16_t swap16(uint16_t v) { return (uint16_t)(v >> 8 | v << 8); }
uint16_t be16(const uint8_t* p) { return (uint16_t)(p[0] << 8 | p[1]); }

// The card's checksum: the sum of an area's 16-bit words and the sum of
// their inverses, in the card's own order (big-endian). The console
// compares the two byte-swapped, and a sum of 0xFFFF means none.
void checksums(const uint8_t* data, size_t size, uint16_t& sum, uint16_t& inv) {
    uint16_t s = 0, i = 0;
    for (size_t k = 0; k + 1 < size; k += 2) {
        uint16_t w = (uint16_t)(data[k] << 8 | data[k + 1]);
        s += w;
        i += (uint16_t)(w ^ 0xFFFF);
    }
    sum = s;
    inv = i;
    if (swap16(s) == 0xFFFF) sum = 0;
    if (swap16(i) == 0xFFFF) inv = 0;
}

}  // namespace

int main(int argc, char** argv) {
    const char* dir = argc > 1 ? argv[1] : "build/memcard";
    if (!mem_init()) {
        std::printf("cannot reserve the guest's memory\n");
        return 1;
    }
    memcard_init(dir);

    // --- the card is there
    check(exi_read(CSR) & 0x1000, "the card is present (the status' EXT bit)");

    // --- its size: the command 0x00
    card_command(0x00);
    uint8_t size_code = 0;
    for (int i = 0; i < 5; ++i) {                       // the dummy, then the size
        uint8_t b = card_read();
        if (i == 4) size_code = b;
    }
    std::printf("the card's size code: %02X\n", size_code);
    check(size_code == 0x10, "the card answers 0x10 (251 blocks)");

    // --- its status: the command 0x83
    card_command(0x83);
    uint8_t status = card_read();
    std::printf("the card's status: %02X\n", status);
    check(status & 0x01, "the card is ready");
    check(status & 0x40, "the card is unlocked");

    // --- write a block: the command 0xF2, the address, then the data
    const char* message = "the memory card works\n";
    const uint32_t size = DMA_UNIT;
    // the sixth block: the first one the game's own files may use (the
    // header, the two directories and the two tables come first)
    const uint32_t block6 = 0x2000 * 6;

    char buffer[DMA_UNIT];
    std::memset(buffer, 0, sizeof buffer);
    std::memcpy(buffer, message, std::strlen(message));

    card_command(0xF2);
    card_address(block6);
    // the data, by DMA: the address, the length, and the transfer
    mem_write(0x80010000, buffer, size);
    exi_write(MAR, 0x00010000);                         // the physical address of the data
    exi_write(LEN, size);
    exi_write(CR, TSTART | DMA | RW_WRITE);
    // and the chip is released
    exi_write(CSR, 0);

    // --- read it back: the command 0x52, the address, then the data
    card_command(0x52);
    card_address(block6);
    char zeros[DMA_UNIT] = {};
    mem_write(0x80010100, zeros, sizeof zeros);          // the buffer is empty
    exi_write(MAR, 0x00010100);
    exi_write(LEN, size);
    exi_write(CR, TSTART | DMA | RW_READ);
    exi_write(CSR, 0);

    char back[DMA_UNIT] = {};
    mem_read(0x80010100, back, sizeof back);
    std::printf("read back: %s", back);
    check(std::memcmp(back, message, std::strlen(message)) == 0,
          "the block reads back as it was written");

    // --- and it is in the file
    char path[512];
    std::snprintf(path, sizeof path, "%s/A.raw", dir);
    FILE* f = std::fopen(path, "rb");
    bool in_file = false;
    if (f) {
        std::fseek(f, 0, SEEK_END);
        long len = std::ftell(f);
        std::fseek(f, 0, SEEK_SET);
        std::vector<uint8_t> d((size_t)len);
        if (std::fread(d.data(), 1, d.size(), f) == d.size() && d.size() > block6 + size)
            in_file = std::memcmp(&d[block6], message, size) == 0;
        std::fclose(f);
    }
    check(in_file, "the block is in the card's file");

    // --- and the card's own blocks are the ones the SDK expects: the
    // header, the directory and the block allocation table, each with the
    // checksums the SDK's card code verifies before it uses a card.
    uint8_t block[0x2000];
    uint16_t sum, inv;

    card_read_block(0, block, sizeof block);
    check(be16(block + 0x22) == 0x10, "the header says the card is 251 blocks");
    checksums(block, 0x1FC, sum, inv);
    check(be16(block + 0x1FC) == sum && be16(block + 0x1FE) == inv,
          "the header's checksums are right");

    card_read_block(1, block, sizeof block);
    checksums(block, 0x1FFC, sum, inv);
    check(be16(block + 0x1FFC) == sum && be16(block + 0x1FFE) == inv,
          "the directory's checksums are right");

    card_read_block(3, block, sizeof block);
    checksums(block + 0x04, sizeof block - 0x04, sum, inv);
    check(be16(block) == sum && be16(block + 0x02) == inv, "the table's checksums are right");
    check(be16(block + 0x06) == 251, "the table says 251 free blocks");

    std::printf("\n%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
