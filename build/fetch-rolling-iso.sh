#!/usr/bin/env bash
# Download the latest official rolling amd64 ISO from the VyOS nightly builds.
# Prints the downloaded ISO path on stdout. Requires: gh, curl.
set -euo pipefail
DEST="${1:-.}"
mkdir -p "$DEST"

read -r TAG ISO_URL < <(gh api repos/vyos/vyos-rolling-nightly-builds/releases/latest \
  --jq '.tag_name + " " + (.assets[] | select(.name|endswith("-generic-amd64.iso")) | .browser_download_url)')

echo "[*] latest rolling: $TAG" >&2
iso="$DEST/$(basename "$ISO_URL")"
curl -fL --retry 3 "$ISO_URL" -o "$iso"
# minisig is published alongside; fetch for provenance (verification optional until pubkey pinned)
curl -fsSL "${ISO_URL}.minisig" -o "${iso}.minisig" || echo "[!] no minisig" >&2
echo "$iso"
