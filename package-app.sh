#!/usr/bin/env bash
# package-app.sh - wrap the staged native WET build into a double-clickable
# macOS app bundle (default: ~/Applications/WET.app).
#
# Re-run after every rebuild/stage:   ./package-app.sh [--refresh-game] [--dmg]
#
# The bundle is fully self-contained: binary, dylibs, MoltenVK and the extracted
# game data (Contents/Resources/game). Game data is APFS-cloned (cp -c), so it
# costs almost no extra disk space while the source files still exist.
# On re-runs the game data is cloned from the existing WET.app (fast, the repo's
# game/ isn't needed); --refresh-game re-clones it from the repo's game/ folder.
#
# Everything the app writes lives outside the bundle (keeps the signature valid):
#   logs                 ~/Library/Logs/WET/wet_NNN.log (+ app-stdout.log)
#   saves/profile/cache  ~/Library/Application Support/WET  (cache/ for shaders)
#
# --dmg also builds a drag-to-install disk image (WET.app + /Applications link).
#
# Options (env vars):
#   WET_DMG_PATH   disk image path             (default ~/Games/WET.dmg)
#   WET_DMG_FORMAT hdiutil format              (default UDZO; game data is already compressed,
#                  so UDZO was smaller+faster than ULFO in a test)
#   WET_APP_PATH   where to write the bundle   (default ~/Applications/WET.app)
#   WET_GAME_SRC   extracted game dir to clone (default: <repo>/game)
#   WET_MOLTENVK   MoltenVK dylib to bundle    (default: Homebrew's, else ./libMoltenVK.dylib)
#   WET_BUNDLE_ID  CFBundleIdentifier          (default com.kylebailey.wet)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP="${WET_APP_PATH:-$HOME/Applications/WET.app}"
GAME_SRC="${WET_GAME_SRC:-$ROOT/game}"
REFRESH_GAME=0
MAKE_DMG=0
DMG="${WET_DMG_PATH:-$HOME/Games/WET.dmg}"
DMG_FORMAT="${WET_DMG_FORMAT:-UDZO}"
for arg in "$@"; do
  case "$arg" in
    --refresh-game) REFRESH_GAME=1 ;;
    --dmg) MAKE_DMG=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "package-app: unknown option $arg" >&2; exit 2 ;;
  esac
done
BUNDLE_ID="${WET_BUNDLE_ID:-com.kylebailey.wet}"
ICON_SRC="$ROOT/launcher/WetLauncher/Assets/icon.png"
FW_RPATH="@executable_path/../Frameworks"

