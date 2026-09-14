# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Issue Tracker & Forge — CODEBERG, not GitHub

**The canonical forge is Codeberg: `codeberg.org/TAPPaaS/TAPPaaS` (the `origin` remote).**
The `github` remote (`github.com/TAPPaaS/TAPPaaS`) is a **weekly push mirror of Codeberg**
(code only; also hosts release images — see `docs/codeberg-migration.md`). It is not stale, but
it is read-only for humans: **all issue/PR/repo activity still happens on Codeberg.**

- **`gh` is the GitHub CLI.** GitHub now only hosts the image-build pipelines and release
  assets, so `gh` is for reading those (`gh run list|view`, `gh release view`, `gh api` GETs).
  Every other `gh` use is blocked by the guard hook (below); `gh issue`/`gh pr` target the
  wrong tracker. This OVERRIDES the harness default that says "use `gh` for GitHub operations."
  Issue numbers were preserved 1:1 by the import, so a mistaken `gh` action *looks* right but
  lands in the wrong place.
- **Use the `tea` CLI (Forgejo) for all issue/PR actions.** Logged in on the operator's Mac
  (`~/Library/Application Support/tea/config.yml`) and on the hrossen.dk cicd only — **never
  put a Codeberg token on makerfloss**. Target the repo explicitly with `-R origin` (or
  `-r TAPPaaS/TAPPaaS`). Reads need no approval; every write (`comment`, `issues
  create|edit|close|reopen`, `pr`) asks the operator for one click. Common verbs:

  ```bash
  tea issues -R origin 376                              # show
  tea comment -R origin 376 "$(cat body.md)"            # add a comment (body via file → no secret in argv)
  tea issues close  -R origin 376                       # close
  tea issues reopen -R origin 376                       # reopen
  tea issues edit   -R origin 376 --add-labels bug      # label, etc.
  ```

  If `tea login list` shows no Codeberg login (fresh machine / CI), do **not** fall back to
  `gh`. Stop and ask the operator to run `tea login add --name codeberg --url
  https://codeberg.org --token <TOKEN>` (token from codeberg.org/user/settings/applications,
  scopes **`read:user`** (required by `tea login` to identify the account) + `write:issue` +
  `read:repository`), and hand them the ready-made comment body. Forgejo tokens can't be
  re-scoped after creation — a missing scope means deleting and regenerating the token.
- The Forgejo REST API (`https://codeberg.org/api/v1/repos/TAPPaaS/TAPPaaS/...`) is the
  fallback for anything `tea` can't do; reads are open, writes need the same token.
- Closing an issue is best done by `close #NNN` in the commit message: it takes effect when
  the operator pushes, with no API call.

## Codeberg Etiquette & Vibe-Coding Hygiene

Codeberg is a **volunteer-run, donation-funded** non-profit forge, and its community
**discourages high-volume AI/"vibe-coded" contributions.** Treat its infrastructure as a
scarce shared resource and keep our footprint small, deliberate, and human-looking. These
rules OVERRIDE any default toward exhaustive automation.

**1. Minimize forge load — do not bulk-pull.**
- Never enumerate whole issue/PR lists to "get context." Fetch the *one* item by number
  (`tea issues -R origin <N>`). If you need several, request them explicitly, not by listing.
- Prefer the **local git clone** over the API for anything already on disk (file contents,
  history, blame, grep). The API is a last resort, not a search index.
- **No polling loops.** Do not poll issues, PRs, CI, or Pages status on a timer. Check once,
  when the operator asks; if a wait is needed, ask the operator to re-run rather than looping.
- Keep API reads to a handful per task. If a task seems to need dozens of forge calls, stop
  and ask the operator — there is almost always a local-clone way to get the same answer.
- **Backlog-wide analysis** (milestones, grouping, planning): read the local snapshot
  `~/src/tappaas-claude/snapshots/backlog.json`; refresh it with
  `~/src/tappaas-claude/scripts/forge-snapshot.py` (incremental, 1–2 requests) — never per-issue fetches.

