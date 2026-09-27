# wet-recomp-macos

macOS (Apple Silicon) scripts and config for building and running
[Supermedo/wet-recomp](https://github.com/Supermedo/wet-recomp), the unofficial
static recompilation of *WET* (Xbox 360, 2009) made with
[ReXGlue](https://github.com/rexglue/rexglue-sdk) v0.10.0.

This is an add-on, not a fork. All of the recompilation work is from
wet-recomp (by Mohammed Albarghouthi) and ReXGlue. This repo only adds the
pieces needed to build a native Mach-O binary with MoltenVK, run it, and wrap it
in a `.app`.

**No game content is included.** You need your own legally dumped copy of the
WET Xbox 360 disc. Do not share `game/`, ISOs, `default.xex`, the built
`WET.app`, or DMGs made from it. They contain the game.

## What's here

| File | Purpose |
|---|---|
| `setup-macos.sh` | macOS version of upstream `setup.ps1`: checks tools, installs MoltenVK and Vulkan headers through Homebrew, clones ReXGlue v0.10.0 with submodules, applies upstream's input patch, builds the `rexglue` CLI, runs `rexglue init` and codegen. |
| `build-macos.sh` | Builds `wet` with the `mac-arm64-release` preset (`mac-amd64-release` on Intel) and copies the binary and dylibs into the checkout root. |
| `build-xcode.sh` | Alternative build through a generated Xcode project (`out/build/xcode`). |
| `launch-native.command` | Runs `./wet` with the MoltenVK ICD and `DYLD_LIBRARY_PATH` set, and with the fullscreen fix below. Can be double-clicked in Finder. |
| `package-app.sh` | Makes a self-contained, ad-hoc signed `WET.app` (binary, dylibs, MoltenVK, game data). `--dmg` also makes a drag-to-install disk image. `--help` lists options. |
| `wet_manifest.toml` | ReXGlue manifest with 138 `[entrypoint.functions]` entries, mostly indirect-call targets the analysis missed (see below). This is just addresses and sizes. |
| `patches/wet-recomp-macos.patch` | Small change to upstream `CMakeLists.txt`: compiles `generated/default/wet_register.cpp` at `-O1`. |
| `patches/rexglue-sdk-macos.patch` | Small change to two ReXGlue CMake files so the MoltenVK ICD path resolves when the SDK is used via `add_subdirectory`. |

## Requirements

- Apple Silicon Mac. Intel presets exist in the scripts but were not tested.
- Xcode 16 or newer (ReXGlue needs AppleClang 16+ for C++23), with the command line tools.
- Homebrew and these packages:
  ```sh
  brew install git cmake ninja molten-vk vulkan-headers
  ```
  `setup-macos.sh` installs `molten-vk` and `vulkan-headers` itself if they are missing.
  Rendering goes through Vulkan on top of MoltenVK (Metal).
- [extract-xiso](https://github.com/XboxDev/extract-xiso) to unpack the ISO (not in Homebrew core; build it from source with CMake).
- Your own dump of the WET Xbox 360 disc (`.iso`).
- `package-app.sh` needs the app destination on an APFS volume (it uses `cp -c` clones for the game data).

## Build and run

1. Clone upstream. It has no submodules of its own; the SDK and its submodules are
   cloned by `setup-macos.sh`.
   ```sh
   git clone --recurse-submodules https://github.com/Supermedo/wet-recomp.git
   git clone https://github.com/kylebailey9/wet-recomp-macos.git
   cd wet-recomp
   ```

2. Copy this repo's files into the checkout root (the `patches/` files sit next to upstream's `rexglue-input.patch`):
   ```sh
   cp ../wet-recomp-macos/*.sh ../wet-recomp-macos/launch-native.command .
   cp ../wet-recomp-macos/wet_manifest.toml .
   cp ../wet-recomp-macos/patches/*.patch patches/
   chmod +x *.sh launch-native.command
   ```

3. Extract your ISO into `game/`:
   ```sh
   extract-xiso -x /path/to/WET.iso -d game/
   ls -l game/default.xex
   ```
   `game/default.xex` must be WET's executable, about 22.4 MB. See
   "Wrong default.xex" below.

4. Apply the two small patches. Clone the SDK first so the SDK patch can be applied;
   `setup-macos.sh` skips the clone if the SDK is already there.
   ```sh
   git apply patches/wet-recomp-macos.patch
   git clone --branch v0.10.0 --depth 1 https://github.com/rexglue/rexglue-sdk.git thirdparty/rexglue-sdk
   git -C thirdparty/rexglue-sdk apply ../../patches/rexglue-sdk-macos.patch
   ```

5. Run setup. This builds the `rexglue` CLI, runs `rexglue init` and a first codegen.
   ```sh
   ./setup-macos.sh
   ```

6. Put this repo's manifest in place (after setup, since `rexglue init --force`
   may regenerate `wet_manifest.toml`) and run codegen again:
   ```sh
   cp ../wet-recomp-macos/wet_manifest.toml .
   cmake --build out/build/mac-arm64-release --target wet_codegen
   ```

7. Build:
   ```sh
   ./build-macos.sh        # or ./build-xcode.sh
   ```

8. Run:
   ```sh
   ./launch-native.command
   ```
   Logs go to `logs/wet_NNN.log` in the checkout.

9. Optional: package an app and/or a DMG.
   ```sh
   ./package-app.sh              # writes ~/Applications/WET.app
   ./package-app.sh --dmg        # also writes ~/Games/WET.dmg
   ```
   Re-run after every rebuild. The app keeps nothing writable inside the bundle
   on purpose: logs go to `~/Library/Logs/WET/`, saves, profile and shader cache to
   `~/Library/Application Support/WET/`. Options: `WET_APP_PATH`, `WET_DMG_PATH`,
   `WET_DMG_FORMAT`, `WET_GAME_SRC`, `WET_MOLTENVK`, `WET_BUNDLE_ID`, `--refresh-game`.
   The app and DMG contain your game data. Keep them for your own use.

## Problems found during the port and how they were handled

### Wrong default.xex

At one point the `default.xex` in `game/` was from a different game (a
"GearGame" build), not WET. Check the size before running setup: WET's
`default.xex` is about 22.4 MB. If you swap the xex, re-run `./setup-macos.sh` so init and codegen
use the right file.

### Missing functions: `FATAL ... unregistered function at guest address`

ReXGlue's analysis misses some functions that are only reached through function
pointers (vtable forwarding thunks, `boost::function` managers, entries in data
tables, functions placed right after a `bctr`/`b` that got merged into the
function before them). When the game calls one, it stops with a FATAL error
about an unregistered function at a guest address.

Workflow:

1. Find the address in the log (`logs/wet_NNN.log`, or `~/Library/Logs/WET/` for the app).
2. Add it to `wet_manifest.toml`:
   ```toml
   [entrypoint.functions.0x82B79D30]
   ```
   Add `size = N` if the function's size is known (for example 16 for the
   `lwz r12,0(r3); lwz r11,N(r12); mtctr r11; bctr` thunks).
