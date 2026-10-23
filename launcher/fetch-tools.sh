#!/usr/bin/env bash
# Fetch the build tools that the launcher packages carry.
#
# CMake and Ninja are small, portable, and the same on every machine, so they
# are bundled instead of being another thing the user has to install.  The
# compiler is deliberately not bundled: the game must be compiled with the
# user's own C++ runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${TOOLS_DIR:-$ROOT/build/tools}"
CMAKE_VERSION="${CMAKE_VERSION:-3.31.6}"
NINJA_VERSION="${NINJA_VERSION:-1.12.1}"
LLVM_MINGW_VERSION="${LLVM_MINGW_VERSION:-20261020}"
SDL3_VERSION="${SDL3_VERSION:-3.4.18}"
PYTHON_EMBED_VERSION="${PYTHON_EMBED_VERSION:-3.12.10}"
TARGET="${1:-}"

mkdir -p "$CACHE"

fetch() {
    local url="$1" out="$2"
    if [ -s "$out" ]; then
        return
    fi
    echo "== downloading $(basename "$out")"
    curl -fL --retry 3 --connect-timeout 20 -o "$out.part" "$url"
    mv "$out.part" "$out"
}

need_unzip() {
    command -v unzip >/dev/null 2>&1 || {
        echo "unzip is needed to unpack the bundled build tools" >&2
        exit 1
    }
}

cmake_license() {
    local dir="$1" f
    for f in "$dir"/doc/cmake-*/Copyright.txt \
             "$dir"/doc/cmake/Copyright.txt \
             "$dir"/share/cmake-*/Copyright.txt \
             "$dir"/Copyright.txt; do
        if [ -f "$f" ]; then
            cp "$f" "$dir/COPYING-CMAKE.txt"
            return
        fi
    done
}

ninja_license() {
    local dir="$1"
    if [ ! -s "$dir/COPYING-NINJA.txt" ]; then
        curl -fsSL --retry 3 --connect-timeout 20 \
            -o "$dir/COPYING-NINJA.txt" \
            "https://raw.githubusercontent.com/ninja-build/ninja/v$NINJA_VERSION/COPYING" \
            || true
    fi
}

fetch_linux() {
    local c="$CACHE/cmake-linux" n="$CACHE/ninja-linux"
    if [ ! -x "$c/bin/cmake" ]; then
        fetch "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-linux-x86_64.tar.gz" \
              "$CACHE/cmake-linux.tar.gz"
        rm -rf "$c" "$CACHE/.cmake-linux-extract"
        mkdir -p "$CACHE/.cmake-linux-extract"
        tar -xzf "$CACHE/cmake-linux.tar.gz" -C "$CACHE/.cmake-linux-extract" --strip-components=1
        mv "$CACHE/.cmake-linux-extract" "$c"
        cmake_license "$c"
    fi
    if [ ! -x "$n/ninja" ]; then
        need_unzip
        fetch "https://github.com/ninja-build/ninja/releases/download/v$NINJA_VERSION/ninja-linux.zip" \
              "$CACHE/ninja-linux.zip"
        rm -rf "$n" "$CACHE/.ninja-linux-extract"
        mkdir -p "$CACHE/.ninja-linux-extract"
        unzip -q -o "$CACHE/ninja-linux.zip" -d "$CACHE/.ninja-linux-extract"
        mv "$CACHE/.ninja-linux-extract" "$n"
        ninja_license "$n"
    fi
    echo "== bundled CMake: $c/bin/cmake"
    echo "== bundled Ninja: $n/ninja"
}

