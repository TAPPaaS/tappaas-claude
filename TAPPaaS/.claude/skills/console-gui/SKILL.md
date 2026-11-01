---
name: console-gui
description: Working on the TAPPaaS console (src/foundation/tappaas-cicd/ui): where things are, the preview/apply contract, the shared components, fixture mode, the visual loop, the viewports, the wording rules and the review checklist. Load for any task that touches ui/.
---

# The console GUI

The console is `src/foundation/tappaas-cicd/ui` ("ui"): a TypeScript server (`ui/src`) and a React/Vite web app (`ui/web`). Read `docs/plans/console-gui-pipeline.md` for the why; `.interface-design/system.md` (repo root) for the tokens, patterns and wording; `ui/README.md` for the server.

## Where things are

| What | Where |
|---|---|
| Routes and the API | `ui/src/server.ts`; reads in `reads.ts`, jobs in `jobs.ts`, verbs run through `run.ts`'s `Runner` |
| Pages | `ui/web/src/pages/*.tsx` (Overview, Health, HealthPanel, Operations, Assets, AssetPage, Physical, RemoveNode, AddNode, CiPanel, Zones, Identity, …) |
| Physical view | `ui/web/src/physical/*` (SidePanel right, Unplaced left, rack and rooms in `layout.ts`, drag-and-drop in `dragdrop.tsx` + pure `dragplace.ts`) |
| Wizards and operate buttons | `ui/web/src/wizard.tsx` (`StepRow`, `DecideStep`), `flows.tsx` (`ActStep`, `CheckStep`, `TypedConfirm`, `FindingList`), `operate.tsx`, `stepform.tsx`, `argv.ts` (`stepFlow`, `previewKindOf`, `isDestructiveCall`) |
| Jobs in the web | `ui/web/src/jobs.tsx` (`JobStatusLine`, `JobOutput`, `Output`: sticks to the last line unless the reader scrolled), `run.ts` (`useJobRun`), `api.ts` (`previewJob`, `applyJob`, `applyNowJob`) |
| Health graph | `ui/web/src/healthgraph.ts` (hub clustering), `pages/Health.tsx`, `HealthPanel.tsx` |
| Style | `ui/web/src/styles.css` (all tokens on `:root`), `breakpoints.ts` (mirrors the `--bp-*` tokens), `colors.ts` (reads tokens only) |
| Unit tests | `ui/test/unit/*.test.ts`, run by `ui/test.sh` (pure functions and the server; no DOM) |
| Fixtures | `ui/test/fixtures` (captured from hrossen by `capture.sh`, redacted), `2026-10-17/` frozen for old assertions |

Use the shared components. A new step, confirm, output panel or status line is a review finding, not a feature.

## The preview/apply contract

Every verb a button or wizard runs has a manifest `preview.kind`:

- `apply-flag`: the verb without `--apply` is the plan; apply adds `--apply`. Exit 2 from the plan means "pending changes".
- `dry-run-flag`: `--check` / `--dry-run` is the plan.
- `none`: no dry run; the preview states the argv ("… has no dry run. Apply runs exactly: …").

The jobs layer runs the preview first and stops on a refusal; `applyNowJob` applies only when the preview is clean. Destructive verbs need the object's name typed (server-enforced). A job with a secret has no dry run. With `TAPPAAS_SIMULATE=1` in the service's environment an apply runs the preview instead and reports `simulated: would run <argv>` (README "Simulate").

## Running it without a system

```bash
src/foundation/tappaas-cicd/ui/fixture-server.sh --port 9097
```

Serves every page from the fixtures on this machine; `CONSOLE_NOW` stops the server's clock, `X-Console-Actor` is the trusted sign-in, the verb journal is `/tmp/tappaas-console-fixtures-9097/journal.jsonl`. Module icons 404 by design. This is layer A of the design: every look, wording and click path is checked here, never on hrossen.

## The visual loop

```bash
src/foundation/tappaas-cicd/ui/web/e2e/run.sh [--routes id,…] [--viewports phone,laptop] [--allow id,…] [--update-baseline]
```

Builds, serves from fixtures, captures every route in `e2e/routes.json` at the four viewports (phone 390×844, tablet 820×1180, laptop 1366×768, desktop 1920×1080) as a PNG and an accessibility `.txt`, diffs against the local baseline and writes `e2e/report.md`. Read the report, open only the diff images it names, at half scale. A route the change names may differ (`--allow`); any other difference is a regression. PNG baselines are local (regenerated from the base commit when stale); the `.txt` baselines are in git and are refreshed with `--update-baseline` when the operator has accepted a look.

