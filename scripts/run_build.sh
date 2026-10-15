#!/usr/bin/env bash
# Block design, synthesis, implementation and bitstream. Log: build/vivado_build.log
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build" && cd "$ROOT/build"
vivado -mode batch -nojournal -source ../scripts/build_bd.tcl -log vivado_build.log
