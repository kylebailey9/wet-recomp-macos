#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SDK_DIR="$ROOT/thirdparty/rexglue-sdk"
ARCH="$(uname -m)"
BUILD_DIR="$ROOT/out/build/xcode"

echo "==> Generating Xcode project..."
cmake -G Xcode -B "$BUILD_DIR" "-DREXSDK_DIR=$SDK_DIR" -DCMAKE_OSX_ARCHITECTURES="$ARCH"

echo "==> Building with Xcode (Release)..."
cmake --build "$BUILD_DIR" --config Release --target wet

echo "==> Staging executable and libraries..."
for cand in "$BUILD_DIR/Release/wet" "$BUILD_DIR/wet"; do
  if [[ -f "$cand" ]]; then
    cp -f "$cand" "$ROOT/wet"
    chmod +x "$ROOT/wet"
    break
  fi
done

for lib in librexruntime.dylib librexgpu-xenos.dylib libMoltenVK.dylib libTracyClient.dylib; do
  for d in "$BUILD_DIR/Release" "$BUILD_DIR" "$SDK_DIR/out/mac-arm64/Release" "$SDK_DIR/out/mac-arm64"; do
    [[ -f "$d/$lib" ]] && cp -f "$d/$lib" "$ROOT/"
  done
done
[[ -f "$SDK_DIR/cmake/MoltenVK_icd.json" ]] && cp -f "$SDK_DIR/cmake/MoltenVK_icd.json" "$ROOT/"

echo "==> Build complete: $ROOT/wet"
echo "Launch with: ./launch-native.command"
echo "Or open Xcode project: open $BUILD_DIR/wet.xcodeproj"