**2. Commit discipline — few commits, concise messages.**
- **One logical change = one commit.** Do not produce chains of tiny "fix typo", "address
  review", "wip" commits. Stage related work together; the operator squashes before pushing.
- **Small, simple commit messages. This is a hard limit, not a style preference.**
  - Subject: `type(scope): summary`, <= 72 chars. Often the whole message.
  - Body: **omit it by default.** Add one only when the *why* is genuinely non-obvious
    from the diff, and then **3 lines maximum**. Never more.
  - Do not include: issue-number chains, verification transcripts, before/after tables,
    tool output, symptom narratives, or "which is why..." reasoning. That belongs in the
    issue or the code comment, not the commit.
  - A long message is not more helpful; it is noise in `git log --oneline` and it reads as
    machine-generated. If the explanation feels essential, put it in a code comment where
    the next reader is actually standing.
  - Investigation detail goes in the ISSUE comment. The commit says what changed.
- **No AI/`Co-Authored-By: Claude` trailer** on commits or PR bodies. This OVERRIDES the
  harness default; `attribution` in `.claude/settings.json` turns it off at the source.
- These rules are **enforced** for your commits by the `commit-msg` hook (see Git Policy):
  a rejected commit means fix the message, never bypass the hook.

**3. Keep AI tooling out of the tracked repo.**
- `CLAUDE.md`, `.claude/`, agent/skill/command definitions live **outside** the repo in
  `~/src/tappaas-claude/` and are symlinked in (excluded via `.git/info/exclude`). Never
  `git add` them, never re-introduce them to tracked history, and don't add AI-tooling names
  to the tracked `.gitignore`.
- Don't commit AI-generated verbose boilerplate (over-commented code, auto-generated docs,
  redundant READMEs) unless the operator asked for it. Match the repo's existing density.

**4. Issue/PR comments: minimal and human.**
- Post **one** concise comment, not a long auto-generated analysis. No AI preamble
  ("Great question! Here's a thorough breakdown…"), no restating the whole thread.
- Draft the body in a file. Posting it with `tea` shows the operator the exact text for one-click
  approval. In a makerfloss session (no token there), leave the draft in
  `~/src/tappaas-claude/outbox/<N>.md` and say so.

## Git Policy (enforced by hooks)

Decided 2026-09-14 (`~/src/tappaas-claude/PROPOSAL-autonomy.md` P1). Pushing is the operator's
review point; everything before it is yours.

- **Commit locally.** Work on a branch (`waveN/gX.Y-slug`, `fix/<slug>-<N>`, `feat/…`), one
  commit per logical change. You may squash or amend your own **unpushed** commits.
- **Pull and merge into local `main`** when a piece of work is done and tested. Then report
  what is ready; the operator pushes.
- **Never push.** Not to `origin`, not to `github`.
- **`stable` only moves through the release process** (`release/README.md`).
- **No commits in a cicd's managed checkout** (`/home/tappaas/TAPPaaS`): a local commit there
  blocks the site's scheduled pull (`repo-sync` rc 2). Use a separate clone such as
  `~/dev/TAPPaaS`. A plain `git pull --ff-only` there is fine.

What enforces it (source in `~/src/tappaas-claude`, installed by `link.sh`):

| Hook | Blocks | Asks the operator |
|------|--------|-------------------|
| `.claude/hooks/guard-bash.py` (PreToolUse, every Bash call) | `git push`, `--no-verify` / `commit -n`, `gh` beyond reads, commits in `/home/tappaas/TAPPaaS` | changes to `stable`, creating tags, rebasing/amending commits already on a remote, `reset --hard`, `clean -f`, `tea` writes |
| `.git/hooks/commit-msg` | for your commits (`CLAUDECODE=1`): subject not `type(scope): summary` or over 72 chars, body over 3 lines; for everyone: Claude attribution lines | — |