die() { echo "package-app: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# ---- inputs -----------------------------------------------------------------
for f in wet librexruntime.dylib librexgpu-xenos.dylib; do
  [[ -f "$ROOT/$f" ]] || die "missing staged $ROOT/$f (build + stage first)"
done

# Where the bundled game data comes from.
if [[ $REFRESH_GAME -eq 0 && -f "$APP/Contents/Resources/game/default.xex" ]]; then
  GAME_FROM="$APP/Contents/Resources/game"; GAME_MODE="existing app"
else
  [[ -f "$GAME_SRC/default.xex" ]] || die "no game at $GAME_SRC/default.xex (set WET_GAME_SRC)"
  GAME_FROM="$(cd "$GAME_SRC" && pwd -P)"; GAME_MODE="source"
fi

MVK="${WET_MOLTENVK:-}"
if [[ -z "$MVK" ]]; then
  for c in /opt/homebrew/lib/libMoltenVK.dylib /usr/local/lib/libMoltenVK.dylib "$ROOT/libMoltenVK.dylib"; do
    [[ -f "$c" ]] && { MVK="$c"; break; }
  done
fi
[[ -n "$MVK" && -f "$MVK" ]] || die "libMoltenVK.dylib not found (set WET_MOLTENVK)"
MVK="$(cd "$(dirname "$MVK")" && pwd -P)/$(basename "$MVK")"
MVK="$(readlink -f "$MVK" 2>/dev/null || echo "$MVK")"

if pgrep -f "$APP/Contents/MacOS/wet-bin" >/dev/null 2>&1; then
  die "WET.app is running - quit it first"
fi

MINOS="$(otool -l "$ROOT/wet" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')"
[[ -n "$MINOS" ]] || MINOS="13.0"

# ---- build in a temp dir, then swap into place -------------------------------
# Build next to the destination so the final move is an instant same-volume
# rename (and clones work).
mkdir -p "$(dirname "$APP")"
TMP="$(mktemp -d "$(dirname "$APP")/.wetapp.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
B="$TMP/WET.app"; C="$B/Contents"
mkdir -p "$C/MacOS" "$C/Frameworks" "$C/Resources/vulkan/lib" \
         "$C/Resources/vulkan/share/vulkan/icd.d"

log "copying binaries (MoltenVK: $MVK)"
cp "$ROOT/wet" "$C/MacOS/wet-bin"
cp "$ROOT/librexruntime.dylib" "$ROOT/librexgpu-xenos.dylib" "$C/Frameworks/"
[[ -f "$ROOT/libTracyClient.dylib" ]] && cp "$ROOT/libTracyClient.dylib" "$C/Frameworks/"
cp "$MVK" "$C/Frameworks/libMoltenVK.dylib"
chmod 755 "$C/MacOS/wet-bin"; chmod 644 "$C/Frameworks/"*.dylib

# The runtime only looks for the GPU plugin next to the executable.
ln -s ../Frameworks/librexgpu-xenos.dylib "$C/MacOS/librexgpu-xenos.dylib"
# The runtime's macOS Vulkan probe checks <bundle>/Contents/Resources/vulkan
# for lib/libMoltenVK.dylib before falling back to /opt/homebrew.
ln -s ../../../Frameworks/libMoltenVK.dylib "$C/Resources/vulkan/lib/libMoltenVK.dylib"
cat > "$C/Resources/vulkan/share/vulkan/icd.d/MoltenVK_icd.json" <<'JSON'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "../../../lib/libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": true
    }
}
JSON

