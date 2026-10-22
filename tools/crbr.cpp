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
    wpad_set_classic_filter(camera_filter);
}

RtGameLayer layer("Custom Robo", install);

}  // namespace