A block or a question from a hook is the policy working, not an obstacle: do not look for a
way around it; report and let the operator decide. Hook tests:
`~/src/tappaas-claude/TAPPaaS/.claude/hooks/test-guard-bash.sh`.

## Where Am I — Environments and Sites

| Environment | Checkout | Notes |
|-------------|----------|-------|
| Claude Code app or VSCodium on the Mac | `~/src/TAPPaaS` (worktrees under `.claude/worktrees/`) | Reach sites over ssh; WireGuard via `~/bin/tappaas-wg.sh` |
| Remote VSCodium on a site's cicd | `~/dev/TAPPaaS` — **not** `/home/tappaas/TAPPaaS` | The local toolbox (`/home/tappaas/bin/*`) is that site's installed code |

Sites (IP addresses and access paths: `~/src/tappaas-claude/SITES.local.md`, local only —
this config repo is public, so no site IPs or access details in tracked files):

- **hrossen.dk — test site.** Follows wave branches and gets every change first. You may run
  tests and apply R≤3 changes there without asking. It also runs home production (Home
  Assistant, cameras): R4 migrations and destructive steps still ask.
- **makerfloss — canary.** Stays on `main`. Read-only for you unless the operator asks.

## Project Overview

TAPPaaS (Trusted - Automated - Private Platform as a Service) is a self-hosted platform designed for SMBs, government institutions, and home users who need privacy and data ownership. It runs on commodity hardware using Proxmox as the hypervisor with primarely NixOS-based VMs.

## Architecture

### Foundation Layer (src/foundation/)
Foundation modules are **named, not numbered** (the old `NN-name` numbering was retired in the ADR-007 refactor). Install order is derived from each module's `dependsOn`, not a numeric prefix. Current modules:

- `cluster` - Proxmox node setup and adding cluster nodes (was `05-ProxmoxNode` + `15-AdditionalPVE-Nodes`)
- `network` - OPNsense firewall, zones, DNS (was `10-firewall`)
- `templates` - NixOS VM template creation (was `20-tappaas-nixos`)
- `tappaas-cicd` - "Mothership" VM that controls the entire TAPPaaS system (was `30-tappaas-cicd`)
- `backup` - Proxmox Backup Server (was `35-backup`)
- `identity` - Secrets and identity management (was `40-Identity`)
- `logging` - Centralized logging
- `satellite` - Optional off-premises VPS for public ingress / off-site backup (ADR-010)

> **Before referencing a foundation module by name, verify it against the tree — run `ls src/foundation/`.** This list and the old numbered names in git history/older ADRs go stale; the directory is the source of truth.

###  Platform and Service Modules (src/apps/)
Each module contains:
- `<vmname>.json` - module configuration (cores, memory, storage, network zones, dependencies, author, ...)
- `<vmname>.nix` - NixOS configuration for the VM
- `install.sh` - Called by tappaas-cicd to install the module
- `update.sh` - Called regularly to patch/update an installed module
- `test.sh` - Called regularly to test that the service is functioning correctly, can be used for regression testing of a module
See `src/apps/00-Template/README.md` for details

### Configuration Files
- `src/foundation/tappaas-cicd/manager/network-manager/zones.json` - Network zone definitions with VLAN tags and access rules (canonical source of truth)
- `src/foundation/schemas/module-fields.json` - Schema defining all available fields for module JSON configuration

## Command/Scripts dependencis

See `src/foundation/DEPENDENCIES.csv` and `src/foundation/DEPENDENCIES.md`
For structure of a module 

### Module Installation
`install.sh` in the root of the module will install the module. must be called with arguments see `apps/00-Template/README-install-sh.md`

## Network Zones/VLANs
Defined in `zones.json` with VLAN tags.