# ---- game data (APFS clones) -----------------------------------------------------
# Only the extracted files: no ISO, no .bak files, no repo helper scripts.
log "cloning game data from $GAME_MODE: $GAME_FROM"
G="$C/Resources/game"; mkdir -p "$G"
shopt -s nullglob dotglob
for e in "$GAME_FROM"/*; do
  n="$(basename "$e")"
  case "$n" in
    *.iso|*.ISO|*.bak|.gitkeep|.DS_Store|setup-macos.sh) continue ;;
  esac
  cp -c -R -p "$e" "$G/" || die "clone failed for $n (APFS volume required)"
done
shopt -u nullglob dotglob
find "$G" \( -iname '*.iso' -o -name '*.bak' -o -name '.DS_Store' \) -type f -delete
[[ -f "$G/default.xex" ]] || die "bundled game has no default.xex"
log "game data: $(du -sh "$G" | cut -f1) (du, counts clones in full), $(find "$G" -type f | wc -l | tr -d ' ') files"

# ---- fix load paths ------------------------------------------------------------
strip_abs_rpaths() {  # remove every LC_RPATH that is not @-relative
  local f="$1" p
  while IFS= read -r p; do
    [[ -z "$p" || "$p" == @* ]] && continue
    install_name_tool -delete_rpath "$p" "$f" 2>/dev/null || true
  done < <(otool -l "$f" | awk '/cmd LC_RPATH/{r=1;next} r&&/ path /{print $2; r=0}')
}
has_rpath() { otool -l "$1" | awk '/cmd LC_RPATH/{r=1;next} r&&/ path /{print $2; r=0}' | grep -qx "$2"; }

log "rewriting install names / rpaths"
strip_abs_rpaths "$C/MacOS/wet-bin"
has_rpath "$C/MacOS/wet-bin" "$FW_RPATH" || install_name_tool -add_rpath "$FW_RPATH" "$C/MacOS/wet-bin"
rpath_deps() {  # @rpath deps of $1 other than its own install name
  local self; self="$(otool -D "$1" | tail -n +2)"
  otool -L "$1" | tail -n +2 | awk '{print $1}' | grep '^@rpath/' | grep -v -x -F "$self" || true
}
for d in "$C/Frameworks/"*.dylib; do
  # Absolute install ids (e.g. Homebrew's /opt/homebrew/opt/molten-vk/...) ->
  # @rpath/<name>; the new name is shorter, so it always fits.
  cur_id="$(otool -D "$d" | tail -n +2)"
  [[ "$cur_id" == @* ]] || install_name_tool -id "@rpath/$(basename "$d")" "$d"
  strip_abs_rpaths "$d"
  # Only touch dylibs that actually load other @rpath libraries (MoltenVK has
  # no header padding, and doesn't need it: it only links system frameworks).
  if [[ -n "$(rpath_deps "$d")" ]]; then
    has_rpath "$d" "$FW_RPATH" || install_name_tool -add_rpath "$FW_RPATH" "$d"
  fi
done

# Every non-system dependency must now resolve inside the bundle.
for f in "$C/MacOS/wet-bin" "$C/Frameworks/"*.dylib; do
  self_id="$(otool -D "$f" | tail -n +2)"
  bad="$(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -v -x -F "${self_id:-/nonexistent}" | grep -v -E '^(/usr/lib/|/System/|@rpath/|@executable_path/|@loader_path/)' || true)"
  [[ -z "$bad" ]] || die "$(basename "$f") still depends on: $bad"
  while IFS= read -r dep; do
    [[ -f "$C/Frameworks/${dep#@rpath/}" ]] || die "$(basename "$f") needs $dep, not bundled"
  done < <(if [[ "$f" == *.dylib ]]; then rpath_deps "$f"; else otool -L "$f" | tail -n +2 | awk '{print $1}' | grep '^@rpath/' || true; fi)
done

# ---- launcher --------------------------------------------------------------------
log "writing launcher"
cat > "$C/MacOS/WET" <<'LAUNCHER'
#!/bin/bash
# WET.app launcher (generated by package-app.sh). Everything the game needs is
# inside the bundle; everything it writes goes to per-user folders.
MACOS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONTENTS="$(dirname "$MACOS_DIR")"
GAME_DIR="${WET_GAME_DIR:-$CONTENTS/Resources/game}"
SUPPORT_DIR="$HOME/Library/Application Support/WET"
LOG_DIR="$HOME/Library/Logs/WET"

if [[ ! -f "$GAME_DIR/default.xex" ]]; then
  /usr/bin/osascript -e "display alert \"WET\" message \"Game files not found at $GAME_DIR. Re-run package-app.sh --refresh-game.\"" >/dev/null 2>&1
  exit 1
fi
mkdir -p "$SUPPORT_DIR/cache" "$LOG_DIR"

VK_ROOT="$CONTENTS/Resources/vulkan"
export REX_VULKAN_SDK="$VK_ROOT"
export VK_ICD_FILENAMES="$VK_ROOT/share/vulkan/icd.d/MoltenVK_icd.json"
export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
# SDL "Spaces" fullscreen leaves the CAMetalLayer drawable at 1x1 -> black screen.
export SDL_VIDEO_MAC_FULLSCREEN_SPACES="${SDL_VIDEO_MAC_FULLSCREEN_SPACES:-0}"
unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH

# Any relative path the runtime might write lands in the writable support dir.
cd "$SUPPORT_DIR" || exit 1

# Drop the legacy Finder -psn_ argument; note which paths the caller overrode.
args=()
have_log=0 have_game=0 have_user=0 have_cache=0
for a in "$@"; do
  case "$a" in
    -psn_*) continue ;;
    --log_file*) have_log=1 ;;
    --game_data_root*) have_game=1 ;;
    --user_data_root*) have_user=1 ;;
    --cache_root*) have_cache=1 ;;
  esac
  args+=("$a")
done

pre=()
[[ $have_game -eq 1 ]]  || pre+=("--game_data_root=$GAME_DIR")
[[ $have_user -eq 1 ]]  || pre+=("--user_data_root=$SUPPORT_DIR")
[[ $have_cache -eq 1 ]] || pre+=("--cache_root=$SUPPORT_DIR/cache")
# The runtime's own auto-numbered log would go to <exe dir>/logs, inside the
# signed bundle; pick the next wet_NNN.log in ~/Library/Logs/WET instead.
if [[ $have_log -eq 0 ]]; then
  n=0
  for f in "$LOG_DIR"/wet_[0-9]*.log; do
    [[ -e "$f" ]] || continue
    b="${f##*/wet_}"; b="${b%.log}"
    [[ "$b" =~ ^[0-9]+$ ]] || continue
    (( 10#$b > n )) && n=$((10#$b))
  done
  printf -v LOG_FILE '%s/wet_%03d.log' "$LOG_DIR" $((n + 1))
  pre+=("--log_file=$LOG_FILE")
fi

# stdout/stderr (MoltenVK messages etc.); the real log is wet_NNN.log.
exec "$MACOS_DIR/wet-bin" "${pre[@]}" ${args[@]+"${args[@]}"} >"$LOG_DIR/app-stdout.log" 2>&1
LAUNCHER
chmod 755 "$C/MacOS/WET"

# ---- icon --------------------------------------------------------------------------
ICON_KEY=""
if [[ -f "$ICON_SRC" ]]; then
  log "building icon from $ICON_SRC"
  IS="$TMP/WET.iconset"; mkdir -p "$IS"
  for s in 16 32 128 256 512; do
    sips -s format png -z $s $s "$ICON_SRC" --out "$IS/icon_${s}x${s}.png" >/dev/null
    d=$((s*2)); sips -s format png -z $d $d "$ICON_SRC" --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
  done
  if iconutil -c icns "$IS" -o "$C/Resources/WET.icns"; then ICON_KEY="WET"; fi
fi

# ---- Info.plist -----------------------------------------------------------------------
log "writing Info.plist (LSMinimumSystemVersion $MINOS)"
cat > "$C/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>WET</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>WET</string>
  <key>CFBundleDisplayName</key><string>WET</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d.%H%M)</string>
  <key>CFBundleIconFile</key><string>${ICON_KEY}</string>
  <key>LSMinimumSystemVersion</key><string>$MINOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$C/Info.plist" >/dev/null
printf 'APPL????' > "$C/PkgInfo"

# ---- sign (inside-out, ad-hoc) ------------------------------------------------------
log "ad-hoc signing"
xattr -cr "$B"
for d in "$C/Frameworks/"*.dylib; do codesign --force --timestamp=none -s - "$d"; done
codesign --force --timestamp=none -s - "$C/MacOS/wet-bin"
codesign --force --deep --timestamp=none -s - "$B"

# ---- install (same-volume rename; clones stay clones) ---------------------------
if [[ -e "$APP" ]]; then rm -rf "$APP"; fi
mv "$B" "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
touch "$APP"
log "done: $APP  ($(du -sh "$APP" | cut -f1) on disk as counted by du; game data are clones)"

# ---- optional disk image -------------------------------------------------------------
if [[ $MAKE_DMG -eq 1 ]]; then
  # The image is a real file: clones don't carry into it. Need ~app size free
  # for the compressed image plus hdiutil's scratch space.
  need_kb=$(( $(du -sk "$APP" | cut -f1) + 1048576 ))
  free_kb=$(df -k "$(dirname "$DMG")" | awk 'NR==2{print $4}')
  (( free_kb > need_kb )) || die "not enough free space for $DMG (need ~$((need_kb/1048576)) GB)"
  log "building $DMG ($DMG_FORMAT)"
  STAGE="$(mktemp -d "$(dirname "$APP")/.wetdmg.XXXXXX")"
  trap 'rm -rf "$TMP" "$STAGE"' EXIT
  cp -c -R -p "$APP" "$STAGE/WET.app"          # clone: instant, no extra space
  ln -s /Applications "$STAGE/Applications"
  mkdir -p "$(dirname "$DMG")"
  hdiutil create -quiet -ov -volname WET -srcfolder "$STAGE" -format "$DMG_FORMAT" "$DMG"
  hdiutil verify -quiet "$DMG"
  MNT="$(mktemp -d /tmp/wetdmg-mnt.XXXXXX)"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
  ok=1
  codesign --verify --deep --strict "$MNT/WET.app" || ok=0
  [[ -L "$MNT/Applications" && -f "$MNT/WET.app/Contents/Resources/game/default.xex" ]] || ok=0
  hdiutil detach -quiet "$MNT" || hdiutil detach -quiet -force "$MNT"
  rmdir "$MNT" 2>/dev/null || true
  [[ $ok -eq 1 ]] || die "disk image check failed: $DMG"
  log "dmg ok: $DMG ($(du -h "$DMG" | cut -f1))"
fi
