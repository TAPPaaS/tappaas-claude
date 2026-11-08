# makerfloss — unreachable from 2026-09-27, last contact 2026-09-26 ~08:30 CEST

Written 2026-09-27 for the on-site visit planned Monday 2026-09-28+. Everything below
is what the site was known to be, or was changed to, before contact was lost — so the
debugging does not start by re-deriving it.

## Reachability, measured 2026-09-27 ~10:40

| path | result |
|---|---|
| `ping 10.0.0.209` (mothership, over the wg tunnel) | 100% loss |
| `ssh cicd-makerfloss` | connect timeout |
| wg tunnel `tappaas-mf` | interface `utun4` UP, `inet 10.255.1.2`, route to 10.0.0.209 via it |
| `ping 10.255.1.1` (the tunnel PEER) | **no reply** — so the session is not passing traffic, not merely the hosts behind it |
| `makerfloss.eu` (88.99.32.236) | tcp/443 accepts SYN, **no TLS handshake**, HTTP 000 |
| `logging.makerfloss.eu`, `cicd.makerfloss.eu` (37.27.5.237) | same — SYN only, **no TLS handshake**, HTTP 000 |

Two things worth carrying into the debugging:

- `nc -z` reported "443 open" on both addresses and that was **misleading** — only a
  SYN/ACK, which an upstream firewall or a half-open state produces. `openssl s_client`
  completed no handshake on either. Do not treat an open port here as a live service.
- 37.27.5.237 is **not** the mothership — it is the off-site satellite (its host key
  differs from 10.0.0.209; noted previously when ssh instructions confused the two). So
  the off-site addresses failing too means this is **broader than the on-site mothership**:
  either the satellite is down as well, or something upstream (site WAN / hosting) is, or
  those DNS records no longer point at makerfloss machines. Not distinguishable from here.
- `~/bin/tappaas-wg.sh status` is not a connectivity signal: it reported `UP: tappaas-mf`
  while nothing passed, and `down: tappaas-hrossen` while hrossen was in continuous use.
  On site, check `sudo wg show tappaas-mf` and read **`latest handshake`**.

## What was changed on the site on 2026-09-26 (so it is not mistaken for stock)

All of it was done by hand from the Mac, and the site's checkout does **not** contain the
corresponding code — it tracks `staging` at `83ccb498`, and these fixes are on `main`.
This is the ADR-028 D12 "deployed ahead of declared" state, deliberately and knowingly.

1. **Grafana repaired.** It had crash-looped since 2026-09-25 02:09 because `/etc/secrets`
   was `0700 root:grafana` and grafana cannot traverse that. `module-manager module update
   logging` fixed it: the guest moved 25.11 -> 26.05 (staged + rebooted at 07:53), mode is
   now `0750 root:grafana`, grafana active and listening on :3000, module tests passed.
2. **Mothership config backup made to work for the first time.** `/etc/secrets/backup-fs.key`
   was absent, so `tappaas-fs-backup.service` had failed on **every** run since 2026-09-15 —
   zero successes in ten days. Created and escrowed keys for `tappaas-cicd`, and escrowed
   the pre-existing keys of `tappaas1/2/3`, which had **none** centrally (each guest held the
   only copy). Guest keys were left byte-identical; nothing was rotated.
3. **Three dangling symlinks removed** under `config/` (`module-fields.json` -> a
   pre-`schemas/` path, target deleted by `c3ea80b8`). They made the capture refuse
   entirely. Removing them means the capture passes with the **old** runner too, which is
   why the site is safe even though its checkout still has the unfixed code.
4. **Runner + `pbs-fs.sh` hand-deployed** from `/tmp`. The next control-plane refresh will
   relink `~/bin` from the checkout and revert them — harmless now, because of (3).

Two PBS snapshots existed afterwards: `host/tappaas-cicd/2026-09-26T06:08:18Z` and
`…T06:29:56Z`, 1.492 MiB each, containing `home-tappaas-config.pxar` and `etc-secrets.pxar`.

## Outstanding on the site, from before the outage

- **Four escrowed keys need their mandatory out-of-band copies** (`backup-manager key
  export <dest>`, ADR-012 §2.5.1). The escrow lives inside the system a full-site rebuild
  recreates, so this is the copy that survives a disaster. Not done.
- **#749 status unknown.** Installing `backup` on a PVE node used to delete that node's PVE
  apt repository (missing deb822 stanza separator). The test site's PBS node was affected and
  was 32 packages behind on PVE, security updates included. makerfloss runs PBS on a node, so
  it is likely affected. Check on site:
  `awk 'NR>1 && /^Types:/ && prev != "" {f=1} {prev=$0} END {exit !f}' /etc/apt/sources.list.d/proxmox.sources`
  and `apt-cache policy pve-manager` — a `100 /var/lib/dpkg/status` line with no repository
  line is the signature. The fix and an idempotent repair are on `main`; the site gets them
  at the next promotion, or sooner via the D12 path.
- **The 2026-09-26 sweep never ran to completion** (#744): the mothership took the
  25.11 -> 26.05 release move at 02:04, rebooted to take it, and the sweep ended at phase 0
  with no result written and the timer reset to 09-27. So `last-update-result.json` on the
  site is from **2026-09-25** and reads `ok: true` — it is a day older than it looks, and no
  module was updated on the 26th.
- Its mothership was last seen healthy on 26.05.20260924.c508844, 0 failed units.

## Suggested order on site

1. Console on the mothership before touching the network — the wg peer not answering is
   consistent with the mothership being down, the firewall being down, or the WAN.
2. `sudo wg show` on both ends; read `latest handshake`.
3. Once up: check #749 (above), then `module-manager module update logging` and
   `backup` to bring the hand-deployed pieces back under the checkout.
4. Export the four keys out-of-band.
