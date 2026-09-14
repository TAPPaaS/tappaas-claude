# Proposal — more autonomy for Claude on TAPPaaS, inside the Codeberg boundary

**Status:** revised after operator review 2026-09-14. **Step 1 (guardrails) applied
2026-09-14**: guard hook, commit-msg hook, settings, CLAUDE.md git/forge/sites sections,
`SITES.local.md`. Also `tea` added to `tappaas-cicd.nix`. **Step 2 (reach and tests)
applied 2026-09-14**: ssh aliases, `SITES.md`, `scripts/tappaas-test.sh`, `tappaas-test`
skill, dev clone + linked config on hrossen (`~/dev`). **Step 3 (agents) applied 2026-09-14**:
seven native `tappaas-*` subagents, `agents.md` routing, CLAUDE.md "Subagents"; the old
`agent-*.md` templates are kept until sessions started before that date end, then deleted.
Steps 4–5 not started.
**Purpose:** let Claude implement the waves in
`TAPPaaS/docs/design/release-2.1-implementation-plan.md` with far fewer stops,
while Codeberg still only ever sees the operator.

### Decisions from review (2026-09-14)

| Topic | Decision |
|-------|----------|
| Staging forge (P3) | Not now; maybe later. Replaced by a **pull hold** on the test site (P3a) |
| Test site | **hrossen.dk** moves to wave branches and gets every test first; **makerfloss** stays on `main` |
| Pull and merge | Claude may `git pull` and merge into local `main`. Pushing stays manual |
| `tea` | Binary on every cicd (`tappaas-cicd.nix`); already on the Mac. **Logged in only on the Mac and hrossen.dk**: no Codeberg token on makerfloss, a platform the operator does not fully control |
| WireGuard | `~/bin/tappaas-wg.sh` gains a no-sudo backend through the WireGuard for macOS app (P4) |
| Gridtefy retro commands | Explained in §7; removal proposed |
| Site facts | tappaas-claude is public, so IPs and hostnames go in a local, gitignored file |

---

## 1. The boundary

Codeberg does not want direct AI interaction. So the line is drawn at the forge,
not at the laptop:

| Where | Claude's autonomy |
|-------|-------------------|
| Local clones, worktrees, the two TAPPaaS sites | High: edit, commit, merge into local `main`, test, run changes on the test site |
| Codeberg | Reads only (one issue by number, or the local snapshot). Every write goes through the operator: `git push` by hand, issue comments through a one-click approval |

Everything else in this proposal follows from that line.

---

## 2. What is in the way today

| Finding | Effect |
|---------|--------|
| "Never `git commit`" | Every logical step ends in a stop; no local history to review, bisect or squash |
| Rules exist only as prose; `settings.json` allows all `Bash`, and `settings.local.json` even allows `git push:*` | The safety depends on the model remembering; the operator compensates by reviewing everything |
| `.claude/agents/*.md` have no frontmatter | They are not real subagents. CLAUDE.md makes Claude read `agents.md` and paste a template into a general-purpose agent on *every* non-trivial task: slow and token-heavy |
| Agent roster drift | `agents.md` routes to a `typescript-dev` that does not exist; CLAUDE.md says 8 agents, there are 9 |
| CLAUDE.md points to `.claude/skills/adr-007-driver/` | That skill no longer exists; the only autonomous stage-gate loop is gone |
| "Propose tests first and ask approval" vs "full authorization on TAPPaaS hosts" | Contradictory; Claude stops to ask before running a test |
| Both sites track `main` (hrossen.dk since 2026-08-30, makerfloss since 2026-09-01) | Any push to `main` deploys to both on the next sweep. There is no site that tests a branch |
| Committing in the cicd's managed checkout blocks its auto-pull (`repo-sync` rc 2) | A remote VSCodium session cannot safely work where it opens |
| The Mac has no nix, node or tsc | TypeScript and nix checks only run on a cicd, by hand-rolled tar pipes |
| WireGuard switcher needs interactive sudo; one tunnel at a time | Claude cannot reach a site on its own from the Mac |
| Memories are per machine | What a remote session learns on hrossen never reaches the Mac session, and back |
| `commands/retro.md` and `post-task-retro.md` are marked "Proprietary — Gridtefy Ring-4, not for upstream donation" | Odd content for the shared config repo; decide whether they stay |

---

## 3. Proposals

