#!/usr/bin/env bash
# Extract the VyOS root filesystem from an ISO into rootfs.tar.
# Usage: iso-to-rootfs.sh <path-to-iso> <output-rootfs.tar>
set -euo pipefail

ISO="${1:?usage: iso-to-rootfs.sh <iso> <out.tar>}"
OUT="${2:?usage: iso-to-rootfs.sh <iso> <out.tar>}"

for tool in bsdtar sqfs2tar; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: missing $tool. Install: apt-get install -y squashfs-tools-ng libarchive-tools" >&2
    exit 1
  }
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "[*] extracting squashfs from $ISO"
bsdtar -C "$workdir" -xf "$ISO" live/filesystem.squashfs

echo "[*] converting squashfs -> $OUT"
sqfs2tar "$workdir/live/filesystem.squashfs" > "$OUT"

echo "[*] done: $(du -h "$OUT" | cut -f1) $OUT"
