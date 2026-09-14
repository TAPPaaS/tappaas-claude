---
name: tappaas-issue
description: Investigate, test, and (with approval) implement a fix/feature for one or more TAPPaaS issues. Use whenever the user references a Codeberg issue by number (#NNN), a small explicit set of related issues (#2, #4, #5), or asks to investigate, look into, reproduce, diagnose, or fix a TAPPaaS issue. Handles forge fetch (Codeberg/tea), local-clone code analysis, live-environment testing, root-cause assessment, and a working-branch implementation committed locally for the operator to push.
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
`gh`; commit locally, never push (see "Git Policy"; hooks enforce it); minimize forge load;
concise, human-looking comments.** This skill assumes them; it does not repeat every clause.

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

2. **Otherwise reach a site from this dev machine.** Addresses and access paths are in
   `~/src/tappaas-claude/SITES.local.md` (local only). Try in order:
   - **hrossen.dk** — the test site; its cicd is reachable over ssh without a tunnel.
   - **makerfloss** — the canary; needs its WireGuard tunnel (`~/bin/tappaas-wg.sh makerfloss.eu`,
     one tunnel at a time) and is **read-only** unless the operator asks.
   `tappaas-wg.sh status` first; `tappaas-wg.sh down` when finished if you brought one up.

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
- **Regression guard — carefully consider a `--deep` `test.sh` extension.** For any real
  fix/feature, weigh adding a case that would have *caught this issue* to the module's `test.sh`,
  behind the deep-test gate (`TAPPAAS_TEST_DEEP=1` / `--deep`, so it runs in the full regression
  sweep, not every fast run). Prefer a coded test over manual verification (per `CLAUDE.md`
  testing rules); if you decide against one, say why. Propose the test plan before running it.
- **Test on a connected system if possible** — via the live env from Phase 3, run the module's
  `test.sh` / `test-module.sh` (with `--deep` when you added a deep case), or a
  `nixos-rebuild test` (never `switch` for first activation).
- **Consider documentation.** Ask whether the change makes any `README.md`, `DESIGN.md`,
  `INSTALL.md`, `DEVELOP.md`, ADR, or schema/field doc stale or incomplete — new flag, changed
  behaviour, new field/value, moved file. Update the docs that genuinely drifted (match the
  repo's density — no boilerplate), or note explicitly that none needed it.
- **Commit on the working branch** (one commit per logical change; the `commit-msg` hook
  checks the message). **Never push.**

## Phase 6 — Wrap up

- **If it's a big fix/feature:** draft a concise description of the fix/feat into a file, let the
  operator review, then post it to the issue: `tea comment -R origin <N> "$(cat body.md)"`.
  One human comment, no AI preamble, no diff-restatement.
- **Leave clean local history**: squash your unpushed commits to one per logical change,
  `type(scope): summary` ≤ 72 chars, body only for a non-obvious *why*, `close #NNN` where
  it closes the issue. When asked to land it, merge into local `main`.
- **Report** the branch and commits that are ready; the operator pushes.

---

## Guardrails recap

- Codeberg + `tea` for all issue actions; **never `gh`** for mutations.
- Commit locally, **never push** — "land it"/"ship it" means merge into local `main` and report.
- Minimize forge load: one issue by number, no list enumeration, no polling loops, prefer the
  local clone over the API.
- Confirm before destructive live ops (deleting VMs, dropping pools, wiping `/etc/secrets`).
- Only one admin WireGuard tunnel up at a time; tear it down when done.
- hrossen.dk is the test site; makerfloss is read-only unless the operator asks.
