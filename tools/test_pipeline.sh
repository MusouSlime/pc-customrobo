#!/usr/bin/env bash
# Custom Robo — check the toolchain, without the game's disc.
#
# The real disc is the user's own (BYOA), but the *toolchain* can be checked
# without it: this builds a synthetic GameCube disc whose main.dol is a
# hand-assembled PowerPC program that prints a line through the SDK's
# console function and then asks the console to leave, and runs it through
# the whole chain:
#
#   wiikit.disc    read the disc and extract it
#   wiikit.recomp  translate the PowerPC to C++
#   cmake + ninja   build it, with SDL3 and the OpenGL headers
#   wiiboot        run it: the disc's file system, the boot globals, the
#                  console hook
#
# A line on the output and the words "the pipeline works" mean the chain is
# whole.
#
#   tools/test_pipeline.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

export PKG_CONFIG_PATH="$HOME/.local/opt/sdl3/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$HOME/.local/opt/sdl3${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$HOME/.local/opt/sdl3/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
GL_INCLUDE="-I$HOME/.local/opt/gl/include"

B="$HERE/build"

echo "== 1. the synthetic disc"
python3 tools/make_testdisc.py "$B/testdisc.iso"

echo "== 2. read it"
python3 -m wiikit.disc "$B/testdisc.iso" --info
rm -rf "$B/testextract"
python3 -m wiikit.disc "$B/testdisc.iso" --extract "$B/testextract"

echo "== 3. the executable"
python3 -m wiikit.dol "$B/testextract/sys/main.dol" --info

echo "== 4. recompile"
rm -rf "$B/testrecomp"
python3 -m wiikit.recomp "$B/testextract/sys/main.dol" --out "$B/testrecomp" \
    --symbols "$B/testnames.tsv"

echo "== 5. build"
rm -rf "$B/testbuild"
cmake -S "$B/testrecomp" -B "$B/testbuild" -G Ninja \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE="-O1 $GL_INCLUDE" \
    -DWIIKIT_EXTRA="$HERE/tools/crbr.cmake" >/dev/null
ninja -C "$B/testbuild" 2>&1 | tail -2

echo "== 6. run"
out="$("$B/testbuild/wiiboot" "$B/testextract" --fonts "$B/fonts" --no-video 2>&1)"
echo "$out"
case "$out" in
    *"the pipeline works"*) echo; echo "PASS: the toolchain is whole." ;;
    *) echo; echo "FAIL: the game did not print its line."; exit 1 ;;
esac