### P1 — Git: commit locally, push by hand

- Claude **may commit** on any local working branch (`waveN/gX.Y-slug`,
  `fix/…`, `feat/…`), one commit per logical change, and may squash or amend
  its own **unpushed** commits.
- Claude **never pushes** to `origin` (Codeberg) or `github`. Pushing is the
  operator's review point.
- Claude may `git pull` and **merge working branches into local `main`**
  (decided 2026-09-14). Anything that touches `stable` needs an approval
  prompt: `stable` only moves by the release process.
- No commits ever in a cicd's managed checkout (`/home/tappaas/TAPPaaS`).
- Message rules stay as today (≤ 72-char Conventional subject, body ≤ 3 lines,
  no `Co-Authored-By: Claude`), but are **enforced by a `commit-msg` git hook**,
  not by memory. This also overrides the harness default that adds the trailer.

Enforcement, not prose (drafts in §5):

- `githooks/commit-msg` in tappaas-claude, installed by `link.sh` into each
  repo's `.git/hooks/` (local, never tracked).
- A Claude Code `PreToolUse` hook, `hooks/guard-bash.sh`, that **denies**
  every `git push`, `--no-verify`, `gh` writes and commits in
  `/home/tappaas/TAPPaaS`; and **asks** for anything that changes `stable`.

**About `gh`:** it is the **GitHub** CLI, not a Codeberg tool (Codeberg's
is `tea`). GitHub is now only used for the image-build pipelines and release
hosting, so `gh` is only needed to read those, e.g. `gh run list` or
`gh release view`. Every `gh` write is blocked, and issue/PR commands are
blocked entirely: on GitHub they land in the wrong tracker. `gh` is also
installed on the cicd today.

With the guard in place, CLAUDE.md drops the long "never commit" paragraphs
and the stale ADR-007 carve-out.

### P2 — Codeberg issues through `tea`, with one-click approval

**Where `tea` is installed:**
- **Mac:** already installed (Homebrew), with a `codeberg` login.
- **Both cicds:** added to `environment.systemPackages` in
  `src/foundation/tappaas-cicd/tappaas-cicd.nix` (uncommitted). It reaches
  both sites with the next rebuild of tappaas-cicd after the push to `main`.
- **Login on hrossen.dk only**, a one-time operator step:
  `tea login add --name codeberg --url https://codeberg.org --token <TOKEN>`
  with a token of its own (scopes `read:user`, `write:issue`,
  `read:repository`) that can be revoked alone. **No login on makerfloss**:
  the binary is there, but without a token it can do nothing. Issue writes
  from a makerfloss session go to the outbox and are posted from the Mac or
  hrossen.dk.

- **Reads:** `tea issues -R origin <N> --comments` for a named issue, or the
  local snapshot (`scripts/forge-snapshot.py`) for anything backlog-wide. No
  prompt.
- **Writes** (`tea comment`, `tea issues close|edit|create|reopen`, `tea pr`):
  a permission **ask** rule. Claude drafts, the operator sees the exact text
  in the prompt and clicks once. The human stays in the loop without
  copy-paste.
- **Outbox for batches:** during a wave, Claude writes one short comment per
  issue to `~/src/tappaas-claude/outbox/<N>.md` (gitignored).
  `scripts/tea-outbox.sh` lists them, shows each, and posts on "y". The
  operator can run it at the end of a session in one go.
- **Closing issues:** through `close #N` in the commit message, which takes
  effect when the operator pushes. No API call.

### P3a — Pull hold on the test site (replaces staging for now)

`site-manager update --no-git-pull` already exists: it sets
`TAPPAAS_NO_GIT_PULL=1`, and `scripts/refresh-control-plane.sh` then skips the
pull and runs the rest of the sweep on whatever is checked out. The missing
piece is making that **persist** for the scheduled runs on one site.

**Proposal:** a per-repository hold marker that is local to the site.
- **Marker:** a file under `~/config/.repo-hold/<repo>` containing a reason,
  who set it, and an expiry.
- **Set and clear:** `site-manager repository hold <repo> --reason … --until …`
  and `site-manager repository release <repo>`.
- **Effect:** while the marker exists and has not expired,
  `refresh-control-plane.sh` treats that repository as if `--no-git-pull` was
  given. The rest of the sweep runs normally.
