// Custom Robo — the port's own layer over the wiikit runtime.
//
// Linked into wiiboot by crbr.cmake. What belongs here is what only this
// game needs; everything general stays in wiikit.
#include "mem.h"
#include "rt.h"
#include "video.h"
#include <cstdlib>
#include <cstring>

namespace {

// ---- the card, for the port's own tracing -------------------------------------------
// WIIKIT_CARDTDBG=1 logs what the SDK's card layer asks for and gets back, which
// is what tells a stuck "checking memory card" screen from one waiting on input.
PPCFunc orig_CARDProbeEx, orig_CARDMountAsync, orig_CARDMountCallback, orig_CARDCheckExAsync;
PPCFunc orig_CARDReadStatus, orig_CARDReadSegment, orig_CARDEnableInterrupt, orig_CARDExiHandler;
PPCFunc orig_CARDWriteAsync, orig_CARDWritePage, orig_CARDEraseSector;
PPCFunc orig_CARDAllocBlock, orig_CARDFreeBlock, orig_CARDUpdateDir, orig_CARDVerify;
PPCFunc orig_CARDUpdateFatBlock, orig_CARDCreateAsync, orig_CARDDeleteAsync, orig_CARDFormatAsync;
bool card_dbg = false;

void hook_CARDProbeEx(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDProbeEx(c);
    if (card_dbg) rt_log("crbr: CARDProbeEx(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDMountAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDMountAsync(c);
    if (card_dbg) rt_log("crbr: CARDMountAsync(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDMountCallback(PPCContext& c) {
    if (card_dbg) rt_log("crbr: __CARDMountCallback(chan %d) result %d", (int)c.r[3], (int)c.r[4]);
    orig_CARDMountCallback(c);
}
void hook_CARDCheckExAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDCheckExAsync(c);
    if (card_dbg) rt_log("crbr: CARDCheckExAsync(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDReadStatus(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDReadStatus(c);
    if (card_dbg) rt_log("crbr: __CARDReadStatus(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDReadSegment(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t addr = c.r[4];
    uint32_t len = c.r[5];
    orig_CARDReadSegment(c);
    if (card_dbg) rt_log("crbr: __CARDReadSegment(%d, %08X, %u) -> %d", chan, addr, len, (int)c.r[3]);
}
void hook_CARDEnableInterrupt(PPCContext& c) {
    int chan = (int)c.r[3], on = (int)c.r[4];
    orig_CARDEnableInterrupt(c);
    if (card_dbg) rt_log("crbr: __CARDEnableInterrupt(%d, %d) -> %d", chan, on, (int)c.r[3]);
}
void hook_CARDExiHandler(PPCContext& c) {
    if (card_dbg) rt_log("crbr: __CARDExiHandler(%d), exi status %08X", (int)c.r[3], (unsigned)c.r[4]);
    orig_CARDExiHandler(c);
}
void hook_CARDWriteAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t dst = c.r[4], len = c.r[5], off = c.r[6];
    orig_CARDWriteAsync(c);
    if (card_dbg) rt_log("crbr: CARDWriteAsync(%d, %08X, %u, %u) -> %d", chan, dst, len, off, (int)c.r[3]);
}
void hook_CARDWritePage(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDWritePage(c);
    if (card_dbg) rt_log("crbr: __CARDWritePage(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDEraseSector(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t addr = c.r[4];
    orig_CARDEraseSector(c);
    if (card_dbg) rt_log("crbr: __CARDEraseSector(%d, %08X) -> %d", chan, addr, (int)c.r[3]);
}
void hook_CARDAllocBlock(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t size = c.r[4];
    orig_CARDAllocBlock(c);
    if (card_dbg) rt_log("crbr: __CARDAllocBlock(%d, %u) -> %d", chan, size, (int)c.r[3]);
}
void hook_CARDFreeBlock(PPCContext& c) {
    int chan = (int)c.r[3], block = (int)c.r[4];
    orig_CARDFreeBlock(c);
    if (card_dbg) rt_log("crbr: __CARDFreeBlock(%d, %d) -> %d", chan, block, (int)c.r[3]);
}
void hook_CARDUpdateDir(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDUpdateDir(c);
    if (card_dbg) rt_log("crbr: __CARDUpdateDir(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDVerify(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDVerify(c);
    if (card_dbg) rt_log("crbr: __CARDVerify(%d) -> %d", chan, (int)c.r[3]);
}
void hook_CARDUpdateFatBlock(PPCContext& c) {
    orig_CARDUpdateFatBlock(c);
    if (card_dbg) rt_log("crbr: __CARDUpdateFatBlock -> %d", (int)c.r[3]);
}
void hook_CARDCreateAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t name = c.r[5], size = c.r[6];
    orig_CARDCreateAsync(c);
    if (card_dbg) rt_log("crbr: CARDCreateAsync(%d, %08X, %u) -> %d", chan, name, size, (int)c.r[3]);
}
void hook_CARDDeleteAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    uint32_t name = c.r[5];
    orig_CARDDeleteAsync(c);
    if (card_dbg) rt_log("crbr: CARDDeleteAsync(%d, %08X) -> %d", chan, name, (int)c.r[3]);
}
void hook_CARDFormatAsync(PPCContext& c) {
    int chan = (int)c.r[3];
    orig_CARDFormatAsync(c);
    if (card_dbg) rt_log("crbr: CARDFormatAsync(%d) -> %d", chan, (int)c.r[3]);
}

// ---- unlocks, for trying content out ------------------------------------------------
// CRBR_UNLOCK=1 sets the USA version's "Unlock Everything" masks (the raw
// Gecko writes from the community codeset). They live in the game's static
// data, so they are reasserted every frame: loading a save or visiting a menu
// that rebuilds them cannot take the unlocks back.
PPCFunc orig_VIWaitForRetrace;
bool unlock_all = false;
void hook_VIWaitForRetrace(PPCContext& c) {
    orig_VIWaitForRetrace(c);
    if (!unlock_all) return;
    st32(0x80321D44u, 0xFFFFFFFFu);   // Unlock Bonuses (Arcade, Parts Index, ...)
    // All parts, owned in Arcade & Vs. Mode.
    st32(0x803BF79Cu, 0x0003FFFFu);   // bodies
    st32(0x803BF7BCu, 0x0003FFFFu);   // guns
    st32(0x803BF7DCu, 0x0003FFFFu);   // bombs
    st32(0x803BF7FCu, 0x0003FFFFu);   // pods
    st32(0x803BF81Cu, 0x0002FFFFu);   // legs
    st32(0x803BF83Cu, 0x0003FFFFu);   // all holosseums
    // The same parts as shop stock (Codejunkies "All ... Parts").
    st32(0x803BFB9Cu, 0x0003FFFFu);
    st32(0x803BFBBCu, 0x0003FFFFu);
    st32(0x803BFBDCu, 0x0003FFFFu);
    st32(0x803BFBFCu, 0x0003FFFFu);
    st32(0x803BFC1Cu, 0x0003FFFFu);
    // Parts Index glossary entries.
    st32(0x803BF8ECu, 0x0012FFFFu);
    st32(0x803BF8F4u, 0x0003FFFFu);
    st32(0x803BF8FCu, 0x0003FFFFu);
    st32(0x803BF904u, 0x0003FFFFu);
    st32(0x803BF90Cu, 0x0002FFFFu);
}

// The GameCube's controllers, and the game: Custom Robo is a four-player
// game where the C stick and the triggers matter as much as the face
// buttons. wiikit hands a GameCube game a standard controller on each port
// the host has a pad for, and reads it in analog mode 3.
//
// The C stick turns the camera the way games of 2004 did: pushed right, the
// view swings left. Games since turn it the other way, and this one has no
// option for it: the port turns the C stick's X around. CRBR_CAMERA=console
// in the environment keeps the console's way.
bool camera_invert = true;
void camera_filter(int, ClassicState& s) {
    if (camera_invert) s.rx = -s.rx;
}

void install() {
    if (const char* e = std::getenv("CRBR_CAMERA")) camera_invert = std::strcmp(e, "console") != 0;
    const char* unlock_env = std::getenv("CRBR_UNLOCK");
    unlock_all = !unlock_env || std::strcmp(unlock_env, "0") != 0;
    orig_VIWaitForRetrace = ppc_hook("VIWaitForRetrace", hook_VIWaitForRetrace);
    wpad_set_classic_filter(camera_filter);
    card_dbg = std::getenv("WIIKIT_CARDTDBG") != nullptr;
    orig_CARDProbeEx = ppc_hook("CARDProbeEx", hook_CARDProbeEx);
    orig_CARDMountAsync = ppc_hook("CARDMountAsync", hook_CARDMountAsync);
    orig_CARDMountCallback = ppc_hook("__CARDMountCallback", hook_CARDMountCallback);
    orig_CARDCheckExAsync = ppc_hook("CARDCheckExAsync", hook_CARDCheckExAsync);
    orig_CARDReadStatus = ppc_hook("__CARDReadStatus", hook_CARDReadStatus);
    orig_CARDReadSegment = ppc_hook("__CARDReadSegment", hook_CARDReadSegment);
    orig_CARDEnableInterrupt = ppc_hook("__CARDEnableInterrupt", hook_CARDEnableInterrupt);
    orig_CARDExiHandler = ppc_hook("__CARDExiHandler", hook_CARDExiHandler);
    orig_CARDWriteAsync = ppc_hook("CARDWriteAsync", hook_CARDWriteAsync);
    orig_CARDWritePage = ppc_hook("__CARDWritePage", hook_CARDWritePage);
    orig_CARDEraseSector = ppc_hook("__CARDEraseSector", hook_CARDEraseSector);
    orig_CARDAllocBlock = ppc_hook("__CARDAllocBlock", hook_CARDAllocBlock);
    orig_CARDFreeBlock = ppc_hook("__CARDFreeBlock", hook_CARDFreeBlock);
    orig_CARDUpdateDir = ppc_hook("__CARDUpdateDir", hook_CARDUpdateDir);
    orig_CARDVerify = ppc_hook("__CARDVerify", hook_CARDVerify);
    orig_CARDUpdateFatBlock = ppc_hook("__CARDUpdateFatBlock", hook_CARDUpdateFatBlock);
    orig_CARDCreateAsync = ppc_hook("CARDCreateAsync", hook_CARDCreateAsync);
    orig_CARDDeleteAsync = ppc_hook("CARDDeleteAsync", hook_CARDDeleteAsync);
    orig_CARDFormatAsync = ppc_hook("CARDFormatAsync", hook_CARDFormatAsync);
}

RtGameLayer layer("Custom Robo", install);

}  // namespace
