#!/bin/bash
# Runs once when the Codespace is created. Installs extract-xiso so you can
# pull default.xex out of your WET Xbox 360 ISO.
set -e
if ! command -v extract-xiso >/dev/null 2>&1; then
  echo "Installing extract-xiso..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq cmake build-essential
  git clone --depth 1 https://github.com/XboxDev/extract-xiso.git /tmp/extract-xiso
  cmake -S /tmp/extract-xiso -B /tmp/extract-xiso/build -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build /tmp/extract-xiso/build -j"$(nproc)"
  sudo cmake --install /tmp/extract-xiso/build
fi
echo "extract-xiso ready: $(command -v extract-xiso)"
echo "Next: follow WET-CODESPACE.md"