- **Visibility:** the sweep log and `site-manager` show the hold. An expired
  hold warns and pulls again, so a forgotten hold cannot freeze a site.
- **Tracking:** added to the plan as a new G0.3 item.

**How the test site (hrossen.dk) gets a change:**

| Case | Steps |
|------|-------|
| Pushed branch | The operator pushes `waveN/...` to Codeberg; Claude runs `site-manager repository modify TAPPaaS --branch waveN/...`, then `update --force` and the deep tests. The scheduled sweeps follow the branch. Back to `main` when the group lands |
| Unpushed work | Claude syncs the working tree into hrossen's checkout as **uncommitted** changes (never a commit there), sets the hold, runs `site-manager update --no-git-pull` and the deep tests. Scheduled sweeps keep running on it without wiping it. At the end: release the hold, restore the checkout with `git checkout -- . && git pull` |

The second case gives most of what staging would, with nothing leaving the
two sites and the Mac.

### P3 — A self-hosted staging remote (deferred, "maybe later")

TAPPaaS already runs a Forgejo at `forgejo.makerfloss.eu`. Add a repository
there, e.g. `TAPPaaS/TAPPaaS-staging`:

- Claude **may push** wave branches to the `staging` remote only (the guard
  allows exactly that remote; never `--force`).
- A test site follows a wave branch from staging:
  `site-manager repository modify TAPPaaS --url forgejo.makerfloss.eu/TAPPaaS/TAPPaaS-staging --branch waveN/...`
  (`--url` is supported today), runs `update-tappaas --force`, and switches
  back to Codeberg `main` afterwards.
- **One-way only:** staging never mirrors to Codeberg. The operator pushes the
  finished, squashed branch to Codeberg from the Mac.
