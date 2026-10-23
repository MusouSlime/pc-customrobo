#!/usr/bin/env bash
# Assemble the thin Windows launcher package.
#
# It carries the port source, the shared launcher core, the WinForms front end
# and the OpenGL headers.  It does not carry SDL3 binaries: those must match
# the user's compiler, so the launcher asks for the SDL3 development folder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="$ROOT/build/windows"
PKG="$OUTDIR/CustomRoboLauncher"
ZIP="$ROOT/build/CustomRoboLauncher-windows.zip"
GL="${GL_DIR:-$HOME/.local/opt/gl}"

[ -f "$GL/include/GL/glcorearb.h" ] || { echo "no GL headers at $GL/include" >&2; exit 1; }
[ -f "$ROOT/tools/names-hooks.txt" ] || { echo "no tools/names-hooks.txt" >&2; exit 1; }

echo "== assembling $PKG"
rm -rf "$PKG"
mkdir -p "$PKG/launcher/windows" "$PKG/project/tools" "$PKG/deps/gl"

cp "$ROOT/launcher/core.py" "$PKG/launcher/"
cp "$ROOT/launcher/windows/CustomRoboLauncher.ps1" "$PKG/launcher/windows/"
cp "$ROOT/launcher/windows/Custom Robo Launcher.cmd" "$PKG/"
# cmd.exe is happiest with CRLF, even though it usually tolerates LF.
sed -i 's/$/\r/' "$PKG/Custom Robo Launcher.cmd"
cp "$ROOT/launcher/windows/README.txt" "$PKG/README.txt"

cp -a "$ROOT/wiikit" "$PKG/project/wiikit"
rm -rf "$PKG/project/wiikit/.git"
cp -a "$ROOT/tools/." "$PKG/project/tools/"
rm -f "$PKG/project/tools/"*.tsv
find "$PKG/project" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$PKG/project" -name '*.pyc' -delete

cp -a "$GL/include" "$PKG/deps/gl/include"

echo "== bundling CMake and Ninja"
"$ROOT/launcher/fetch-tools.sh" windows
mkdir -p "$PKG/deps/cmake/bin"
cp "$ROOT/build/tools/cmake-windows/bin/cmake.exe" "$PKG/deps/cmake/bin/cmake.exe"
cp -a "$ROOT/build/tools/cmake-windows/share" "$PKG/deps/cmake/"
[ -f "$ROOT/build/tools/cmake-windows/COPYING-CMAKE.txt" ] && \
    cp "$ROOT/build/tools/cmake-windows/COPYING-CMAKE.txt" "$PKG/deps/cmake/"
cp "$ROOT/build/tools/ninja-windows/ninja.exe" "$PKG/deps/ninja.exe"
[ -f "$ROOT/build/tools/ninja-windows/COPYING-NINJA.txt" ] && \
    cp "$ROOT/build/tools/ninja-windows/COPYING-NINJA.txt" "$PKG/deps/"

echo "== bundling clang, SDL3 and Python"
mkdir -p "$PKG/deps/llvm-mingw" "$PKG/deps/sdl3" "$PKG/deps/python"
cp -a "$ROOT/build/tools/llvm-mingw/." "$PKG/deps/llvm-mingw/"
cp -a "$ROOT/build/tools/sdl3-mingw/." "$PKG/deps/sdl3/"
cp -a "$ROOT/build/tools/python-embed/." "$PKG/deps/python/"
# The embeddable Python isolates sys.path; make the project importable.
for pth in "$PKG"/deps/python/*._pth; do
    [ -f "$pth" ] || continue
    grep -qx '../../project' "$pth" || printf '\n../../project\n' >> "$pth"
done

# Keep the source tree's executable bits from leaking into odd places; the
# .cmd and .ps1 are launched explicitly by Windows.
echo "== packaging $ZIP"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
    (cd "$OUTDIR" && zip -qr "$ZIP" CustomRoboLauncher)
else
    (cd "$OUTDIR" && python3 -m zipfile -c "$ZIP" CustomRoboLauncher)
fi
echo
echo "built: $ZIP"
echo "The recipient unzips it and runs \"Custom Robo Launcher.cmd\"."
