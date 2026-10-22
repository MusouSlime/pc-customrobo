#!/usr/bin/env bash
# Custom Robo — check wiikit's memory card.
#
# The card is the GameCube's own: an EXI device on channel 0, device 0. The
# test drives the EXI's registers the way the SDK drives them, and checks
# the card's answers, its blocks and the file it is in.
#
#   tools/test_memcard.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

export PKG_CONFIG_PATH="$HOME/.local/opt/sdl3/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$HOME/.local/opt/sdl3${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$HOME/.local/opt/sdl3/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
GL_INCLUDE="-I$HOME/.local/opt/gl/include"

B="$HERE/build"

# The test needs the synthetic disc's build (the recompiled code it links
# against), so that comes first.
if [ ! -d "$B/testrecomp" ]; then
    echo "== the synthetic disc's build (for the recompiled code)"
    tools/test_pipeline.sh >/dev/null
fi

echo "== build the test"
rm -rf "$B/testbuild"
cmake -S "$B/testrecomp" -B "$B/testbuild" -G Ninja \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE="-O1 $GL_INCLUDE" \
    -DWIIKIT_EXTRA="$HERE/tools/crbr.cmake" >/dev/null
ninja -C "$B/testbuild" memcard_test 2>&1 | tail -1

echo "== run it"
rm -rf "$B/memcard"
"$B/testbuild/memcard_test" "$B/memcard"
