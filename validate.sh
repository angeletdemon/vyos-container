#!/usr/bin/env bash
# validate.sh — prove the published VyOS container actually works in ContainerLab.
#
# Spins up a working, Module-1-flavoured mini-lab:
#
#     host-a ──eth1── [ bcr (VyOS) ] ──eth2══transit══eth2── [ fcr (VyOS) ] ──eth1── host-b
#            10.10.1.0/24            10.0.0.0/30                10.20.1.0/24
#
# Two VyOS routers (bcr/fcr, like the Module-1 Aristas) with a host behind each,
# static-routed so the hosts reach each other end-to-end (working, not broken).
# Both routers enforce **key-only SSH** (password auth disabled) using your pubkey;
# the hosts also accept your key (root) so you can SSH into every node.
#
# After the checks it LEAVES THE LAB RUNNING and prints how to log into each node
# plus the teardown command — so you can poke around first.
#
# Usage:
#   ./validate.sh                 # use local image if present, else pull
#   CLEAN_PULL=1 ./validate.sh    # logout + wipe local + anonymous pull first
#   TEARDOWN=1 ./validate.sh      # destroy the lab automatically at the end (CI mode)
#   IMAGE=quay.io/slashvar/vyos:rolling ./validate.sh   # test a different registry/tag
set -euo pipefail

# ---- knobs (override via env) -----------------------------------------------
IMAGE="${IMAGE:-ghcr.io/angeletdemon/vyos:rolling}"
HOST_IMAGE="${HOST_IMAGE:-localhost/lab-host:latest}"   # the repo's UBI9 lab host; swap via HOST_IMAGE
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
CLEAN_PULL="${CLEAN_PULL:-0}"
TEARDOWN="${TEARDOWN:-0}"
LABNAME="vyos-validate"
RUNDIR="${RUNDIR:-$HOME/.vyos-validate-lab}"
TOPO="$RUNDIR/topo.clab.yml"
PODMAN="sudo podman"

# ---- helpers ----------------------------------------------------------------
PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
info() { printf '\033[36m[*]\033[0m %s\n' "$1"; }
mgmt_ip() { $PODMAN inspect "$1" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' 2>/dev/null | awk '{print $1}'; }

cleanup() {
  if [ "$TEARDOWN" = "1" ]; then
    info "TEARDOWN=1 — destroying the lab"
    sudo containerlab destroy -t "$TOPO" --runtime podman --cleanup >/dev/null 2>&1 || true
    rm -rf "$RUNDIR"
  fi
}
trap cleanup EXIT

# ---- pre-flight -------------------------------------------------------------
command -v containerlab >/dev/null || { echo "containerlab not found"; exit 1; }
command -v podman >/dev/null || { echo "podman not found"; exit 1; }
[ -f "$SSH_PUBKEY" ] || { echo "ssh pubkey not found: $SSH_PUBKEY"; exit 1; }
[ -f "$SSH_KEY" ]    || { echo "ssh private key not found: $SSH_KEY"; exit 1; }
PUBKEY_TYPE="$(awk '{print $1}' "$SSH_PUBKEY")"
PUBKEY_DATA="$(awk '{print $2}' "$SSH_PUBKEY")"
[ -n "$PUBKEY_DATA" ] || { echo "could not parse pubkey data from $SSH_PUBKEY"; exit 1; }

# ---- image -----------------------------------------------------------------
if [ "$CLEAN_PULL" = "1" ]; then
  info "CLEAN_PULL=1 — anonymous fresh pull of $IMAGE"
  $PODMAN logout "${IMAGE%%/*}" >/dev/null 2>&1 || true
  $PODMAN rmi -f "$IMAGE" >/dev/null 2>&1 || true
fi
info "ensuring images are present"
$PODMAN image exists "$IMAGE" || $PODMAN pull "$IMAGE"
$PODMAN image exists "$HOST_IMAGE" || { echo "host image missing: $HOST_IMAGE (build it or set HOST_IMAGE=)"; exit 1; }

# ---- lab dir + host authorized_keys (lets you SSH root@host too) ------------
mkdir -p "$RUNDIR"
install -m 0644 "$SSH_PUBKEY" "$RUNDIR/authorized_keys"

# ---- generate VyOS router configs (partial config.boot; clab merges mgmt eth0 + its own key) ----
gen_router() {  # name eth1cidr eth2cidr route_dest route_nexthop outfile
  local name="$1" e1="$2" e2="$3" rdest="$4" rnh="$5" out="$6"
  cat > "$out" <<EOF
interfaces {
    ethernet eth1 {
        address "$e1"
    }
    ethernet eth2 {
        address "$e2"
    }
}
protocols {
    static {
        route $rdest {
            next-hop $rnh {
            }
        }
    }
}
service {
    ssh {
        disable-password-authentication
    }
}
system {
    host-name "$name"
    login {
        user admin {
            authentication {
                public-keys labkey {
                    key "$PUBKEY_DATA"
                    type "$PUBKEY_TYPE"
                }
            }
        }
    }
}
EOF
}
gen_router bcr "10.10.1.1/24" "10.0.0.1/30" "10.20.1.0/24" "10.0.0.2" "$RUNDIR/bcr.config.boot"
gen_router fcr "10.20.1.1/24" "10.0.0.2/30" "10.10.1.0/24" "10.0.0.1" "$RUNDIR/fcr.config.boot"

# ---- topology --------------------------------------------------------------
cat > "$TOPO" <<EOF
name: $LABNAME
topology:
  nodes:
    bcr:
      kind: vyosnetworks_vyos
      image: $IMAGE
      startup-config: bcr.config.boot
    fcr:
      kind: vyosnetworks_vyos
      image: $IMAGE
      startup-config: fcr.config.boot
    host-a:
      kind: linux
      image: $HOST_IMAGE
      binds: [ "authorized_keys:/root/.ssh/authorized_keys:ro" ]
      exec:
        - ip addr add 10.10.1.10/24 dev eth1
        - ip route add default via 10.10.1.1
    host-b:
      kind: linux
      image: $HOST_IMAGE
      binds: [ "authorized_keys:/root/.ssh/authorized_keys:ro" ]
      exec:
        - ip addr add 10.20.1.10/24 dev eth1
        - ip route add default via 10.20.1.1
  links:
    - endpoints: ["host-a:eth1", "bcr:eth1"]
    - endpoints: ["bcr:eth2", "fcr:eth2"]
    - endpoints: ["fcr:eth1", "host-b:eth1"]
EOF

# ---- deploy ----------------------------------------------------------------
info "deploying $LABNAME (image: $IMAGE)"
( cd "$RUNDIR" && sudo containerlab deploy -t "$TOPO" --runtime podman --reconfigure )

N_BCR="clab-${LABNAME}-bcr"; N_FCR="clab-${LABNAME}-fcr"
N_HA="clab-${LABNAME}-host-a"; N_HB="clab-${LABNAME}-host-b"

wait_running() {  # container -> 0 when systemd is (degraded|running)
  local c="$1" s
  for _ in $(seq 1 30); do
    s="$($PODMAN exec "$c" systemctl is-system-running 2>/dev/null || true)"
    [ "$s" = running ] || [ "$s" = degraded ] && return 0
    sleep 4
  done
  return 1
}

echo; info "=== TESTS ==="

# routers boot
wait_running "$N_BCR" && ok "bcr: VyOS booted (systemd running)" || bad "bcr did not reach running"
wait_running "$N_FCR" && ok "fcr: VyOS booted (systemd running)" || bad "fcr did not reach running"

# config loaded
$PODMAN exec "$N_BCR" vbash -ic "show configuration commands" 2>/dev/null | grep -q "eth1 address '10.10.1.1/24'" \
  && ok "bcr: startup-config loaded (eth1 10.10.1.1/24)" || bad "bcr: expected interface config missing"
$PODMAN exec "$N_FCR" vbash -ic "show configuration commands" 2>/dev/null | grep -q "eth1 address '10.20.1.1/24'" \
  && ok "fcr: startup-config loaded (eth1 10.20.1.1/24)" || bad "fcr: expected interface config missing"

# SSH: keyed auth works + password rejected, on BOTH routers.
# NB: op-mode commands (show ...) need an interactive shell, so the auth probe runs 'echo'.
SSH_BASE=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes)
sleep 5
test_ssh() {  # label container
  local name="$1" c="$2" ip; ip="$(mgmt_ip "$c")"
  if ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${SSH_BASE[@]}" "admin@${ip}" 'echo VYOS_SSH_OK' 2>/dev/null | grep -q VYOS_SSH_OK; then
    ok "$name: keyed SSH login works (key-only, $ip)"
  else
    bad "$name: keyed SSH login failed ($ip)"
  fi
  if ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no "${SSH_BASE[@]}" "admin@${ip}" true 2>/dev/null; then
    bad "$name: password SSH ACCEPTED (key-only NOT enforced)"
  else
    ok "$name: password SSH rejected (key-only enforced)"
  fi
}
test_ssh bcr "$N_BCR"
test_ssh fcr "$N_FCR"

