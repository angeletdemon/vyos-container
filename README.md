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

See the design + plan in the TrainingLabs repo (`docs/superpowers/`).
