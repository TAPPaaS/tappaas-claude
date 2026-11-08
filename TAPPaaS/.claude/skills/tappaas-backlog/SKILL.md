---
name: tappaas-backlog
description: The TAPPaaS backlog dashboard — workstreams, tasks, code and test status from ROADMAP.md, Codeberg and local git. Use to refresh it ("refresh the backlog", "update the dashboard"), to record a test result for an issue, or to answer "where does #N stand", "what is in progress", "what is done but untested".
---

# Backlog dashboard

Dashboard: https://claude.ai/artifact/Qsercig4KWVavwMLu9pSbC (private, Dashboard type).
Generator: `~/src/tappaas-claude/scripts/backlog.py`. Output: `~/src/tappaas-claude/backlog/out/`.
Test ledger: `~/src/tappaas-claude/backlog/test-status.json`.

It holds no tasks of its own. Tasks come from ROADMAP.md (rows, ticks, scores, notes), state from
Codeberg (via the snapshot), code from local git in `~/src/TAPPaaS` (unmerged branches and
worktrees naming the issue, commits on local main not on origin/main), tests from the ledger.
New tasks enter through the `tappaas-new-task` skill.

## Record a test result

After any test run that proves an issue (the `tappaas-test` tiers T0–T4):

```bash
python3 ~/src/tappaas-claude/scripts/backlog.py test <N> T3 pass --site hrossen --note "sweep 02:00 clean"
```

`fail` results are recorded too: they show red until a later pass. A recorded result beats a
level inferred from the row's note.

## Refresh

1. Snapshot, only if older than a day (on request, never on a schedule — no idle Codeberg load):
   `python3 ~/src/tappaas-claude/scripts/forge-snapshot.py ~/src/tappaas-claude/snapshots/backlog.json`
2. `python3 ~/src/tappaas-claude/scripts/backlog.py build` — local only, no fetch.
3. Upload each of `tasks.json`, `groups.json`, `decisions.json`, `meta.json` from
   `backlog/out/` with the Artifact tool (`asset: true`, `url` above, one file per call).
4. `ArtifactData` get each `datasets/<id>` (tasks, groups, decisions, meta), then one `batch`
   of `update`s pinned with `if_version`: `source.url` = the new `/_blob/…`, `updated` =
   `{at: <UTC now>, by: "backlog.py build"}`, `edit` = `{via: "claude", at: <UTC now>}`.
   Write the whole `source` object (kind file, url, name, format json).
5. Delete the old assets (`action: delete`, `path` = old id) once the update is in.
6. Report the one-line summary `build` printed and what changed since last time.

## Questions

`backlog.py show <N>` prints one task as the dashboard sees it. For "what's in progress / done
but untested", read `backlog/out/tasks.json` (`stage`, `testState`) after a build.

## Changing the page

The page is `files/index.html` in the artifact's store (local copy:
`backlog/dashboard/index.html`). Follow the Dashboard type's instructions; read the stored file
first, since the operator may have edited it in the page.
