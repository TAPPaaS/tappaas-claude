---
name: tappaas-wave
description: Drives one group of the TAPPaaS 2.1 implementation plan (e.g. "G0.2", "wave 0 group 3") end to end — entry-gate check, one branch, every issue in the group implemented and tested, the group proven on the test site, landed in local main, issues and plan updated. Use when the operator names a wave or group from docs/design/release-2.1-implementation-plan.md, or asks to continue one.
---

# Running a wave group

The plan is `docs/design/release-2.1-implementation-plan.md`: groups in §3–§7, the test level
per upgrade risk in §10.1, the branch → `main` → `stable` rules in §10.2, entry/exit gates in
§10.3. The per-issue method is the `tappaas-issue` skill; testing is the `tappaas-test` skill.
This skill strings them together for a whole group with as few stops as possible.

## 0. Self-check (always, first)

- `pwd` must be the TAPPaaS checkout or one of its worktrees.
- Run `git push --dry-run` there. **It must be refused** with a "tappaas guard" message. If it
  runs, the guardrail hooks are not active in this session: stop and tell the operator to open
  the session in `~/src/TAPPaaS` (folder picker) or to register the user-level guard
  (`~/src/tappaas-claude/README.md`, "User-level guard").

## 1. Entry gate

Read the group's table and its row in §10.3. Check every item: decisions in §11, ADR status
lines in `docs/ADR/`, prerequisite waves on `stable`. Delegate to `tappaas-adr-reviewer` when
an ADR has to be read against the code. **Unmet gate → report exactly what is missing and stop.**

## 2. Branch

`waveN/gX.Y-<slug>` from an up-to-date `main` (`git pull --ff-only` first), or continue the
existing branch for this group. A worktree under `.claude/worktrees/` if another session is
using the main checkout.

## 3. Issues, in the plan's order

For each issue in the group table:
1. **Read it**: the snapshot (`~/src/tappaas-claude/snapshots/backlog.json`, refresh with
   `scripts/forge-snapshot.py`) or `tea issues -R origin <N> --comments` for that one number.
   Skip issues already closed; say so in the report.
2. **Investigate** (tappaas-issue phases 2–3): root cause in the local clone, read-only live
   evidence via `tappaas-site-operator`.
3. **No per-issue gate** — the group's entry gate was the decision. Stop and ask
   (AskUserQuestion, all open points in one question set) only when:
   - the right fix differs from what the issue/plan says, or needs a design choice the gate
     did not settle;
   - **scope grows**: the same bug elsewhere, or a restructure. Offer "this issue only" versus
     "all occurrences" with the blast radius of each.
4. **Implement** in the main session; one commit per logical change, `close #N` on the commit
   that closes it. `tappaas-tester` adds the regression case and proves it fails without the
   fix. `tappaas-security` reviews anything touching exposure, secrets, ssh or firewall rules
   (mandatory in Wave 2). `tappaas-network` / `tappaas-nix-dev` for their domains.
5. **Test** to the issue's level (§10.1): T0–T2 with `tappaas-test.sh hrossen …`.
6. **Related bugs found on the way:** same area and risk class → fix on this branch as a
   separate commit and say so; anything else → queue it as a task (spawn_task) and list it.
7. Draft one short comment per issue in `~/src/tappaas-claude/outbox/<N>.md` (what changed, how
   it was tested — no preamble).

**Data-safety fast lane** (§10.2 rule 4, e.g. #602): once that issue alone is green on
hrossen, propose landing it ahead of the rest of the group.

## 4. Group gate on the test site (T3)

Needed when the group's highest risk is R3 or more, or the change alters code the scheduled
sweep runs. The branch must be on Codeberg: ask the operator to push it
(`git -C ~/src/TAPPaaS push origin <branch>`) — until the pull hold (#653) exists.

Hand it to `tappaas-upgrade-tester` (branch, touched modules, risk level). It updates only the
touched modules. **A full `site-manager update` reboots hrossen's nodes and live-migrates the
cicd** — the operator's ssh sessions freeze while it runs: announce it before starting, run it
detached, and never promise "no reboot". Never `--force` (overrides every `rebootOk`, #633).
R4 migrations and anything destructive: ask first.

## 5. Land

All green → fast-forward local `main` to the branch (or merge), then report and ask the
operator to push `main`. **Switch hrossen back to `main` only after that push**, otherwise it
falls back to the old code. makerfloss picks the change up on its next scheduled sweep (T4):
note that its `~/config/last-update-result.json` should be read after that run.

## 6. Bookkeeping

- Under the group heading in the plan, add one line: `Status: landed YYYY-MM-DD — <commits>`
  (or `in progress` with what remains). Commit it with the group.
- Offer to post the outbox comments (`tea comment`, one approval each). Issues with `close #N`
  close when the operator pushes.

## Stop only for

An unmet gate · a scope or design decision · a test that cannot be made green without
changing the design · R4 migrations, anything destructive, or a change on makerfloss · pushes
(always the operator's). Everything else — investigation, code, tests on hrossen, commits,
merging into local `main` — runs without asking.

## Final report

A table per issue: done / skipped (why) / blocked (why), commits, tests (level reached, pass),
then: branch and `main` state, what the operator must do (push, post comments), queued tasks,
and the T4 check that is due.
