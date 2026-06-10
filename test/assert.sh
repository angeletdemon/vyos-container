#!/usr/bin/env bash
# Deploy the smoke topology, assert VyOS boots healthy and the injected config loaded.
# Runtime-agnostic: uses podman if present (sudo), else docker.
# Image under test: $IMAGE (default localhost/vyos:rolling-test).
set -euo pipefail
cd "$(dirname "$0")"
export IMAGE="${IMAGE:-localhost/vyos:rolling-test}"
TOPO=smoke.clab.yml
NODE=clab-vyos-smoke-r1

if command -v podman >/dev/null; then EXEC="sudo podman exec"; else EXEC="docker exec"; fi

cleanup() { sudo containerlab destroy -t "$TOPO" --cleanup >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "[*] deploy ($IMAGE)"
sudo -E containerlab deploy -t "$TOPO" --reconfigure

echo "[*] wait for system-running (up to 120s)"
state=""
for _ in $(seq 1 24); do
  state="$($EXEC "$NODE" systemctl is-system-running 2>/dev/null || true)"
  { [ "$state" = "running" ] || [ "$state" = "degraded" ]; } && break
  sleep 5
done
echo "    state=$state"
{ [ "$state" = "running" ] || [ "$state" = "degraded" ]; } || { echo "FAIL: not healthy"; exit 1; }

echo "[*] assert injected config loaded (marker host-name vyos-smoketest)"
if $EXEC "$NODE" su - admin -c "show configuration commands" 2>/dev/null | grep -q "vyos-smoketest"; then
  echo "PASS: startup-config applied"
else
  echo "FAIL: marker not found"; exit 1
fi

echo "ALL PASS"