- Later: Woodpecker agents on a TAPPaaS node for that Forgejo give CI on every
  staging push (the same runners #415 asks for).

Without P3, a branch deploy needs the operator to push the branch to Codeberg
first. That works, but it puts unfinished work on Codeberg and a human step in
every test loop.

### P4 — Three ways of working, one set of rules

| | Claude Code app on the Mac | VSCodium on the Mac | Remote VSCodium on a cicd (hrossen.dk / makerfloss.dk) |
|---|---|---|---|
| Checkout | `~/src/TAPPaaS` | same | **`~/dev/TAPPaaS`**, a separate clone. Never the managed `/home/tappaas/TAPPaaS` |
| Parallel work | one worktree per wave group (`.claude/worktrees/<group>`, which still picks up the parent CLAUDE.md) | a different worktree than the app session | one dev clone per cicd |
| Commit | local (P1) | local | local in the dev clone |
| Push | operator, from a Mac terminal | same | operator, via forwarded ssh agent |
| Reaching a site | ssh aliases (below) | same | local toolbox for its own site; ssh alias for the other |
| Claude config | symlinked from `~/src/tappaas-claude` | same | clone tappaas-claude on the cicd; `link.sh --repos-root ~/dev` |
| Issue writes | `tea` with ask rule | same | hrossen.dk: `tea` with its own token, same ask rule. makerfloss: outbox only |

**ssh access, as tested on 2026-09-14:**
- **hrossen.dk:** reachable directly, `ssh tappaas@hrossen.dk`. It lands on
  `tappaas-cicd`, on `main` at `a52a98b`, with no `tea` yet.
- **makerfloss:** reachable only through the WireGuard tunnel. With the
  tunnel up, `ssh tappaas@<makerfloss cicd>` lands on `tappaas-cicd`, on
  `main`, with no `tea`.

**WireGuard without sudo.** A sudoers no-password rule for `wg-quick` is not
safe on this Mac. The tunnel configs, the `wg-quick` script and the Homebrew
tree are all owned by the operator's user account. Anything running as that
user could edit a config's `PostUp` line or swap the binary, then run it as
root without a password.

Instead, `~/bin/tappaas-wg.sh` now has two backends:
- **app:** the official **WireGuard for macOS** app (App Store). The
  script drives its tunnels with `scutil --nc start|stop|status`, which
  needs no sudo. The app keeps the private keys in the Keychain. The script
  picks this backend automatically once both tunnels exist in the app, under
  the names `tappaas-mf` and `tappaas-hrossen`.
- **wg-quick:** the old sudo path, kept as a fallback.

Operator steps:
1. Install WireGuard from the App Store.
2. Import `tappaas-mf.conf` and `tappaas-hrossen.conf` in the app, keeping
   those names.
3. Optionally delete the plaintext `.conf` files afterwards.

The previous script is kept as `~/bin/tappaas-wg.sh.orig`.

Define aliases in `~/.ssh/config` (e.g. `cicd-hrossen`, `cicd-makerfloss`).
Note that both sites use `10.0.0.0/24`, so with a tunnel up a bare
`10.0.0.x` address can hit the wrong site. Aliases avoid that mistake.

**Shared site knowledge.** Move the durable site facts now scattered over
per-machine memories into tappaas-claude:
- which branch each site tracks;
- access paths;
- quirks, such as the makerfloss WAN being wired only to tappaas1, and the
  nested-ssh flag loss.

All three environments then read the same file. tappaas-claude is **public**,
so: a shared `SITES.md` with structure and no addresses, plus a gitignored
`SITES.local.md` (copied to each machine) for IPs and access paths. The
`tappaas-issue` skill currently hard-codes the makerfloss cicd IP; that moves
to the local file.

### P5 — Testing ladder

This matches the plan's §10.1 levels, with one script doing the transport.

| Step | Where | What | Claude asks? |
|------|-------|------|--------------|
| T0 | Mac | `shellcheck`, `bash -n`, JSON schema checks on changed files | no |
| T1 | scratch dir on a cicd | Sync the working tree to `~/dev/scratch/<branch>`; run fast tiers (TS unit suites, python unittests, `lib/test-*.sh`, `nix build` of changed components) | no |
| T2 | a site, read-only | Deep tiers that only read: `test-module.sh --deep`, `network-manager reconcile` dry-run, `zone-manager` check mode | no |
| T3 | **hrossen.dk** | A pushed branch, or unpushed work under a pull hold (P3a): `update --force` / `--no-git-pull`, deep tests, then back to `main` | no, for R ≤ 3 changes; yes for R4 migrations and anything destructive |
| T4 | **makerfloss** | After the operator pushes to `main`: one scheduled sweep, check `last-update-result.json` | no (read-only) |
| T5 | blank install | `rc/<ver>` fresh install + upgrade from `stable` (release/README.md step 4) | operator-driven |

One transport script, `scripts/tappaas-test.sh`:

```bash
tappaas-test.sh <site> [--sync] [--fast|--deep] <component>...
```

It:
- ships the working tree (tracked plus modified files) with a tar pipe;
- runs each component's `test.sh` through a `bash -s` heredoc, so flags survive
  the nested ssh;
- saves the output to `~/src/tappaas-claude/logs/` and returns the real exit
  code.

Claude calls one command instead of rebuilding the ssh chain each time.

**Know what a scratch run proves.** Tests that call `/home/tappaas/bin/*`
exercise the site's installed code, not the scratch copy. Each component's
`TEST.md` should mark which tiers are scratch-safe; everything else needs T3.

**Two sites, two roles (decided):** hrossen.dk is the test site (T3); Claude
may change it for R ≤ 3 work. makerfloss is the canary (T4); it stays on
`main` and is read-only for Claude unless asked. hrossen.dk also runs
production workloads (Home Assistant, cameras), so a failed T3 is felt at
home. That is why R4 and destructive steps still ask.

Optional: a `pre-push` hook on the Mac runs T0 + T1 for the components the
push touches, so a push never carries a red fast tier.

### P6 — Agents: native subagents, fewer of them, used for isolation

- Convert the kept agents to **native Claude Code subagents** (frontmatter:
  `name`, `description`, `tools`, `model`). Claude can then call them
  directly by type; no more reading `agents.md` and pasting templates.
- Drop the CLAUDE.md rule "on every non-trivial task read agents.md and
  dispatch". Use subagents where they pay off: **context isolation** (site
  operations, long test runs, reviews, research). Writing code on the same
  files is faster in the main session.
- Roster:

