# Custom Robo — build the port.
#
# Assumes tools/setup.sh has been run and the disc has been extracted into
# build/extract (see docs/01-disc-layout.md).
#
#   tools/build.sh
#
# The generated build finds SDL3 and the OpenGL headers through the
# environment this script sets.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

export PKG_CONFIG_PATH="$HOME/.local/opt/sdl3/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$HOME/.local/opt/sdl3${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
# wiikit's runtime includes <GL/glcorearb.h>, which the Mesa headers carry.
# CMAKE_INCLUDE_PATH is not enough: it does not reach a target's include
# path, so the flag goes on the compiler's own.
GL_INCLUDE="-I$HOME/.local/opt/gl/include"
export CMAKE_CXX_FLAGS="$GL_INCLUDE${CMAKE_CXX_FLAGS:+ $CMAKE_CXX_FLAGS}"

DOL="$HERE/build/extract/sys/main.dol"
[ -f "$DOL" ] || { echo "no $DOL: extract the disc first (docs/01-disc-layout.md)"; exit 1; }

# The names for the stripped executable, if they have been built.
SYMS=""
[ -f "$HERE/build/names.tsv" ] && SYMS="--symbols $HERE/build/names.tsv"

# The recompile. wiikit's own hooks always apply; the port's own are added.
python3 -m wiikit.recomp "$DOL" --out "$HERE/build/recomp" \
    $SYMS --hooks "$HERE/tools/crbr-hooks.txt"

cmake -S "$HERE/build/recomp" -B "$HERE/build/recomp-build" -G Ninja \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE="-O1 $GL_INCLUDE" \
    -DWIIKIT_EXTRA="$HERE/tools/crbr.cmake"

ninja -C "$HERE/build/recomp-build"

echo
echo "built: $HERE/build/recomp-build/wiiboot"
echo "run it with: tools/run.sh"