fetch_windows() {
    local c="$CACHE/cmake-windows" n="$CACHE/ninja-windows"
    local llvm="$CACHE/llvm-mingw" sdl="$CACHE/sdl3-mingw" py="$CACHE/python-embed"
    if [ ! -f "$c/bin/cmake.exe" ]; then
        need_unzip
        fetch "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-windows-x86_64.zip" \
              "$CACHE/cmake-windows.zip"
        rm -rf "$c" "$CACHE/.cmake-windows-extract"
        mkdir -p "$CACHE/.cmake-windows-extract"
        unzip -q -o "$CACHE/cmake-windows.zip" -d "$CACHE/.cmake-windows-extract"
        mv "$CACHE/.cmake-windows-extract/cmake-$CMAKE_VERSION-windows-x86_64" "$c"
        rmdir "$CACHE/.cmake-windows-extract" 2>/dev/null || true
        cmake_license "$c"
    fi
    if [ ! -f "$n/ninja.exe" ]; then
        need_unzip
        fetch "https://github.com/ninja-build/ninja/releases/download/v$NINJA_VERSION/ninja-win.zip" \
              "$CACHE/ninja-win.zip"
        rm -rf "$n" "$CACHE/.ninja-windows-extract"
        mkdir -p "$CACHE/.ninja-windows-extract"
        unzip -q -o "$CACHE/ninja-win.zip" -d "$CACHE/.ninja-windows-extract"
        mv "$CACHE/.ninja-windows-extract" "$n"
        ninja_license "$n"
    fi

    # A portable clang + UCRT sysroot and a matching SDL3, so the Windows
    # package does not need MSYS2 or a separately installed compiler.
    if [ ! -x "$llvm/bin/clang++.exe" ]; then
        need_unzip
        fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/llvm-mingw-$LLVM_MINGW_VERSION-ucrt-x86_64.zip" \
              "$CACHE/llvm-mingw.zip"
        rm -rf "$llvm" "$CACHE/.llvm-mingw-extract"
        mkdir -p "$CACHE/.llvm-mingw-extract"
        unzip -q -o "$CACHE/llvm-mingw.zip" -d "$CACHE/.llvm-mingw-extract"
        mv "$CACHE/.llvm-mingw-extract/llvm-mingw-$LLVM_MINGW_VERSION-ucrt-x86_64" "$llvm"
        rmdir "$CACHE/.llvm-mingw-extract" 2>/dev/null || true
        # Keep only the x86_64 UCRT target; the archive also carries every
        # other architecture and a bundled Python.
        rm -rf "$llvm/python" "$llvm/busybox" \
               "$llvm/i686-w64-mingw32" "$llvm/aarch64-w64-mingw32" \
               "$llvm/armv7-w64-mingw32"
        rm -rf "$llvm"/lib/clang/*/lib/linux
        # Editor/debugger front ends are not part of a build.
        rm -f "$llvm/bin/clangd.exe" "$llvm/bin/clang-tidy.exe" \
              "$llvm/bin/clang-format.exe" "$llvm/bin/clang-scan-deps"*.exe \
              "$llvm/bin/liblldb.dll" "$llvm/bin/libpython"*.dll \
              "$llvm/bin/lldb"*.exe
    fi
    if [ ! -f "$sdl/lib/cmake/SDL3/SDL3Config.cmake" ]; then
        need_unzip
        fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL3_VERSION/SDL3-devel-$SDL3_VERSION-mingw.zip" \
              "$CACHE/sdl3-mingw.zip"
        rm -rf "$sdl" "$CACHE/.sdl3-mingw-extract"
        mkdir -p "$CACHE/.sdl3-mingw-extract"
        unzip -q -o "$CACHE/sdl3-mingw.zip" -d "$CACHE/.sdl3-mingw-extract"
        mkdir -p "$sdl"
        cp -a "$CACHE/.sdl3-mingw-extract/SDL3-$SDL3_VERSION/x86_64-w64-mingw32/." "$sdl/"
        cp "$CACHE/.sdl3-mingw-extract/SDL3-$SDL3_VERSION/LICENSE.txt" "$sdl/" 2>/dev/null || true
        rm -rf "$CACHE/.sdl3-mingw-extract"
    fi
    if [ ! -f "$py/python.exe" ]; then
        need_unzip
        fetch "https://www.python.org/ftp/python/$PYTHON_EMBED_VERSION/python-$PYTHON_EMBED_VERSION-embed-amd64.zip" \
              "$CACHE/python-embed.zip"
        rm -rf "$py"
        mkdir -p "$py"
        unzip -q -o "$CACHE/python-embed.zip" -d "$py"
        # The embeddable build isolates sys.path from PYTHONPATH.  Add the
        # package's project tree so `python -m wiikit.disc` still works.
        for pth in "$py"/*._pth; do
            [ -f "$pth" ] || continue
            grep -qx '../../project' "$pth" || printf '\n../../project\n' >> "$pth"
        done
    fi

    echo "== bundled CMake: $c/bin/cmake.exe"
    echo "== bundled Ninja: $n/ninja.exe"
    echo "== bundled clang: $llvm/bin/clang++.exe"
    echo "== bundled SDL3: $sdl"
    echo "== bundled Python: $py/python.exe"
}

case "$TARGET" in
    linux)   fetch_linux ;;
    windows) fetch_windows ;;
    *)
        echo "usage: $0 linux|windows" >&2
        exit 2
        ;;
esac
