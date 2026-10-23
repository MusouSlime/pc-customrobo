#!/usr/bin/env bash
# Build the thin Linux AppImage launcher.
#
# The AppImage carries the port's Python source, wiikit, SDL3 and the OpenGL
# headers.  It deliberately does not carry clang, CMake, Ninja or Python: the
# launcher uses the ones installed on the user's system, so the binary it
# produces matches that system's C++ runtime and graphics stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="$ROOT/build/appimage"
APPDIR="$OUTDIR/CustomRoboLauncher.AppDir"
OUT="$ROOT/build/CustomRoboLauncher-x86_64.AppImage"

SDL3="${SDL3_DIR:-$HOME/.local/opt/sdl3}"
GL="${GL_DIR:-$HOME/.local/opt/gl}"

[ -d "$SDL3" ] || { echo "no SDL3 development tree at $SDL3" >&2; exit 1; }
[ -f "$GL/include/GL/glcorearb.h" ] || { echo "no GL headers at $GL/include" >&2; exit 1; }
[ -f "$ROOT/tools/names-hooks.txt" ] || { echo "no tools/names-hooks.txt" >&2; exit 1; }
command -v magick >/dev/null || command -v convert >/dev/null || {
    echo "ImageMagick is needed for the icon" >&2; exit 1; }
ICON_TOOL="$(command -v magick || command -v convert)"

echo "== assembling $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
         "$APPDIR/usr/share/custom-robo/launcher" \
         "$APPDIR/usr/share/custom-robo/project" \
         "$APPDIR/usr/share/custom-robo/deps"

cp -a "$ROOT/wiikit" "$APPDIR/usr/share/custom-robo/project/wiikit"
rm -rf "$APPDIR/usr/share/custom-robo/project/wiikit/.git"
mkdir -p "$APPDIR/usr/share/custom-robo/project/tools"
cp -a "$ROOT/tools/." "$APPDIR/usr/share/custom-robo/project/tools/"
# The launcher only needs the hook-name table, not the developer's derived
# symbol maps or test binaries.
rm -f "$APPDIR/usr/share/custom-robo/project/tools/"*.tsv
find "$APPDIR/usr/share/custom-robo/project" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$APPDIR/usr/share/custom-robo/project" -name '*.pyc' -delete

cp "$ROOT/launcher/core.py" "$ROOT/launcher/linux_ui.py" \
   "$APPDIR/usr/share/custom-robo/launcher/"
cp "$ROOT/launcher/appimage/custom-robo-launcher" "$APPDIR/usr/bin/custom-robo-launcher"
chmod 755 "$APPDIR/usr/bin/custom-robo-launcher"

echo "== bundling SDL3 and GL headers"
cp -a "$SDL3" "$APPDIR/usr/share/custom-robo/sdl3"
mkdir -p "$APPDIR/usr/share/custom-robo/gl"
cp -a "$GL/include" "$APPDIR/usr/share/custom-robo/gl/"
find "$APPDIR/usr/share/custom-robo/sdl3" -name '__pycache__' -type d -prune -exec rm -rf {} + || true

echo "== bundling CMake and Ninja"
"$ROOT/launcher/fetch-tools.sh" linux
mkdir -p "$APPDIR/usr/share/custom-robo/deps/cmake"
mkdir -p "$APPDIR/usr/share/custom-robo/deps/cmake/bin"
cp "$ROOT/build/tools/cmake-linux/bin/cmake" "$APPDIR/usr/share/custom-robo/deps/cmake/bin/cmake"
cp -a "$ROOT/build/tools/cmake-linux/share" "$APPDIR/usr/share/custom-robo/deps/cmake/"
[ -f "$ROOT/build/tools/cmake-linux/COPYING-CMAKE.txt" ] && \
    cp "$ROOT/build/tools/cmake-linux/COPYING-CMAKE.txt" "$APPDIR/usr/share/custom-robo/deps/cmake/"
cp "$ROOT/build/tools/ninja-linux/ninja" "$APPDIR/usr/share/custom-robo/deps/ninja"
chmod 755 "$APPDIR/usr/share/custom-robo/deps/ninja"
[ -f "$ROOT/build/tools/ninja-linux/COPYING-NINJA.txt" ] && \
    cp "$ROOT/build/tools/ninja-linux/COPYING-NINJA.txt" "$APPDIR/usr/share/custom-robo/deps/"

echo "== icon and desktop entry"
cp "$ROOT/launcher/appimage/custom-robo.svg" "$APPDIR/custom-robo.svg"
"$ICON_TOOL" -background none "$ROOT/launcher/appimage/custom-robo.svg" \
        -resize 256x256 "$APPDIR/custom-robo.png"
ln -sf custom-robo.png "$APPDIR/.DirIcon"
cp "$APPDIR/custom-robo.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/custom-robo.png"
cp "$ROOT/launcher/appimage/custom-robo.desktop" "$APPDIR/custom-robo.desktop"
cp "$APPDIR/custom-robo.desktop" "$APPDIR/usr/share/applications/"
cp "$ROOT/launcher/appimage/AppRun" "$APPDIR/AppRun"
chmod 755 "$APPDIR/AppRun"

# --- appimagetool ----------------------------------------------------------
TOOL="${APPIMAGETOOL:-}"
if [ -z "$TOOL" ] || [ ! -x "$TOOL" ]; then
    TOOL="$ROOT/build/appimage-tools/appimagetool-x86_64.AppImage"
    if [ ! -x "$TOOL" ]; then
        mkdir -p "$(dirname "$TOOL")"
        echo "== downloading appimagetool"
        curl -fL --retry 3 -o "$TOOL.part" \
            "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
        mv "$TOOL.part" "$TOOL"
        chmod 755 "$TOOL"
    fi
fi

echo "== packaging $OUT"
mkdir -p "$(dirname "$OUT")"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" "$OUT"
chmod 755 "$OUT"
echo
echo "built: $OUT"
echo "run:   \"$OUT\""
echo "       (or \"$OUT\" --appimage-extract-and-run if FUSE is unavailable)"
