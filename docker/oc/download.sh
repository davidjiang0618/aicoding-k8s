#!/bin/bash

# Pre-download OpenCode binary to avoid network issues during docker build
# Run this script before building the image:
#   ./download.sh                    Download latest version for current architecture
#   OC_VERSION=1.15.0 ./download.sh  Download specific version
#
# The binary is saved to bin/opencode (git-ignored)

cd "$(dirname "$0")"

# Auto-detect latest version from GitHub Releases if not specified
if [ -z "$OC_VERSION" ]; then
  LATEST_URL=$(curl -sI -L -o /dev/null -w '%{url_effective}' \
    https://github.com/anomalyco/opencode/releases/latest 2>/dev/null)
  OC_VERSION=$(echo "$LATEST_URL" | sed 's|.*/v||')
  if [ -z "$OC_VERSION" ]; then
    echo "ERROR: Could not detect latest version. Set manually: OC_VERSION=1.15.0 ./download.sh"
    exit 1
  fi
fi

# Detect target architecture based on host platform
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  TARGET="linux-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  TARGET="linux-x64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

FILENAME="opencode-${TARGET}.tar.gz"
URL="https://github.com/anomalyco/opencode/releases/download/v${OC_VERSION}/${FILENAME}"

mkdir -p bin

echo "Downloading opencode v${OC_VERSION} for ${TARGET} ..."

curl --connect-timeout 60 --max-time 600 --retry 5 --retry-delay 10 \
  -L -o bin/opencode.tar.gz "$URL"

if [ $? -ne 0 ]; then
  echo "Download failed. Please retry or download manually:"
  echo "  $URL"
  echo "  Extract and place the binary at docker/oc/bin/opencode"
  rm -f bin/opencode.tar.gz
  exit 1
fi

tar -xzf bin/opencode.tar.gz -C bin
rm bin/opencode.tar.gz
chmod +x bin/opencode

echo "Downloaded opencode v${OC_VERSION} (${TARGET}) to bin/opencode"
echo "Now run: ./build.sh"
