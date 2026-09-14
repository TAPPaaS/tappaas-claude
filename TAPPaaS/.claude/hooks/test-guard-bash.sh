#!/usr/bin/env bash
# The test commands are literal strings for the guard to parse, $(...) included.
# shellcheck disable=SC2016
#
# test-guard-bash.sh — table test for guard-bash.py. Builds a throwaway repo with a
# fake remote so branch-dependent rules (stable, pushed commits) are exercised.
#
# Usage: ./test-guard-bash.sh
#
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${HERE}/guard-bash.py"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT INT TERM

pass=0; fail=0

# decision_for <cwd> <command> — prints deny|ask|none (GUARD_ARGS: e.g. "--scope tappaas")
GUARD_ARGS=""
decision_for() {
    # shellcheck disable=SC2086  # GUARD_ARGS is intentionally word-split
    python3 - "$1" "$2" <<'PY' | TAPPAAS_GUARD_MANAGED_CHECKOUT="${WORK}/managed" python3 "${GUARD}" ${GUARD_ARGS} \
        | python3 -c 'import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)["hookSpecificOutput"]["permissionDecision"] if d else "none")'
import json, sys
print(json.dumps({"tool_name": "Bash", "cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))
PY
}

expect() {
    local want="$1" cwd="$2" cmd="$3" got
    got="$(decision_for "${cwd}" "${cmd}")"
    if [[ "${got}" == "${want}" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: want %-4s got %-4s  %s  (cwd %s)\n' "${want}" "${got}" "${cmd}" "${cwd}"
    fi
}

# --- fixtures: origin (bare), a clone with main/stable/feature, a "managed" clone
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
g init --bare "${WORK}/origin.git"
g clone "${WORK}/origin.git" "${WORK}/repo"
R="${WORK}/repo"
g -C "${R}" commit --allow-empty -m "fix(x): first"
g -C "${R}" push origin main
g -C "${R}" branch stable && g -C "${R}" push origin stable
g -C "${R}" checkout -b pushed && g -C "${R}" push origin pushed
g -C "${R}" checkout -b local-only
g -C "${R}" commit --allow-empty -m "fix(x): local"
g clone "${WORK}/origin.git" "${WORK}/managed"
S="${WORK}/stable-wt"
g -C "${R}" worktree add "${S}" stable
P="${WORK}/pushed-wt"
g -C "${R}" worktree add "${P}" pushed
T="${WORK}/tappaas"     # a clone that also has a TAPPaaS remote
g clone "${WORK}/origin.git" "${T}" && g -C "${T}" remote add codeberg git@codeberg.org:TAPPaaS/TAPPaaS.git
O="${WORK}/other"       # an unrelated project
g init "${O}" && g -C "${O}" remote add origin https://github.com/someone/other.git

# --- push / no-verify / managed checkout
expect none "${R}" 'git status'
expect none "${R}" 'git log --grep push'
expect deny "${R}" 'git push'
expect deny "${R}" 'cd /tmp && git -C /tmp/x push origin main'
expect deny "${R}" 'echo $(git push)'
expect deny "${R}" 'FOO=1 sudo git push --force'
expect deny "${R}" 'git commit -m "fix: x" --no-verify'
expect deny "${R}" 'git commit -nm "fix: x"'
expect none "${R}" 'git commit -m "-n is just text"'
expect none "${R}" 'git commit -am "fix(x): y"'
expect deny "${R}" 'git push "unbalanced'
expect deny "${WORK}/managed" 'git commit -m "fix: x"'
expect deny "${R}" "cd ${WORK}/managed && git merge origin/main"
expect none "${WORK}/managed" 'git pull --ff-only'

# --- stable, tags, history rewrites
expect none "${R}" 'git checkout stable'
expect ask  "${R}" 'git branch -f stable main'
expect ask  "${R}" 'git switch -C stable'
expect ask  "${S}" 'git commit -m "fix: on stable"'
expect ask  "${S}" 'git merge main'
expect ask  "${R}" 'git tag -a v2.1 -m "TAPPaaS 2.1"'
expect none "${R}" 'git tag -l'
expect none "${R}" 'git rebase main'
expect ask  "${P}" 'git commit --amend --no-edit'
expect ask  "${P}" 'git rebase main'
expect none "${R}" 'git commit --amend --no-edit'
expect ask  "${R}" 'git reset --hard HEAD~1'
expect ask  "${R}" 'git clean -fd'
expect none "${R}" 'git merge local-only'

# --- gh (GitHub: read-only) and tea (Codeberg writes ask)
expect deny "${R}" 'gh issue comment 3 -b hi'
expect deny "${R}" 'gh pr list'
expect none "${R}" 'gh run list --limit 5'
expect none "${R}" 'gh release view nixos-template-v1.4'
expect none "${R}" 'gh api repos/TAPPaaS/TAPPaaS/releases/latest'
expect deny "${R}" 'gh api -X POST repos/x/y/issues'
expect deny "${R}" 'gh api repos/x/y/issues -f title=t'
expect deny "${R}" 'gh repo create x'
expect none "${R}" 'tea issues -R origin 376 --comments'
expect ask  "${R}" 'tea comment -R origin 376 "$(cat body.md)"'
expect ask  "${R}" 'cd /tmp && tea issues close -R origin 376'
expect none "${R}" "ssh tappaas@host 'cd ~/TAPPaaS && git status'"

# --- user-level hook (--scope tappaas): only TAPPaaS repositories are guarded
expect deny "${O}" 'git push'                     # project hook: every repo in scope
GUARD_ARGS="--scope tappaas"
expect deny "${T}" 'git push origin main'
expect deny "${T}" 'git commit -nm "fix: x"'
expect none "${O}" 'git push origin main'
expect none "${R}" 'git push'                     # remote is a local path, not TAPPaaS
expect deny "${O}" "cd ${T} && git push"
expect deny "${O}" "git -C ${T} push"
expect deny "${WORK}/managed" 'git commit -m "fix: x"'
expect deny "${T}" 'gh pr list'
expect none "${O}" 'gh pr view 3'
expect ask  /tmp   'tea comment -R origin 1 hi'
expect none /tmp   'git status'
GUARD_ARGS=""

printf '%d passed, %d failed\n' "${pass}" "${fail}"
[[ "${fail}" -eq 0 ]]
