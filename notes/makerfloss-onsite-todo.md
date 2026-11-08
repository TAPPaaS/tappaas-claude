# makerfloss — open on-site items (updated 2026-10-20)

Items that need someone physically at makerfloss. Untracked file; keep addresses out
(tappaas-claude is public).

## 1. BIOS: power on after power loss — tappaas2 and tappaas3

There is no UPS. On 2026-10-03 all three nodes lost power and stayed off until someone
switched them on on 2026-10-05 (journal boot history). tappaas1 is set to Power On
(2026-10-20) and tappaas3 too (2026-11-02). Still to do, needs a monitor and keyboard:

| Node | Board | Now | Where |
|---|---|---|---|
| tappaas2 | HP EliteDesk 800 G4 | Power Off (read via hp-bioscfg) | F10 at boot → Advanced → Power-On Options → After Power Loss = Power On. The write from Linux failed, so the BIOS probably has a setup password |

For the record, tappaas3 (ASRock B550M): Advanced, Chipset Configuration or Onboard Devices
Configuration, Restore On AC/Power Loss.

tappaas2 runs no guests. Take it down between backups: the nightly VM backup is 21:00,
file captures 20:08–20:40; tappaas3 is the PBS server. Verify tappaas2 afterwards with
`cat "/sys/class/firmware-attributes/hp-bioscfg/attributes/After Power Loss/current_value"`.

## 2. WAN cabling — done 2026-10-20

A dedicated unmanaged switch carries the upstream segment to all three nodes' `wan`
bridges (tappaas1 nic1, tappaas2 nic0, tappaas3 nic0), each 1 Gb/s. Keep it isolated
from the LAN switch (crs310-maker). Firewall HA: tappaas1 primary, tappaas2 fallback
(tappaas2 has tanka1; tappaas3 has no tanka1 pool, so it cannot be an HA target).
Config change prepared (dependsOn + cluster:ha, HANode tappaas2), run after the #762
test. 2.3's haCpu default will want a firewall restart (deferred, operator picks time).

## 2b. Firewall HA: tappaas1 primary, tappaas2 fallback (next visit)

Not done 2026-10-20 (operator had to leave). The released network module declares
`cluster:ha`, but makerfloss's installed `config/network.json` lacks it: the firewall VM
(110) has a replication job to tappaas2 but no HA resource. tappaas2 has the `tanka1` pool
and a 1 Gb/s WAN link. On tappaas-cicd, not while another test touches the firewall:

    cd ~/config && cp -p network.json ~/network.json.pre-ha && jq '.dependsOn |= (if index("cluster:ha") then . else .[0:1] + ["cluster:ha"] + .[1:] end) | .config["cluster:ha"].HANode = "tappaas2"' network.json > /tmp/n.json && mv /tmp/n.json network.json && chmod 600 network.json && jq -c '{dependsOn, ha: .config["cluster:ha"]}' network.json
    module-manager module update network

Then check: `ha-manager status` lists vm:110 started on tappaas1, `/etc/pve/ha/rules.cfg`
has a node-affinity rule tappaas1:2,tappaas2:1, `pvesr list` keeps 110-0 → tappaas2, and
the WAN, satellite tunnel and relay still work. Optional proof: `ha-manager crm-command
relocate vm:110 tappaas2` and back, in a quiet window (stop-and-start, brief outage).
Release 2.3 adds `haCpu` (default common): it will want a firewall restart, reported as
DEFERRED; run `module-manager module update network --allow-disruption` at a chosen time.

## 3. Memory overcommit on tappaas1 (remote, but caused by item 2)

Every guest runs on tappaas1: 33.0 of 31.2 GB committed (106%, health gate FAIL), while
tappaas2 (23.3 GB) and tappaas3 (15.5 GB) run nothing. HA guests are tappaas-cicd (130)
and identity (140), replicated to tappaas2. Moving them, logging and the lab guests off
tappaas1 fixes the gate; the network VM must stay until item 2 is done.
Rule: reboot tappaas1, never shut it down — the conditional HA policy moves 130/140 on
a shutdown.

## Done on 2026-10-20

- Two USB key sticks written (5 keys), to be kept at two other sites.
- satellite1 converted to a managed module (#775; nightly-sweep check pending).
- tappaas1/2 PVE repository repaired (#749 gap); code fix on main d9bf0cf4.
- tappaas1 BIOS Power On.
