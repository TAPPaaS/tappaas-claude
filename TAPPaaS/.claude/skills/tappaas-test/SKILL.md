---
name: tappaas-test
description: How to test a TAPPaaS change — the test ladder (local lint → site scratch copy → read-only deep tests → test-site deploy → canary soak → release candidate), the tappaas-test.sh runner that ships the working tree to a site's cicd, and which site may be changed. Use whenever a TAPPaaS change needs testing, a test.sh must be run, or someone asks whether something works on a live system.
---

# Testing TAPPaaS changes

The Mac has no nix, node or tsc: anything beyond lint runs on a site's cicd. Sites and
their roles are in `~/src/tappaas-claude/SITES.md` (public) and `SITES.local.md` (addresses).

- **hrossen.dk — test site.** All tests; R≤3 changes without asking.
- **makerfloss — canary.** Stays on `main`. Fast tests only unless the operator asks.

Run tests without asking (CLAUDE.md "Testing Requirements"). Add a deep-tier case that
would have caught the issue whenever you fix one.

## The ladder

Climb only as far as the change's upgrade risk needs (plan §10.1 in
`docs/design/release-2.1-implementation-plan.md`).

| Step | Where | How |
|------|-------|-----|
| T0 | Mac | `bash -n`, `python3 -m py_compile`, `jq -e .` on changed files. shellcheck is not on the Mac: pipe the file to `ssh cicd-hrossen 'cat > /tmp/x.sh && shellcheck /tmp/x.sh; rm /tmp/x.sh'` |
| T1 | scratch copy on hrossen | `tappaas-test.sh hrossen <component-path>...` — fast tiers of the working tree, unpushed work included |
| T2 | hrossen, read-only live | `tappaas-test.sh hrossen --deep <component-path>`, `tappaas-test.sh hrossen module:<name>`, reconcile dry-runs |
| T3 | hrossen, deployed | the change runs through a real sweep: a pushed branch (`site-manager repository modify TAPPaaS --branch <b>`) or, once plan G0.3 lands, unpushed work under a pull hold. Back to `main` afterwards |
| T4 | makerfloss | after the operator pushes to `main`: next scheduled sweep, `~/config/last-update-result.json` |
| T5 | blank install | release candidates only (`release/README.md`) — operator-driven |

## The runner

```bash
~/src/tappaas-claude/scripts/tappaas-test.sh <site> [--deep] [--no-sync] [--repo DIR] <target>...
#   target = repo path with a test.sh  -> run from ~/dev/scratch/<branch> on the site
#   target = module:<name>             -> /home/tappaas/bin/test-module.sh on the INSTALLED code
```

- Run it from the checkout (or pass `--repo`); it syncs tracked + untracked, non-ignored
  files. A PASS/FAIL line per target; the full log is in `~/src/tappaas-claude/logs/`.
- Exit code = worst target (1 fail, 2 fatal). `--deep` on makerfloss is refused without
  `--allow-canary-deep`.
- **Know what a scratch run proves.** A `test.sh` that finds its code relative to itself
  (most manager/controller suites) tests the scratch copy. Anything that calls
  `/home/tappaas/bin/*` or hard-codes `/home/tappaas/TAPPaaS` tests the site's installed code:
  that needs T3. When unsure, prove it: break the code in a throwaway worktree and check the
  run fails.
- Long runs (deep tiers, module tests): start the runner with `run_in_background`, no `nohup`
  or `&` (CLAUDE.md "Running Long Tasks").

## On a site directly (remote session on the cicd)

Work in `~/dev/TAPPaaS`, never in `/home/tappaas/TAPPaaS` (commits there block the site's
pull; the guard hook refuses them). Run a component's `test.sh` in place; `test-module.sh`
exercises the installed code.