| Agent | From | Purpose |
|-------|------|---------|
| `site-operator` | new | Runs commands on a named site through the aliases and the heredoc rule; read-only unless told; returns a summary, keeps logs out of the main context |
| `upgrade-tester` | new | Runs T3 for a branch: repoint, update, deep tests, repoint back; reports pass/fail per component |
| `adr-reviewer` | from `architect` + `pm` | Checks an ADR against the code and open issues; drafts amendments; used for the wave entry gates |
| `migration-author` | new (after G0.1 lands) | Writes a migration + fixture test to the framework's contract |
| `tester` | kept | test.sh / deep-tier cases, regression tests |
| `security` | kept | Review of firewall, secrets and exposure changes (most of Wave 2 and G1.6) |
| `nix-dev` | kept | NixOS modules; the common baseline (G1.4) |
| `opnsense` + `infra` | merged into `network` | Zones, rules, DNS, Caddy, Proxmox networking |

  `bash-dev` and `python-dev` become conventions inside the skills rather than
  agents; `pm` is covered by the built-in Plan agent.
- Suggested models: `sonnet` for site-operator, upgrade-tester and tester;
  the session model for reviewers.

### P7 — Skills

| Skill | Change |
|-------|--------|
| `tappaas-wave` (new) | The driver for one plan group, replacing the retired ADR-007 stage-gate driver. See below |
| `tappaas-issue` | Commit locally in Phase 5 (P1); test through `tappaas-test.sh` (P5); post through the ask rule or outbox (P2); **skip the Phase 4 gate when the issue belongs to a wave group whose entry gate is met**, since the decision was taken at the gate |
| `tappaas-test` (new) | The ladder, the script, what is scratch-safe, which site has which role |
| `tappaas-adr` (new) | ADR-013 format, status transitions (Draft → Proposed → Accepted → Accepted-implemented), amendment style; used to write the 8 new ADRs in plan §10.4 |
| `tappaas-migration` (new, after G0.1) | The migration contract and fixture test |
| bash skills | Unchanged; loaded only when used |

**`tappaas-wave <group>`, in outline:**

1. Read the group's table and gate row from the plan. Check the entry gate
   from local files: ADR status lines and the decision log. If a gate is not
   met, stop and say which.
2. Create a worktree and branch `waveN/gX.Y-slug` from `main`.
3. For each issue, in the plan's order: read it (snapshot, or `tea` for that
   number); implement; add a deep-tier regression case; run T0–T2; commit
   (`fix(scope): … (#N)`); draft the outbox comment.
4. Group gate: T3 on hrossen.dk under a pull hold, at the §10.1 level of
   the group's riskiest issue. Then merge into local `main` and ask the
   operator to push.
5. Report: commits, test results, outbox, a proposed squash plan and one
   message per logical change; update the group's status in the plan doc.

It stops without asking only on:
- an unmet gate;
- a test it cannot make green without changing the design;
- anything destructive or R5;
- applying an R4 migration on a live site;
- a decision that belongs to the operator.