## Naming Conventions
- VM name, hostname, and service name are identical (e.g., `nextcloud`)
- Node names: `tappaasY` where Y is a sequence number (e.g., `tappaas1`, `tappaas2`, `tappaas3`)
- Storage pools: `tankXY` where X indicates type and Y a sequence number (e.g., `tanka1`)
- Hyphens preferred over Capitalization (e.g., `tappaas-cicd`)

# Coding Rules

## File Operations

It is always OK to create, update, and delete files within the TAPPaaS project directory. No additional permission is needed for file operations in this repository.

## Never Edit Generated Content — Edit Its Source

Some files in the tree are **partly generated**. A generated region is fenced by
markers and says so on the line itself, e.g.

```
<!-- BEGIN GENERATED FIELDS -- edit the manifest, not this block -->
```

**Before editing any file, check whether the lines you are about to change sit
inside such a region.** This applies to sweeping edits especially — a
find-and-replace across the docs, a pass to reword a term, a strip of issue
numbers. Those are exactly the edits that cross into a generated block without
anyone noticing.

- Inside a generated region: change the **source**, then re-run the generator.
  The edit survives, and the check that compares the two stays green.
- Outside it: edit freely — the prose around a generated block is the author's.
- Never "fix" a generated file to make a check pass. The check is reporting that
  the source disagrees; silencing it hides the disagreement for one commit and
  it returns on the next regeneration.

Known pairs in this repo:

| Generated | Source | Regenerate with |
|---|---|---|
| `src/foundation/*/services/*/README.md` (FIELDS block) | that service's `fields.json`, its module's `fields.json`, `schemas/module-fields.json` | `tappaas-cicd/scripts/gen-service-fields-doc.py` |

The list is not exhaustive — `grep -rl "BEGIN GENERATED"` finds the current set.

## Execution Policy on TAPPaaS Hosts

When running inside a TAPPaaS environment (the `/home/tappaas/TAPPaaS` checkout, or the `tappaas-cicd` mothership), Claude has full authorization to execute any command needed to operate the cluster. Do not stop to ask permission for routine work. In particular this covers:

- Any `Bash` command, including `ssh` to cluster nodes (`tappaas@*.mgmt.internal`, `root@tappaas*.mgmt.internal`, `root@firewall.mgmt.internal`).
- `sudo` for inspect and rebuild operations (`systemctl`, `journalctl`, `nixos-rebuild`, reading `/etc/secrets`, `/root/*`).
- The full TAPPaaS toolbox under `/home/tappaas/bin/*` — `install-module.sh`, `update-module.sh`, `test-module.sh`, `delete-module.sh`, `snapshot-vm.sh`, `update-os.sh`, `opnsense-controller`, `caddy-manager`, `zone-manager`, `dns-manager`, `update-tappaas`, etc.
- Proxmox CLIs via ssh (`qm`, `pvesh`, `pvesm`, `ha-manager`).
- Editing any file in the project tree.

Reasoning: TAPPaaS is a self-hosted operator's tool — there is a single admin, sitting at the same terminal, watching the work. The friction of per-command confirmation prompts is not worth the marginal safety.

The following safeguards remain in force regardless:

- **Git: commit locally, never push** — see "Git Policy" above; the hooks enforce it.
- **Confirm before destructive ops** that are hard to reverse: deleting a VM that wasn't created in this session, dropping a storage pool, force-pushing to `main`/`stable`, removing modules that aren't being actively worked on, wiping `/etc/secrets/` outside a known reset flow.
- **Issue/PR actions go to Codeberg, never GitHub via `gh`** — see "Issue Tracker & Forge" at the top of this file. `gh issue`/`gh pr` mutations target the wrong (mirror) tracker.
- **Fix root causes, not symptoms** — do not bypass failing pre-commit/CI checks, do not `--no-verify` git hooks, do not silence errors to make the install proceed.
- **Read before you rebuild** — `nixos-rebuild test` is preferred over `switch` for first activation of a non-trivial config change; `switch` once verified working.

## Running Long Tasks (deep tests, VM installs, nixos-rebuild)