# data plane: host-a <-> host-b through both routers
$PODMAN exec "$N_HA" ping -c 2 -W 2 10.20.1.10 >/dev/null 2>&1 \
  && ok "host-a -> host-b (10.20.1.10) ping OK through bcr+fcr" || bad "host-a -> host-b ping failed"
$PODMAN exec "$N_HB" ping -c 2 -W 2 10.10.1.10 >/dev/null 2>&1 \
  && ok "host-b -> host-a (10.10.1.10) ping OK (return path)" || bad "host-b -> host-a ping failed"

# ---- summary ---------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m=== ALL %d CHECKS PASSED — the published VyOS image works in ContainerLab ===\033[0m\n' "$PASS"
else
  printf '\033[31m=== %d passed, %d FAILED ===\033[0m\n' "$PASS" "$FAIL"
fi

# ---- explore (lab left running) --------------------------------------------
if [ "$TEARDOWN" != "1" ]; then
  echo
  info "Lab is LEFT RUNNING — log into each node and look around:"
  printf '    %-7s VyOS router  ssh -i %s admin@%s   |  sudo podman exec -it %s su - admin\n' "bcr"    "$SSH_KEY" "$(mgmt_ip "$N_BCR")" "$N_BCR"
  printf '    %-7s VyOS router  ssh -i %s admin@%s   |  sudo podman exec -it %s su - admin\n' "fcr"    "$SSH_KEY" "$(mgmt_ip "$N_FCR")" "$N_FCR"
  printf '    %-7s linux host   ssh -i %s root@%s    |  sudo podman exec -it %s bash\n'        "host-a" "$SSH_KEY" "$(mgmt_ip "$N_HA")"  "$N_HA"
  printf '    %-7s linux host   ssh -i %s root@%s    |  sudo podman exec -it %s bash\n'        "host-b" "$SSH_KEY" "$(mgmt_ip "$N_HB")"  "$N_HB"
  echo
  info "Try inside a router:  show interfaces  |  show ip route  |  ping 10.20.1.10"
  info "Tear down when you're done:"
  printf '    \033[33msudo containerlab destroy -t %s --runtime podman --cleanup\033[0m\n' "$TOPO"
  echo  "    (or re-run with TEARDOWN=1 ./validate.sh to auto-destroy)"
fi

[ "$FAIL" -eq 0 ]
