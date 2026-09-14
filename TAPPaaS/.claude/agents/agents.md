# TAPPaaS subagents

Native Claude Code subagents (frontmatter in each `tappaas-*.md`). Call them by type with the
Agent tool; there is no template to paste. Use one where it keeps long output or a second
viewpoint out of the main session. Code is usually written in the main session.

| Agent | Use for | Model |
|-------|---------|-------|
| `tappaas-site-operator` | Commands on hrossen / makerfloss; returns a summary | sonnet |
| `tappaas-upgrade-tester` | T3: a pushed branch through real updates on hrossen, then back to main | sonnet |
| `tappaas-tester` | test.sh / test-service.sh / deep-tier regression cases, and running them | sonnet |
| `tappaas-security` | Review of firewall, exposure, secrets, ssh, container changes (read-only) | session |
| `tappaas-network` | Zones, rules, DNS, DHCP, Caddy, opnsense-controller, network-manager | session |
| `tappaas-nix-dev` | NixOS modules and the shared baseline | session |
| `tappaas-adr-reviewer` | ADR review, wave entry gates, amendment drafts | session |

Typical combinations:
- **A fix:** main session implements → `tappaas-tester` adds the case that would have caught it →
  `tappaas-security` if it touches exposure, secrets or ssh.
- **A wave group:** `tappaas-adr-reviewer` checks the entry gate → main session implements →
  `tappaas-upgrade-tester` proves it on hrossen.
- **Live diagnosis:** `tappaas-site-operator` gathers evidence; the main session decides.

Shell and Python conventions are in the `bash-script-*` skills and the code itself; project
management is the built-in Plan agent. A `migration-author` agent follows once the migration
framework (#652) exists.

> The `agent-*.md` files next to this one are the old prompt templates (retired 2026-09-14,
> stale paths). They stay only until sessions started before that date have finished, then
> they are deleted. Do not use them.