A coding session's done-criterion: `ui/test.sh` green, `scripts/test/test-console-design.sh` green, `run.sh` clean or the diff is the intended one and the baseline updated.

## Shipping a web change: the dist, the push, hrossen

The served web app is `ui/web/dist`, committed, and nix builds its own copy from the lock file (`ui/default.nix`, `buildNpmPackage` with `npmDepsHash`). A session never commits a Mac-built dist: it builds on hrossen's nix and commits that.

1. **Lock unchanged?** `git diff <last dist commit>..HEAD -- ui/web/package-lock.json`. If the lock changed, the hash in `ui/default.nix` must be recomputed on hrossen first (`prefetch-npm-deps package-lock.json`) and committed, or the module update fails on the old hash.
2. **Build on hrossen** from a scratch copy of the committed tree (never the live checkout):
   ```bash
   export SSH_AUTH_SOCK="$(launchctl getenv SSH_AUTH_SOCK)"
   ssh cicd-hrossen 'pgrep -af "site-manager|module-manager" | grep -v pgrep; rm -rf ~/dev/scratch-dist && mkdir -p ~/dev/scratch-dist'
   git archive HEAD src/foundation/tappaas-cicd/ui | ssh cicd-hrossen 'tar -x -C ~/dev/scratch-dist'
   ssh cicd-hrossen 'cd ~/dev/scratch-dist/src/foundation/tappaas-cicd/ui && nix-build default.nix -A web --no-out-link | tail -1'
   ```
   The store path printed holds `index.html` and `assets/` at its root.
3. **Commit the dist**: the old files are read-only (they came from the store), so `chmod -R u+w web/dist` before `rm -rf web/dist`; then `ssh cicd-hrossen "cd <store path> && tar -c .; rm -rf ~/dev/scratch-dist" | tar -x -C web/dist`, `chmod -R u+w web/dist`, and commit only `ui/web/dist` as `build(console): web dist with …`.
4. **The operator pushes** (a hook blocks pushing from a session). Ask for it once, with everything merged; confirm with `git fetch` that `origin/adr-041` is at the tip before deploying, since a push can stop short.
5. **Deploy**: `ssh cicd-hrossen '~/bin/refresh-control-plane.sh; module-manager update tappaas-cicd'` (the module test step runs; the console service restarts), then `systemctl is-active tappaas-console.service`.
6. **Check live** at `https://console.hrossen.dk` in the browser pane (the operator is signed in there; a session never enters credentials): `get_page_text` or `find` for the changed wording, one screenshot at scale 0.6 for a layout change. A read that lands before the storage inventory loads shows pools without sizes; read again.

Only one session writes the console sources at a time: a second GUI session works on its own worktree and branch, and the session that merges does steps 2 to 5 once for the merged tree.

## Reading a page cheaply

`read_page` with `filter: interactive` to find controls, `find` by label, `get_page_text` for wording, `zoom` for an icon, a screenshot at scale 0.5 only for layout, and the capture's `.txt` instead of a live page whenever fixture mode has the route. One screenshot per page and viewport, never one per step.

## Wording and behaviour rules (the operator's)

- Say "the machine's asset record", "the primary location"; never a flag, a file name or an internal (site.json, a vmid) in a wizard.
- One button per step. A selection never collapses its step: a Continue follows it.
- A button that is disabled says why next to it; pressing a Remove/Apply shows the output panel at once, with the status line and its Stop.
- Side panels open with a "Details" link at the top, not Change/Open in.
- Headings over lists ("Storage bays"), then the rows; no stray words from the model.
- The Ack dialog: type fixed, note blank, date picker with the grey default, the `--until` value quoted.
- Health roll-ups read "7 of 17 members warning"; no bare counts beside a word.

## Review checklist

Does the step collapse on select? Is there a Continue? Is any button disabled without a reason? Does the output stick to the last line while running? Is every word one the operator uses? Does the side panel start with Details? Does it hold at phone width (no horizontal scroll, 16 px gutter)? Is the colour or spacing a token (`test-console-design.sh`)? Does the preview say exactly what the apply runs?