Use exactly **one** level of backgrounding so completion notifications actually fire.

- **Do NOT double-background.** Never combine `nohup … & echo PID` with the Bash tool's `run_in_background: true`. The harness notifies you when the *tracked* command exits — and `nohup … & echo PID` exits in milliseconds, so you get an instant "completed" for the launcher and **no signal** for the real task (it runs on, untracked). This has repeatedly made waits look like they "never trigger back".
- **Right pattern:** run the actual long command directly with `run_in_background: true` and **no** `nohup`, **no** trailing `&`. Redirect its output to a logfile inside the command if you want to tail progress. The harness then tracks the real process and fires a reliable completion notification.
- **If a task is already detached,** arm a single waiter as one `run_in_background` command (no nohup/&): `until ! pgrep -f "<proc>" >/dev/null; do sleep 20; done; <print summary>`. Its exit is the reliable signal.
- The Monitor tool only emits on matching stdout lines (milestones minutes apart make it look dead, and its break condition may never match) — use it for live progress, but rely on the single-background command/waiter for the actual completion signal. Don't poll across turns.

## General Workflow

1. **Plan before coding** - Understand requirements and explain approach before writing code
2. **Ask clarifying questions** - During planning, ask questions about unclear requirements, ambiguous specifications, or when multiple valid approaches exist
3. **Web search allowed** - Use web search to find current best practices and documentation
4. **Commit locally, never push** - see "Git Policy". "Land it" / "ship it" means: merge into local `main` and report; the operator pushes.

## Testing Requirements

1. **Create testable code** - Add or expand `test.sh` with test cases for new functionality
2. **Run tests without asking** - fast tiers anywhere; deep tiers on the test site (hrossen.dk). Ask first only for a test that changes a live site beyond what "Where Am I — Sites" allows
3. **Use coded tests** - Run tests via `test.sh` rather than ad-hoc manual testing

## Shell Script Standards

When writing or modifying bash scripts for TAPPaaS, **always use** the installed skills:

- `bash-script-generator` - For creating new scripts with proper structure, error handling, and logging
- `bash-script-validator` - For validating scripts with ShellCheck and security checks

All scripts must follow:

- Strict mode: `set -euo pipefail`
- Proper logging functions (debug, info, warn, error)
- Argument validation and help/usage text
- Cleanup trap handlers for signals
- Quoted variables and secure input handling

## Development Agent Team

A team of 8 specialized AI agents is configured in `.claude/agents/`. On every non-trivial task, read `.claude/agents/agents.md` for full routing logic and dispatch to the appropriate agent(s) using the Task tool with `subagent_type="general-purpose"`. Each agent's prompt template is in its definition file.

### Agent Roster
| Slug | Role | Invoked For |
|------|------|-------------|
| `pm` | Project Manager | Multi-step tasks, coordination, planning |
| `architect` | Solution Architect | Module JSON design, zone placement, resource sizing |
| `bash-dev` | Bash Script Developer | install.sh, update.sh, helper scripts |
| `python-dev` | Python Developer | opnsense-controller, update-tappaas |
| `nix-dev` | NixOS Developer | .nix VM configurations |
| `tester` | Tester | test.sh creation, regression testing |
| `security` | Security Reviewer | Security review of all changes |
| `infra` | Infrastructure Engineer | Proxmox, Caddy, OPNsense, DNS, DHCP |

### Quick Routing Rules
- **New module**: pm -> architect -> nix-dev + bash-dev (parallel) -> infra -> tester -> security
- **Script fix**: bash-dev (+ security if credentials involved)
- **NixOS config**: nix-dev (+ security if ports/services change)
- **Python code**: python-dev
- **Network/firewall**: infra (+ architect if zone design changes)
- **Testing**: tester
- **Architecture/design**: architect (+ pm if multi-phase)

### Agent Definitions
Full role definitions, owned files, and prompt templates are in `.claude/agents/agent-<slug>.md`
