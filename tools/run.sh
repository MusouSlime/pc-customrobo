#!/usr/bin/env bash
# Custom Robo — run the port.
#
#   tools/run.sh                 # the game
#   tools/run.sh --debug         # with the runtime's debugging switches
#
# wiiboot takes the extracted disc and reads the boot ROM's fonts and the
# DSP ROM's resampling table from build/fonts (tools/setup.sh copies them
# from Dolphin's Sys/GC).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

export LD_LIBRARY_PATH="$HOME/.local/opt/sdl3/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

EXTRACT="$HERE/build/extract"
[ -d "$EXTRACT" ] || { echo "no $EXTRACT: extract the disc first (docs/01-disc-layout.md)"; exit 1; }

BIN="$HERE/build/recomp-build/wiiboot"
[ -x "$BIN" ] || { echo "no $BIN: build the port first (tools/build.sh)"; exit 1; }

SYMS=()
[ -f "$HERE/build/names.tsv" ] && SYMS=(--symbols "$HERE/build/names.tsv")

if [ "${1:-}" = "--debug" ]; then
    export WIIKIT_DIDBG=1 WIIKIT_SIDBG=1 WIIKIT_DISCLOG=1
    export WIIKIT_AUDIODBG=1 WIIKIT_AXTRACE=first:count
    shift
fi

exec "$BIN" "$EXTRACT" "${SYMS[@]}" "$@"
