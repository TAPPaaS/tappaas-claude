# tappaas-claude — Claude Code config for the TAPPaaS repos

This repo holds the Claude Code configuration (`CLAUDE.md`, `.claude/agents`,
`.claude/commands`, `.claude/skills`, `.claude/settings.json`) for the TAPPaaS
repositories. **It is deliberately kept OUT of those repos.**

It lives on GitHub — **<https://github.com/TAPPaaS/tappaas-claude>** — shared among TAPPaaS
operators.

## Why

We wnat to seperate recomendation for how to use AI to improve the TAPPaaS solution from the actual TAPPaaS source code

The TAPPaaS repos live on [Codeberg](https://codeberg.org/TAPPaaS), a volunteer-run,
donation-funded forge whose community discourages high-volume AI / "vibe-coded"
contributions. To respect that, the AI tooling and its instruction files must not be
committed to or pushed to Codeberg. 

They live here on GitHub instead (already the TAPPaaS
mirror org) and are **symlinked** into each repo, so Claude
Code still auto-discovers them locally while nothing reaches the TAPPaaS code repos.

## Layout

```
tappaas-claude/
├── README.md            ← this file
├── link.sh              ← (re)creates the symlinks in each repo
├── TAPPaaS/
│   ├── CLAUDE.md
│   └── .claude/{agents,commands,skills,settings.json}
└── Documentation/
    ├── CLAUDE.md
    └── .claude/{agents,commands}
```

(The `Community` repo had no shareable Claude config — only a machine-local
`settings.local.json`, which was simply untracked and left in place.)

## How the wiring works

For each repo under `~/src/<repo>`:

- `~/src/<repo>/CLAUDE.md`            → symlink to `tappaas-claude/<repo>/CLAUDE.md`
- `~/src/<repo>/.claude/agents`       → symlink to `tappaas-claude/<repo>/.claude/agents`
- `~/src/<repo>/.claude/commands`     → symlink to `tappaas-claude/<repo>/.claude/commands`
- `~/src/<repo>/.claude/skills`       → symlink (TAPPaaS only)
- `~/src/<repo>/.claude/settings.json`→ symlink (TAPPaaS only)

Machine-local, non-shared files stay **real** inside each repo and are untouched:
`.claude/settings.local.json`, `.claude/worktrees/`, `.claude/scheduled_tasks.lock`.

Git never sees the symlinks: each repo's `.git/info/exclude` (local, never pushed) ignores
`CLAUDE.md` and `.claude/`, and the AI-tooling lines were removed from the tracked
`.gitignore` files so history stops naming them.

## Setup on a new machine

```bash
git clone https://github.com/TAPPaaS/tappaas-claude ~/src/tappaas-claude
cd ~/src/tappaas-claude
./link.sh                                          # recreates symlinks + excludes
```

`link.sh` is idempotent — safe to re-run. It assumes the TAPPaaS repos are checked out as
siblings under `~/src/` (pass `--repos-root DIR` if they live elsewhere).
