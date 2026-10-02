# WET cloud build via Codespaces

Do this once, in a Codespace on this repo
(github.com/kylebailey9/wet-recomp-macos → **Code** → **Codespaces** →
**Create codespace on main**).

## 1. Get your `default.xex` into the Codespace

Drag your WET Xbox 360 ISO into the VS Code file explorer (or upload
`default.xex` directly if you already extracted it), then in the terminal:

```bash
# If you uploaded the ISO, extract it (takes a minute):
mkdir -p iso-extract && extract-xiso -x your-iso-file.iso -d iso-extract
ls -la iso-extract/default.xex   # should be ~22.4 MB
```

## 2. Encrypt it

```bash
PASSPHRASE=$(openssl rand -base64 36)
echo "SAVE THIS PASSPHRASE: $PASSPHRASE"
mkdir -p game
openssl enc -aes-256-cbc -pbkdf2 \
  -in iso-extract/default.xex \
  -out game/default.xex.enc \
  -pass pass:"$PASSPHRASE"
ls -la game/default.xex.enc
```

Copy the passphrase somewhere safe (password manager). You'll need it once
more in step 4, then never again.

## 3. Add the workflow file and push

```bash
mkdir -p .github/workflows
cp github-workflow-build-macos.yml .github/workflows/build-macos.yml
git add game/default.xex.enc .github/workflows/build-macos.yml .gitignore
git commit -m "Add encrypted default.xex and cloud build workflow"
git push
```

(`.gitignore` already allows `game/default.xex.enc`.)

## 4. Save the passphrase as a secret and start the build

```bash
# Paste the passphrase when prompted:
gh secret set WET_XEX_PASSPHRASE
gh workflow run "Build macOS (Apple Silicon)"
```

## 5. Watch it and grab the result

```bash
gh run watch
```

When it's green, download the `wet-macos-arm64` artifact from the
Actions tab, drop the files next to your own `game/` folder on your Mac,
and run `./launch-native.command`.
