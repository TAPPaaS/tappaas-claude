---
name: tappaas-issue
description: Investigate, test, and (with approval) implement a fix/feature for one or more TAPPaaS issues. Use whenever the user references a Codeberg issue by number (#NNN), a small explicit set of related issues (#2, #4, #5), or asks to investigate, look into, reproduce, diagnose, or fix a TAPPaaS issue. Handles forge fetch (Codeberg/tea), local-clone code analysis, live-environment testing, root-cause assessment, and a working-branch implementation the operator commits.
---

# TAPPaaS Issue Workflow

Purpose: turn a bare "investigate #NNN" (or "look into / fix #NNN") into the full loop
without the operator re-typing the process each time. Follow the phases in order. Stop and
report at the gate in Phase 4 — do **not** implement before the operator says go.

**One issue or a small explicit set.** The operator may name several related issues at once
("investigate #2, #4 and #5"). Fetching a handful of *explicitly named* numbers is fine — it's
not the list-enumeration the forge rules forbid. Run each phase across the set: fetch each in
Phase 1, then treat them as a group from Phase 2 on — establish how they relate (shared root
cause? one change closes all, or separate fixes?) and decide the branch/commit shape at the
Phase 4 gate. Never expand a named set by pulling the issue list for "related" ones; if you
suspect more are involved, name them to the operator and ask.

The forge and git rules in `CLAUDE.md` are in force throughout: **Codeberg via `tea`, never
`gh`; never `git commit`/`git push` (operator does that); minimize forge load; concise,
human-looking comments.** This skill assumes them; it does not repeat every clause.

---

## Phase 1 — Fetch the issue **and its comments** (one item, not a list)

```bash
tea issues -R origin <N> --comments   # issue detail + full comment thread in one call
```

The `--comments` flag is required — without it `tea` prompts (and returns no comments in a
non-interactive run). If you need the thread on its own, `tea comments -R origin ls <N>`.

Read the whole thread including comments — later comments often revise or refute the original
ask. Note: what is asked, who asked, any proposed fix already sketched, decisions/objections
raised in comments, linked issues/ADRs.

For a set (`#2, #4, #5`), run the fetch once per named number — that's the whole set, don't add
"related" issues by enumerating the list. As you read, capture how they overlap (same file /
module / root cause vs. independent) so Phase 4 can decide one combined fix or separate ones.

## Phase 2 — Locate & understand (local clone first)

Use the on-disk clone for everything already on disk — grep, blame, history, file reads. The
Forgejo API is a last resort, not a search index.

- Find the relevant module/foundation code. Verify module names against the tree
  (`ls src/foundation/`, `src/apps/`) — don't trust stale numbered names from history.
- `git log`/`git blame` the suspect lines; check for a prior fix or regression (search
  `MEMORY.md` pointers too — outages/regressions are often recorded there).
- Form a concrete hypothesis of the root cause before touching the live system.

## Phase 3 — Reach a live environment (to observe real state / test)

Try in this order; stop at the first that answers the question:

1. **Am I already on a mothership?** If `test -d /home/tappaas/TAPPaaS` (i.e. you're in a
   remote VS Codium / ssh session on the cicd), run the toolbox locally — no VPN, no hops.
   The `/home/tappaas/bin/*` tools (`test-module.sh`, `install-module.sh`, `opnsense-controller`,
   `zone-manager`, `dns-manager`, journalctl/systemctl on nodes) are right there.

2. **Otherwise reach a deployment from this dev machine.** Exactly one admin WireGuard tunnel
   is up at a time (`~/bin/tappaas-wg.sh`). Try deployments in order:
   - `~/bin/tappaas-wg.sh hrossen.dk` → probe.
   - else `~/bin/tappaas-wg.sh makerfloss.eu` → probe.
   Check current state first with `tappaas-wg.sh status`; `tappaas-wg.sh down` when finished if
   you brought it up.

3. **Find the mothership on the management plane.** With a tunnel up, the mgmt net is
   `10.0.0.0/24` (OPNsense `10.0.0.1`, Proxmox `10.0.0.<n>:8006`). `ssh root@10.0.0.10` lands
   on a Proxmox node (`tappaas1`); from there locate the cicd VM (`qm list | grep -i cicd`) and
   hop to it as the `tappaas` user. Known mapping: **makerfloss cicd = `10.0.0.209`**.

**Nested-ssh gotcha:** `ssh host 'ssh inner bash -lc "cmd --flag"'` silently drops `--flag`.
Use a `bash -s` heredoc for the inner command instead (see `[[tappaas-remote-ssh-heredoc]]`).

Read-only inspection only in this phase (journalctl, systemctl status, config reads, `test.sh`).
Don't mutate the live system while still diagnosing.

## Phase 4 — Assess the ask, then STOP and ask (gate)

Think hard before writing any code:

- **Is the fix/feature the issue proposes actually the right one?** Or is it a symptom-patch
  where the root cause wants a restructure? Fix root causes, not symptoms.
- Does it fit the architecture (relevant ADRs, module boundaries, `zones.json`, schemas)? Would
  it duplicate or contradict existing tooling?
- What's the smallest change that correctly resolves it?

**Then explain your assessment to the operator and ask any relevant questions — the proposed
approach, trade-offs, restructure-vs-patch, scope — BEFORE implementing.** This gate is
mandatory; the default is investigate-and-report, not silently implement.

## Phase 5 — Implement (only after the operator agrees)

Implement on the machine you're running on (this Mac / dev machine).

- **Create a working branch first** so parallel sessions don't collide:
  `git checkout -b fix/<short-slug>-<N>` (or `feat/…`). Do the work there.
- Match the repo's existing density — no AI boilerplate, over-commenting, or redundant docs.
- Use the shell-script skills (`bash-script-generator` / `bash-script-validator`) for any
  `.sh` work, and the agent team for non-trivial changes (see `CLAUDE.md` routing).
- **Test on a connected system if possible** — via the live env from Phase 3, run the module's
  `test.sh` / `test-module.sh`, or a `nixos-rebuild test` (never `switch` for first activation).
  Propose the test plan before running per the testing rules.
- **Never `git commit` or `git push`.** Stage the change in the working tree and stop.

## Phase 6 — Wrap up

- **If it's a big fix/feature:** draft a concise description of the fix/feat into a file, let the
  operator review, then post it to the issue: `tea comment -R origin <N> "$(cat body.md)"`.
  One human comment, no AI preamble, no diff-restatement.
- **Propose ONE short commit message** for the operator to commit + push — Conventional Commits
  subject (`type(scope): summary`, ≤ ~72 chars), body only for non-obvious *why*. **No
  `Co-Authored-By: Claude` trailer** (Codeberg hygiene). Do not run git yourself.
- Reference the issue in the message (`close #NNN` / `#NNN`) when appropriate.

---

## Guardrails recap

- Codeberg + `tea` for all issue actions; **never `gh`** for mutations.
- **Never** `git commit`/`git push` — operator commits, even on "land it"/"ship it".
- Minimize forge load: one issue by number, no list enumeration, no polling loops, prefer the
  local clone over the API.
- Confirm before destructive live ops (deleting VMs, dropping pools, wiping `/etc/secrets`).
- Only one admin WireGuard tunnel up at a time; tear it down when done.
