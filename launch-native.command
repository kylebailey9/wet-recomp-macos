#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Prefer sibling wet-recomp checkout
if [[ ! -x "$ROOT/wet" && -x "$ROOT/wet-recomp/wet" ]]; then
  ROOT="$ROOT/wet-recomp"
fi
cd "$ROOT"
[[ -x "$ROOT/wet" ]] || { echo "Native wet binary missing. Run setup-macos.sh && build-macos.sh"; exit 1; }

# MoltenVK ICD
if [[ -z "${VK_ICD_FILENAMES:-}" ]]; then
  for icd in \
    "$(brew --prefix molten-vk 2>/dev/null)/share/vulkan/icd.d/MoltenVK_icd.json" \
    "$(brew --prefix moltenvk 2>/dev/null)/share/vulkan/icd.d/MoltenVK_icd.json" \
    "$ROOT/MoltenVK_icd.json"
  do
    [[ -f "$icd" ]] && export VK_ICD_FILENAMES="$icd" && break
  done
fi
# macOS: SDL "Spaces" fullscreen leaves the CAMetalLayer drawable at 1x1 after the
# windowed->fullscreen swapchain recreate, so every presented frame is black.
# Use non-Spaces fullscreen instead (override by exporting the var yourself).
export SDL_VIDEO_MAC_FULLSCREEN_SPACES="${SDL_VIDEO_MAC_FULLSCREEN_SPACES:-0}"

export DYLD_LIBRARY_PATH="$ROOT:${DYLD_LIBRARY_PATH:-}"
exec "$ROOT/wet" "$@"
