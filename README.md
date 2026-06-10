# vyos-container (unofficial)

Multi-arch, ContainerLab-ready container images built from VyOS **Rolling** and
**Stream** ISOs.

> **Unofficial — not affiliated with or endorsed by VyOS / Sentrium S.L.** Built per the
> method documented by ContainerLab (ISO → squashfs → `FROM scratch` image). "VyOS" is a
> trademark of Sentrium S.L.; this project does not redistribute VyOS logo artwork.

## Tags

| Tag | Channel | Arch |
|-----|---------|------|
| `:rolling` / `:rolling-YYYY-MM-DD` | rolling | amd64 (+ arm64 when available) |
| `:stream` / `:stream-YYYY.QQ` | stream | (planned) |

## Pull

```bash
docker pull ghcr.io/angeletdemon/vyos:rolling
```

## How it's built

VyOS ships no native container, so each image is produced by:

1. `build/fetch-rolling-iso.sh` — download the official nightly amd64 ISO.
2. `build/iso-to-rootfs.sh <iso> rootfs.tar` — extract `live/filesystem.squashfs` → `rootfs.tar`.
3. `build/Containerfile` — `FROM scratch` + `rootfs.tar`, mask container-hostile units, `CMD /sbin/init`.
4. `test/assert.sh` — ContainerLab `vyosnetworks/vyos` deploy + config-load gate (hard gate before publish).

## Validate it works

`./validate.sh` spins up a working ContainerLab mini-lab to prove the image is healthy —
two VyOS routers (`bcr`/`fcr`) with a host behind each, **key-only SSH** enforced, static-
routed so the hosts reach each other end-to-end:

```
host-a ──[ bcr ]══transit══[ fcr ]── host-b
```

It asserts (10 checks): both routers boot, config loads, keyed SSH works **and password
SSH is rejected** on each router, and host-a ↔ host-b ping succeeds both ways through both
routers. It then **leaves the lab running** and prints how to log into every node (keyed
SSH to the routers as `admin` and the hosts as `root`, or `podman exec`), plus the teardown
command — so you can explore before tearing down.

```bash
./validate.sh                 # use local image if present, else pull :rolling
CLEAN_PULL=1 ./validate.sh    # logout + wipe local + fresh anonymous pull first
TEARDOWN=1 ./validate.sh      # auto-destroy at the end (CI mode)
IMAGE=quay.io/slashvar/vyos:rolling ./validate.sh   # test a specific registry/tag
```

Requires `podman` + `containerlab`, and an SSH keypair at `~/.ssh/id_ed25519` (override
with `SSH_KEY`/`SSH_PUBKEY`). Hosts default to `localhost/lab-host:latest`; override with
`HOST_IMAGE=` (e.g. a public `docker.io/wbitt/network-multitool:latest` if you don't have a
local host image — note SSH-into-host needs an sshd-enabled image like `lab-host`).

See the design + plan in the TrainingLabs repo (`docs/superpowers/`).
