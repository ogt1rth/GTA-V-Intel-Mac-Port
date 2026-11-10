#!/bin/sh
# No game files, network server or iOS device required.
set -eu
cd "$(dirname "$0")/.."
mkdir -p Build/Probe
xcrun clang -std=c11 -O2 -fobjc-arc -fblocks -I Source -I Generated -I Tools/wabt-1.0.42/include \
  -I Tools/wabt-1.0.42/share/wabt/wasm2c -framework Foundation Tests/local_asset_reads.m -o Build/Probe/local-asset-reads
Build/Probe/local-asset-reads
