#!/usr/bin/env bash
# Native macOS setup for Supermedo/wet-recomp (ReXGlue 0.10+ / MoltenVK).
# Run on your Mac inside a wet-recomp git clone that already has game/default.xex.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# If this script lives in native-macos/ next to a clone, or was copied into the repo:
if [[ -f "$ROOT/CMakeLists.txt" ]]; then
  :
elif [[ -f "$ROOT/../CMakeLists.txt" ]]; then
  ROOT="$(cd "$ROOT/.." && pwd)"
elif [[ -f "$ROOT/wet-recomp/CMakeLists.txt" ]]; then
  ROOT="$(cd "$ROOT/wet-recomp" && pwd)"
else
  echo "Place this script in a wet-recomp checkout (or set WET_RECOMP_ROOT)." >&2
  exit 2
fi
ROOT="${WET_RECOMP_ROOT:-$ROOT}"
cd "$ROOT"

SDK_DIR="$ROOT/thirdparty/rexglue-sdk"
TAG="${REXGLUE_TAG:-v0.10.0}"
XEX="$ROOT/game/default.xex"
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
  PRESET="${WET_PRESET:-mac-arm64-release}"
else
  PRESET="${WET_PRESET:-mac-amd64-release}"
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "Run on macOS."; exit 1; }
[[ -f "$XEX" ]] || {
  echo "Missing game/default.xex"
  echo "Dump your own Xbox 360 WET ISO, extract with extract-xiso (or the Windows launcher),"
  echo "and put the game files under: $ROOT/game/"
  exit 2
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install: brew install $*"; exit 1; }; }
need git
need cmake
need ninja
need clang
need clang++

# MoltenVK / Vulkan loader (Homebrew)
if ! brew list molten-vk >/dev/null 2>&1 && ! brew list moltenvk >/dev/null 2>&1; then
  echo "Installing MoltenVK via Homebrew…"
  brew install molten-vk || brew install moltenvk || true
fi
if ! brew list vulkan-headers >/dev/null 2>&1; then
  brew install vulkan-headers || true
fi

export CC="${CC:-/usr/bin/clang}"
export CXX="${CXX:-/usr/bin/clang++}"
# Help ReXGlue find MoltenVK
export VULKAN_SDK="${VULKAN_SDK:-$(brew --prefix molten-vk 2>/dev/null || brew --prefix moltenvk 2>/dev/null || true)}"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-}"
if [[ -z "$VK_ICD_FILENAMES" ]]; then
  for icd in \
    "$(brew --prefix molten-vk 2>/dev/null)/share/vulkan/icd.d/MoltenVK_icd.json" \
    "$(brew --prefix)/share/vulkan/icd.d/MoltenVK_icd.json"
  do
    [[ -f "$icd" ]] && export VK_ICD_FILENAMES="$icd" && break
  done
fi

if [[ ! -d "$SDK_DIR/.git" ]]; then
  git clone --branch "$TAG" --depth 1 https://github.com/rexglue/rexglue-sdk.git "$SDK_DIR"
fi
git -C "$SDK_DIR" submodule update --init --recursive --depth 1

PATCH="$ROOT/patches/rexglue-input.patch"
if [[ -f "$PATCH" ]]; then
  if git -C "$SDK_DIR" apply --check --ignore-whitespace "$PATCH" 2>/dev/null; then
    git -C "$SDK_DIR" apply --ignore-whitespace "$PATCH"
  else
    echo "Note: input patch skipped (already applied or does not match)."
  fi
fi

echo "Configuring preset $PRESET…"
cmake --preset "$PRESET" "-DREXSDK_DIR=$SDK_DIR"
BUILD_DIR="$ROOT/out/build/$PRESET"
cmake --build "$BUILD_DIR" --target rexglue -j"$(sysctl -n hw.ncpu)"

CLI=""
for cand in \
  "$SDK_DIR/out/mac-arm64/Release/rexglue" \
  "$SDK_DIR/out/mac-amd64/Release/rexglue" \
  "$SDK_DIR/out/mac-arm64/rexglue" \
  "$SDK_DIR/out/mac-amd64/rexglue" \
  "$BUILD_DIR/rexglue"
do
  [[ -x "$cand" ]] && { CLI="$cand"; break; }
done
[[ -n "$CLI" ]] || { echo "rexglue CLI not found after build"; exit 1; }

"$CLI" init --force --project-name wet --project-root "$ROOT" --xex-path "$XEX" --game-root "$ROOT/game"
cmake --build "$BUILD_DIR" --target wet_codegen -j"$(sysctl -n hw.ncpu)"
echo "Setup done. Run: ./build-macos.sh"