3. Re-run codegen, rebuild, and re-package if you use the app:
   ```sh
   cmake --build out/build/mac-arm64-release --target wet_codegen
   ./build-macos.sh
   ./package-app.sh
   ```

It is worth checking neighbouring function-pointer targets at the same time.
The included manifest has 138 entries; the ones added during the Mac bring-up
have comments saying why.

### `Unresolved branch` during codegen

If codegen reports an unresolved branch inside a function that has an explicit
`size`, the size is too small and cuts off part of the function. Increase it to
cover the whole function. In this manifest `0x82AE14C8` was changed from
`size = 156` to `size = 192` for this reason.

### Black screen in fullscreen

With SDL's default macOS fullscreen (a separate Space), the `CAMetalLayer`
drawable stays at 1x1 after the swapchain is recreated for fullscreen, so every
frame is black. `launch-native.command` and the `WET.app` launcher set
`SDL_VIDEO_MAC_FULLSCREEN_SPACES=0` to use non-Spaces fullscreen. Export the
variable yourself to override it.

### Harmless messages

- A MoltenVK warning about primitive restart shows up in the output. It is
  harmless and can be ignored.
- The post-build step that copies `MoltenVK_icd.json` next to the binary can fail.
  This is harmless: `launch-native.command` uses Homebrew's MoltenVK ICD, and
  `package-app.sh` writes its own ICD into the bundle.

## Known issues

- Changing settings in-game (F4) from `WET.app` writes the settings file into the
  app bundle instead of `~/Library/Application Support/WET`. That modifies the
  signed bundle (so `codesign --verify` fails afterwards), and the settings are
  lost the next time `package-app.sh` rebuilds the app. Not fixed yet.
- Only tested on Apple Silicon.

## Credits and license

- [Supermedo/wet-recomp](https://github.com/Supermedo/wet-recomp): the WET
  recompilation this builds on (MIT).
- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) by Tom Clay, with code
  derived from [Xenia](https://xenia.jp) (BSD 3-Clause).
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK), [SDL](https://libsdl.org),
  [extract-xiso](https://github.com/XboxDev/extract-xiso).

The scripts, patches and manifest in this repo are MIT licensed, the same as
upstream wet-recomp. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.

*WET* and its assets belong to their copyright holders. This project is
unofficial and is not affiliated with them.
