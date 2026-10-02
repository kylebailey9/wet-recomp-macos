# Cloud builds with GitHub Actions

Builds the native Apple Silicon `wet` binary on a GitHub-hosted Mac, so you
don't need to build on your own machine. The workflow is manual-only
(Actions -> "Build macOS (Apple Silicon)" -> Run workflow) because macOS
runners bill at **10x minutes** — a full build can eat several hundred billed
minutes, so keep an eye on your GitHub plan usage.

## One-time setup (do this on your Mac)

The build needs your own `game/default.xex` (from your personal WET Xbox 360
disc dump) to run codegen. It is never committed in the clear: you commit an
encrypted copy, and the passphrase lives only as a GitHub Actions secret.

1. Encrypt your `default.xex` (about 22.4 MB for WET — anything else is the
   wrong file):
   ```sh
   cd /path/to/wet-recomp-macos
   mkdir -p game
   openssl enc -aes-256-cbc -pbkdf2 \
     -in /path/to/your/game/default.xex \
     -out game/default.xex.enc \
     -pass pass:'PUT-A-LONG-RANDOM-PASSPHRASE-HERE'
   ```
   Use a long random passphrase, not a password you reuse anywhere.

2. Commit the encrypted file plus the new workflow files:
   ```sh
   git add -f game/default.xex.enc
   git add .github/workflows/build-macos.yml CI.md .gitignore
   git commit -m "Cloud macOS build via GitHub Actions"
   git push
   ```
   (The `-f` is needed because `.gitignore` blocks `*.xex.*` by default; the
   ignore file now carries an exception for exactly this one encrypted file.)

3. Add the secret: on GitHub, repo Settings -> Secrets and variables ->
   Actions -> New repository secret. Name: `WET_XEX_PASSPHRASE`, value: the
   passphrase from step 1.

4. Keep this repo **private**. The encrypted blob and the build artifacts are
   derived from your personal disc dump — for your own use only, same as the
   `WET.app`/DMG rules in the README.

## Running a build

Actions tab -> "Build macOS (Apple Silicon)" -> Run workflow. When it finishes,
download the `wet-macos-arm64` artifact (the `wet` binary, its dylibs, and the
MoltenVK ICD). Drop those files next to your own `game/` folder on your Mac
and launch the same way `launch-native.command` does.

## Rotating the passphrase

If the secret ever leaks: pick a new passphrase, re-run step 1, force-push the
new `game/default.xex.enc`, and update the `WET_XEX_PASSPHRASE` secret. The old
encrypted blob is useless without the old passphrase.

## What's next: iPhone

This workflow builds the **macOS** binary — the proven baseline. The iPhone
port is a separate phase: it needs an iOS build configuration added to the
project (new CMake preset, iOS packaging, code signing with your Apple
Developer identity) plus controller/touch input work. Get one green cloud
macOS build first; that's the foundation the iOS port builds on.
