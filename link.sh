#!/usr/bin/env bash
#
# link.sh — (re)create the symlinks that wire this private Claude config into the
# TAPPaaS Codeberg repos, and ensure git never tracks them. Idempotent.
#
# Usage: ./link.sh [--repos-root DIR] [--dry-run] [-h|--help]
#   --repos-root DIR  Parent dir holding the repo checkouts (default: this dir's parent)
#   --dry-run         Print actions without changing anything
#
set -euo pipefail

# --- logging -----------------------------------------------------------------
log()  { printf '%s\n' "$*"; }
info() { log "[info]  $*"; }
warn() { log "[warn]  $*" >&2; }
error(){ log "[error] $*" >&2; }
die()  { error "$*"; exit 1; }

# --- config ------------------------------------------------------------------
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOS_ROOT="$(dirname -- "$SELF_DIR")"   # default: sibling of tappaas-claude
DRY_RUN=0

# Per-repo link map: "<repo>|<relative-path-in-repo>[|<relative-path-in-repo>...]"
# The source is always $SELF_DIR/<repo>/<relative-path>.
LINKS=(
  "TAPPaaS|CLAUDE.md|.claude/agents|.claude/commands|.claude/skills|.claude/settings.json"
  "Documentation|CLAUDE.md|.claude/agents|.claude/commands"
)

usage() { sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- args --------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos-root) REPOS_ROOT="${2:?--repos-root needs a value}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1 (see --help)" ;;
  esac
done

run() { if (( DRY_RUN )); then log "  would: $*"; else "$@"; fi; }

# --- link one repo -----------------------------------------------------------
link_repo() {
  local repo="$1"; shift
  local repo_dir="$REPOS_ROOT/$repo"
  local src_root="$SELF_DIR/$repo"

  [[ -d "$repo_dir" ]] || { warn "repo not found, skipping: $repo_dir"; return 0; }
  info "linking $repo"

  local rel src dst
  for rel in "$@"; do
    src="$src_root/$rel"
    dst="$repo_dir/$rel"
    [[ -e "$src" ]] || { warn "  source missing, skipping: $src"; continue; }
    run mkdir -p "$(dirname -- "$dst")"
    # Replace an existing correct/incorrect symlink; never clobber a real file/dir.
    if [[ -L "$dst" ]]; then
      run rm -f "$dst"
    elif [[ -e "$dst" ]]; then
      warn "  real file/dir in the way, NOT overwriting: $dst"; continue
    fi
    run ln -s "$src" "$dst"
    log "  linked $rel -> $src"
  done

  # Keep git from ever tracking the linked paths (local, never-pushed exclude).
  local excl="$repo_dir/.git/info/exclude"
  if [[ -d "$repo_dir/.git" ]]; then
    # Match any prior block (manual or scripted) so re-runs don't append duplicates.
    if ! grep -qF "Local Claude Code config" "$excl" 2>/dev/null; then
      local marker="# Local Claude Code config (symlinked to tappaas-claude; never committed)"
      run bash -c "printf '\n%s\nCLAUDE.md\n.claude/\n' \"$marker\" >> \"$excl\""
      log "  added excludes to $excl"
    fi
  fi
}

# --- main --------------------------------------------------------------------
info "repos root: $REPOS_ROOT"
(( DRY_RUN )) && info "dry-run: no changes will be made"
for entry in "${LINKS[@]}"; do
  IFS='|' read -r repo rest <<<"$entry"
  IFS='|' read -r -a paths <<<"$rest"
  link_repo "$repo" "${paths[@]}"
done
info "done"