**Pilot:** G0.2 (8 small issues, #644 first). It is contained, exercises the
whole loop, and fixes the tools the later waves rely on.

### P8 — A shorter CLAUDE.md

CLAUDE.md is loaded in every session: 265 lines today. Proposed shape, about
120 lines:

1. **Forge boundary** — §1 of this proposal, plus the tea verbs.
2. **Git policy** — P1 in eight lines; "the hooks enforce this".
3. **Where am I** — the three-environment table (P4); never touch the managed checkout.
4. **Sites** — pointer to `SITES.md`; the branch site and the main site.
5. **Testing** — the ladder (P5) and "run tests without asking, up to the site's role".
6. **Execution policy** — as today, minus the contradictions.
7. **Codebase pointers** — foundation list (verify with `ls`), generated
   content rule, shell standards (pointer to the skills), long-task
   backgrounding.

Architecture prose that duplicates `docs/` moves out; the agent roster moves
into the agent files themselves.

---

## 4. Autonomy at a glance

| Claude does without asking | Claude asks (one click) | Never — blocked by hook or deny rule |
|----------------------------|-------------------------|-------------------------------------|
| Edit any file in the repos | `tea comment`, `tea issues close/edit/create`, `tea pr` | `git push` to Codeberg or GitHub |
| Branches, worktrees, local commits, squashing unpushed commits | Anything that changes `stable` | Any `git push`, force push, `--no-verify` |
| `git pull`; merge working branches into local `main` | Mutating makerfloss | `gh` writes; `gh issue` / `gh pr` entirely |
| T0–T2 on either site; T3 on hrossen.dk for R ≤ 3, incl. setting and releasing a pull hold | Applying an R4 migration on a live site | Commits in `/home/tappaas/TAPPaaS` |
| Read one issue by number; refresh the snapshot | Destructive operations (delete VM, drop pool, wipe secrets) | `Co-Authored-By: Claude` in a commit |
| Draft comments to the outbox | Anything R5 | |

---

## 5. Drafts

**`TAPPaaS/.claude/settings.json`**

```json
{
  "permissions": {
    "allow": ["Bash", "WebSearch",
              "WebFetch(domain:pbs.proxmox.com)", "WebFetch(domain:docs.opnsense.org)",
              "WebFetch(domain:grafana.com)", "WebFetch(domain:wiki.nixos.org)",
              "WebFetch(domain:search.nixos.org)"],
    "ask":   ["Bash(tea comment:*)", "Bash(tea issues close:*)", "Bash(tea issues edit:*)",
              "Bash(tea issues create:*)", "Bash(tea issues reopen:*)", "Bash(tea pr:*)"],
    "deny":  ["Bash(gh issue:*)", "Bash(gh pr:*)"]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/guard-bash.sh" }] }
    ]
  }
}
```

**`hooks/guard-bash.sh`**, in outline. It reads the tool call from stdin and
prints a JSON decision:
- **deny:**
  - every `git push`;
  - `gh` except read-only `run` / `release` / `api` GETs;
  - `--no-verify`;
  - `git commit` when the repository top level is `/home/tappaas/TAPPaaS`;
- **ask:** anything that changes `stable` (commit, merge, reset, branch
  move), and `git rebase` of a branch that already exists on a remote;
- **allow:** everything else.

**`githooks/commit-msg`**, in outline. It rejects a commit when:
- the subject is not `type(scope): summary` or is longer than 72 characters;
- the body is longer than 3 lines, not counting `close #N` lines;
- the message contains `Co-Authored-By: Claude` or "Generated with Claude".

**Native agent header** (example):

```markdown
---
name: site-operator
description: Run commands on a TAPPaaS site (hrossen or makerfloss) via its ssh alias and return a short summary. Read-only unless the task says otherwise. Use for any live inspection or test run so logs stay out of the main context.
tools: Bash, Read, Grep
model: sonnet
---
```

---

## 6. Rollout of this proposal

1. **Guardrails** (an hour): settings, guard hook, commit-msg hook via
   `link.sh`, clean `settings.local.json`, the CLAUDE.md git and forge
   sections. From here Claude can commit locally.
2. **Reach and tests**: ssh aliases, `SITES.md`, `tappaas-test.sh`, the
   `tappaas-test` skill, dev clones on both cicds.
3. **Agents**: native subagents per P6; retire `agents.md` routing.
4. **Wave driver**: `tappaas-wave` + updated `tappaas-issue`; pilot on G0.2.
5. **Pull hold** (TAPPaaS change, plan G0.3): once it lands, T3 needs no
   operator push.
6. **Staging** (later, if wanted).

Each step is useful on its own; stop after any of them.

## 7. Answers, and what is still open

1. **Staging** — later. Covered for now by P3a.
2. **Sites** — hrossen.dk is the test site; makerfloss stays on `main`.
3. **Pull and merge into `main`** — yes; pushing stays manual.
4. **`tea` on the cicds** — yes; added to `tappaas-cicd.nix` (uncommitted).
   Each cicd still needs `tea login add` with its own token.
5. **Gridtefy retro commands.** `retro` and `post-task-retro` are Erik's
   self-improvement loop for Gridtefy's AI "digital workers":
   - After a task, the agent writes a structured self-reflection (six
     reflection questions plus a scan of AI-automation building blocks)
     into a retro inbox.
   - A lint script checks the retro is complete.
   - A trigger counts signals across the inbox; at a threshold, a "retro
     sweep" turns them into changes to the agent setup.

   Here they cannot run: they call scripts and folders (`src/digital-org/…`,
   `src/skills/post-task-retro/…`) that exist only in Gridtefy's own repo.
   They are also marked "Proprietary — Gridtefy Ring-4, not for upstream
   donation" while tappaas-claude is public. **Proposal:** remove both from
   tappaas-claude after checking with Erik; he keeps them in his private
   layer.
6. **Public repo** — site facts go in `SITES.local.md`, gitignored.

Still open:
- **Access to makerfloss** without interactive sudo (P4): a `ProxyJump`
  path, or a sudoers rule you add yourself for the two tunnels.
- **Starting the rollout:** step 1 (guardrails) is ready to apply on your go.
