# WetISOSetup — iOS app

A small iPhone app that does the whole WET cloud-build setup from your phone:

1. Paste a GitHub classic token (repo + workflow scopes) → Connect.
2. Check the `wet-recomp-macos` repo.
3. Tap **Select your WET Xbox 360 ISO** — the app finds and extracts
   `default.xex` from the disc image (or pick `default.xex` directly).
4. Tap **Do everything** — the app encrypts the XEX (same OpenSSL-compatible
   AES-256-CBC/PBKDF2 format the build expects), creates the GitHub Actions
   workflow file, updates `.gitignore`, uploads `game/default.xex.enc`,
   saves the `WET_XEX_PASSPHRASE` secret, and dispatches the cloud build.

Your ISO stays on your device; only the encrypted 22 MB XEX is uploaded.
The token never leaves the app except to call api.github.com.

## Build it

This is a normal Xcode project (iOS 17+). On your Mac:

1. Open `WetISOSetup.xcodeproj` in Xcode.
2. Xcode will automatically fetch the `swift-sodium` package
   (used for GitHub's sealed-box secret encryption) on first open.
3. Select your development team under Signing (free Apple ID signing works
   for installing on your own iPhone).
4. Plug in your iPhone, pick it as the run destination, and hit Run.

Bundle ID is `org.kylebailey94.WetISOSetup` — change it if you like.

## Notes

- The workflow file the app writes is the same one described in `CI.md`.
- After the cloud build finishes, download the `wet-macos-arm64` artifact
  from the Actions tab, drop the files next to your own `game/` folder,
  and run `./launch-native.command` on your Mac.
- An iPhone port of WET itself is a much bigger project (iOS CMake config,
  touch controls, real-device testing) and is not part of this app —
  this app only automates the macOS cloud build from your phone.
