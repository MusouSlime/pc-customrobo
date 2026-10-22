#!/usr/bin/env bash
# Custom Robo — set up the toolchain this port needs.
#
# The host is an rpm-ostree system (Bazzite), so packages are not installed
# system-wide: SDL3 and the OpenGL headers are unpacked into
# ~/.local/opt, and the environment points at them.
#
# Run once. It is safe to run again: it reuses what is already there.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPT="$HOME/.local/opt"
mkdir -p "$OPT"

# --- SDL3 ------------------------------------------------------------------
# wiikit's runtime needs SDL3 (the window and the sound) and OpenGL 4.5.
# SDL3 is packaged for Fedora; unpack it rather than install it.
if [ ! -d "$OPT/sdl3/lib64/cmake/SDL3" ]; then
    echo "== SDL3"
    tmp="$(mktemp -d)"
    cd "$tmp"
    for p in SDL3 SDL3-devel; do
        url="$(dnf repoquery --location --latest-limit 1 "$p" 2>/dev/null | tail -1)"
        [ -n "$url" ] || { echo "no $p in the repositories"; exit 1; }
        curl -sSLO "$url"
        rpm2cpio "$(basename "$url")" | cpio -idm --quiet
    done
    mkdir -p "$OPT/sdl3/lib64"
    cp -a usr/lib64/libSDL3.so* usr/lib64/cmake usr/lib64/pkgconfig "$OPT/sdl3/lib64/"
    cp -a usr/include "$OPT/sdl3/"
    # the package's .pc and CMake config carry an absolute /usr prefix
    sed -i "s|^prefix=/usr$|prefix=$OPT/sdl3|" "$OPT/sdl3/lib64/pkgconfig/sdl3.pc"
    cd /
    rm -rf "$tmp"
fi

# --- OpenGL headers --------------------------------------------------------
# wiikit's runtime includes <GL/glcorearb.h>, which the Mesa devel package
# carries; the runtime loads the functions itself through SDL, so only the
# headers are needed here.
if [ ! -f "$OPT/gl/include/GL/glcorearb.h" ]; then
    echo "== OpenGL headers"
    tmp="$(mktemp -d)"
    cd "$tmp"
    for p in mesa-libGL-devel libglvnd-devel; do
        url="$(dnf repoquery --location --latest-limit 1 "$p" 2>/dev/null | tail -1)"
        [ -n "$url" ] || continue
        curl -sSLO "$url"
        rpm2cpio "$(basename "$url")" | cpio -idm --quiet
    done
    mkdir -p "$OPT/gl"
    cp -a usr/include "$OPT/gl/"
    cd /
    rm -rf "$tmp"
fi

# --- Dolphin's files --------------------------------------------------------
# wiiboot needs the boot ROM's fonts and the DSP ROM's resampling table.
# They are free, and Dolphin's Sys/GC carries them.
echo "== Dolphin's Sys/GC"
DOLPHIN_SYS=""
for d in \
    "$HOME/.local/share/dolphin/Sys/GC" \
    /var/lib/flatpak/app/org.DolphinEmu.dolphin-emu/x86_64/stable/*/files/share/dolphin-emu/Sys/GC
do
    if [ -f "$d/font_western.bin" ]; then DOLPHIN_SYS="$d"; break; fi
done
if [ -z "$DOLPHIN_SYS" ]; then
    echo "  no Dolphin's Sys/GC found: install Dolphin, or copy font_western.bin,"
    echo "  font_japanese.bin and dsp_coef.bin into $HERE/build/fonts by hand"
else
    mkdir -p "$HERE/build/fonts"
    cp -u "$DOLPHIN_SYS"/font_western.bin "$DOLPHIN_SYS"/font_japanese.bin \
          "$DOLPHIN_SYS"/dsp_coef.bin "$HERE/build/fonts/" 2>/dev/null || true
    echo "  copied from $DOLPHIN_SYS"
fi

# --- report ----------------------------------------------------------------
echo
echo "Toolchain:"
echo "  SDL3        $("$HOME/.local/opt/sdl3/lib64/pkgconfig/../../../../bin/true" 2>/dev/null; echo "$OPT/sdl3 (3.4.18)")"
echo "  GL headers  $OPT/gl/include"
echo "  cmake       $(cmake --version | head -1)"
echo "  ninja       $(ninja --version)"
echo "  clang++     $(clang++ --version | head -1)"
echo
echo "Next: put the disc's image at build/, then follow docs/01-disc-layout.md."
