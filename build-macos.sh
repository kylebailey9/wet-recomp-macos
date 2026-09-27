#!/usr/bin/env bash
# Native macOS build — produces ./wet (Mach-O) for Apple Silicon / Intel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$ROOT/CMakeLists.txt" ]]; then
  :
elif [[ -f "$ROOT/../CMakeLists.txt" ]]; then
  ROOT="$(cd "$ROOT/.." && pwd)"
elif [[ -f "$ROOT/wet-recomp/CMakeLists.txt" ]]; then
  ROOT="$(cd "$ROOT/wet-recomp" && pwd)"
fi
ROOT="${WET_RECOMP_ROOT:-$ROOT}"
cd "$ROOT"

XEX="$ROOT/game/default.xex"
SDK_DIR="$ROOT/thirdparty/rexglue-sdk"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  PRESET="${WET_PRESET:-mac-arm64-release}"
else
  PRESET="${WET_PRESET:-mac-amd64-release}"
fi

[[ -f "$XEX" ]] || { echo "game/default.xex missing."; exit 2; }
[[ -f "$SDK_DIR/CMakeLists.txt" ]] || { echo "Run setup-macos.sh first."; exit 2; }

export CC="${CC:-/usr/bin/clang}"
export CXX="${CXX:-/usr/bin/clang++}"

cmake --preset "$PRESET" "-DREXSDK_DIR=$SDK_DIR"
BUILD_DIR="$ROOT/out/build/$PRESET"
cmake --build "$BUILD_DIR" --target wet -j"$(sysctl -n hw.ncpu)"

cp -f "$BUILD_DIR/wet" "$ROOT/wet"
# Stage runtime dylibs if present
for lib in librexruntime.dylib librexgpu-xenos.dylib libMoltenVK.dylib; do
  for d in "$BUILD_DIR" "$SDK_DIR/out/mac-arm64/Release" "$SDK_DIR/out/mac-amd64/Release" \
           "$SDK_DIR/out/mac-arm64" "$SDK_DIR/out/mac-amd64"; do
    [[ -f "$d/$lib" ]] && cp -f "$d/$lib" "$ROOT/"
  done
done
[[ -f "$SDK_DIR/cmake/MoltenVK_icd.json" ]] && cp -f "$SDK_DIR/cmake/MoltenVK_icd.json" "$ROOT/"

echo "Built native binary: $ROOT/wet"
echo "Launch with: ./launch-native.command"
