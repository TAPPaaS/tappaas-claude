---
name: tappaas-new-task
description: Brings new work into the TAPPaaS backlog — one idea, a bug seen in passing, or a pasted list — as a Codeberg issue plus a scored row in the right ROADMAP.md group, with an optional worktree session to start it. Use when the operator says "new task", "add to the backlog", "file this", "track this", "/tappaas-new-task", or hands over a list of things to do.
---

# New task into the backlog

The backlog has one source of truth: **ROADMAP.md rows** (where, in what order, scored) backed
by **Codeberg issues** (the detail). A new task gets both, or it is not in the backlog. The
dashboard (`tappaas-backlog` skill) reads them; it never holds tasks of its own.

Forge rules from `CLAUDE.md` hold: Codeberg via `tea`, one approval per issue created, no
list enumeration. ROADMAP.md commits go straight on `main` in `~/src/TAPPaaS` with the
`-- ROADMAP.md` pathspec only; never stage anything else there, never switch branch.

## 1. Understand each item

For every item (a list is handled item by item, one approval batch at the end):
- What is wanted, in one sentence the issue title can use (≤ 80 chars, says the outcome, not
  "investigate X").
- **Duplicate check, locally only:** search titles and bodies in
  `~/src/tappaas-claude/snapshots/backlog.json` and the rows in ROADMAP.md (`grep -n -i`).
  A likely duplicate → propose a comment on that issue instead of a new one.
- Which code it touches (a quick `ls`/`grep` in `~/src/TAPPaaS/src`), enough to score it.

## 2. Place and score

- **Group:** read the group headings and their purpose lines in ROADMAP.md
  (`grep -n '^### G' ROADMAP.md` and the line after). Pick the group whose purpose covers it.
  None fits → *Future Work* (no Ease/Risk columns there). Never invent a group; if several
  items share a theme no group covers, say so and suggest one for the operator to decide.
- **Ease** L/M/H and **Risk** L/M/H by the tables under *The scores* in ROADMAP.md. Risk is
  what an existing install goes through via `update-tappaas`.
- **Order inside the group:** rows are read top to bottom and the first unticked row is next.
  Put the new row where it belongs in that order (after what it depends on), not by habit at
  the bottom.
- **Note** ≤ 200 chars, ROADMAP style: `**Opened YYYY-MM-DD.**` plus the one fact that matters
  (dependency, who reported it). No ADR history.

## 3. Show the plan, one approval

Show a table: item → title, group, position (after #N), Ease, Risk, note, duplicate found.
Then one AskUserQuestion with "File all" / "Let me adjust". Nothing is created before it.

## 4. File

Per item, after the yes:
1. Issue body to `~/src/tappaas-claude/outbox/new-<slug>.md`: what and why in a few lines,
   acceptance in a short list, the files it touches. No AI preamble.
2. `tea issues create -R origin --title "<title>" --description "$(cat <file>)" --milestone "<milestone>"`
   — `--milestone` takes the name, not the id: `"Release 2.1: Security and stability release"`
   for wave work, `"Future Work"` for Future Work. Read the new number from the output.
3. Add the row to ROADMAP.md: `| #N | <title> | E | R | <note> |` in its group table, bump the
   heading's `open: N` and the *At a glance* row. Future Work rows are `| #N | <title> | <note> |`.
4. One commit for the batch, on main in `~/src/TAPPaaS`:
   `git -C ~/src/TAPPaaS commit -m "docs(roadmap): #N, #M into G6.1, Future Work" -- ROADMAP.md`
   (commit-msg hook: subject ≤ 72, body ≤ 3 lines, no co-author line). Not pushed: say so.
5. Pull the new issues into the snapshot: `python3 ~/src/tappaas-claude/scripts/forge-snapshot.py
   ~/src/tappaas-claude/snapshots/backlog.json` (incremental, 2–3 calls).

## 5. Offer to start

For each item ready to work on (no unmet dependency, not Future Work): offer a session
(`start_session`, own_initiative, model opus, own worktree) whose brief names the issue, the
group, the Risk and therefore the test level it needs (L → T2, M/H → T3), and says to record
the result with `backlog.py test`. Then offer a dashboard refresh (`tappaas-backlog`).

## Report

Issue numbers with links, where each landed in ROADMAP.md, the commit (unpushed), sessions
offered.
