# TAPPaaS sites used for development and testing

Public structure only. Addresses, access paths and site quirks are in
`SITES.local.md` (gitignored, copied to each dev machine by hand).

| Site | Role | Branch | Claude may |
|------|------|--------|-----------|
| hrossen.dk | **Test site**: first to get every change | wave branches, else `main` | run all tests; apply R≤3 changes; set/release a pull hold. R4 migrations and destructive steps ask |
| makerfloss | **Canary** | `main` | read and run fast tests; `--deep` only when asked (`--allow-canary-deep`) |

Access from a dev machine: ssh aliases `cicd-hrossen` and `cicd-makerfloss` (see
`SITES.local.md` for the `~/.ssh/config` block; both pin their host key with
`HostKeyAlias`, because both sites use the same management subnet). makerfloss needs
its WireGuard tunnel: `~/bin/tappaas-wg.sh makerfloss.eu`.

Codeberg: `tea` is logged in on the operator's Mac and on hrossen.dk only.
