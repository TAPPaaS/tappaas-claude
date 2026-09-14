#!/usr/bin/env bash
#
# tappaas-test.sh — run TAPPaaS tests on a site's cicd from any dev machine.
#
# Usage: tappaas-test.sh <site> [options] <target>...
#   site          hrossen | makerfloss   (ssh aliases cicd-<site>, see SITES.local.md)
#   target        repo path containing a test.sh  -> run from a synced scratch copy
#                 module:<name>                   -> test-module.sh on the site's INSTALLED code
# Options:
#   --deep            deep tiers (TAPPAAS_TEST_DEEP=1 / test-module.sh --deep)
#   --allow-canary-deep  permit --deep on makerfloss (deep tiers can create fixture VMs)
#   --repo DIR        repository to sync (default: git top level of $PWD, else ~/src/TAPPaaS)
#   --no-sync         reuse the scratch copy from the previous run of this branch
#   --keep N          scratch copies kept on the site (default 3)
#   -h, --help        this help
#
# The scratch copy lives in ~/dev/scratch/<branch> on the cicd and holds the tracked and
# untracked (not ignored) files of the working tree — unpushed work included, nothing
# committed or pushed anywhere. Scripts that honour TAPPAAS_CICD_DIR use the scratch copy;
# anything calling /home/tappaas/bin/* still runs the site's installed code.
#
# Output: ~/src/tappaas-claude/logs/<site>-<timestamp>.log; a PASS/FAIL line per target.
# Exit code: the worst exit code of all targets (test.sh convention: 1 fail, 2 fatal).
#
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SELF_DIR
readonly LOG_DIR="${SELF_DIR}/../logs"
readonly WG="${HOME}/bin/tappaas-wg.sh"

info()  { printf '[tappaas-test] %s\n' "$*" >&2; }
die()   { printf '[tappaas-test] ERROR: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

TMP_LIST=""
# shellcheck disable=SC2329  # called by the trap
cleanup() { [[ -n "${TMP_LIST}" ]] && rm -f "${TMP_LIST}"; return 0; }
trap cleanup EXIT INT TERM

# --- arguments -------------------------------------------------------------------
[[ $# -ge 1 ]] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac
SITE="$1"; shift
DEEP=0; CANARY_DEEP=0; SYNC=1; KEEP=3; REPO=""
TARGETS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deep)              DEEP=1; shift ;;
        --allow-canary-deep) CANARY_DEEP=1; shift ;;
        --no-sync)           SYNC=0; shift ;;
        --keep)              KEEP="${2:?--keep needs a number}"; shift 2 ;;
        --repo)              REPO="${2:?--repo needs a directory}"; shift 2 ;;
        -h|--help)           usage; exit 0 ;;
        -*)                  die "unknown option: $1 (see --help)" ;;
        *)                   TARGETS+=("$1"); shift ;;
    esac
done
[[ ${#TARGETS[@]} -gt 0 ]] || die "no targets given (see --help)"
for t in "${TARGETS[@]}"; do
    [[ "${t}" =~ ^(module:)?[A-Za-z0-9._/-]+$ ]] || die "unsafe target name: ${t}"
done
[[ "${KEEP}" =~ ^[0-9]+$ ]] || die "--keep must be a number"

case "${SITE}" in
    hrossen)    ALIAS="cicd-hrossen" ;;
    makerfloss) ALIAS="cicd-makerfloss"
                [[ "${DEEP}" -eq 0 || "${CANARY_DEEP}" -eq 1 ]] ||
                    die "makerfloss is the canary: --deep needs --allow-canary-deep (deep tiers can create fixture VMs)" ;;
    *)          die "unknown site '${SITE}' (hrossen | makerfloss)" ;;
esac

if [[ -z "${REPO}" ]]; then
    REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "${REPO}" ]] || REPO="${HOME}/src/TAPPaaS"
fi
[[ -d "${REPO}/.git" || -f "${REPO}/.git" ]] || die "not a git checkout: ${REPO}"
BRANCH="$(git -C "${REPO}" rev-parse --abbrev-ref HEAD)"
SLUG="$(printf '%s' "${BRANCH}" | tr -c 'A-Za-z0-9._-' '_')"
SCRATCH="dev/scratch/${SLUG}"   # relative to the remote home

# --- reach the site ---------------------------------------------------------------
if [[ "${SITE}" == makerfloss ]] && ! "${WG}" status 2>/dev/null | grep -q 'UP: *tappaas-mf'; then
    info "bringing up the makerfloss tunnel"
    "${WG}" makerfloss.eu >/dev/null
fi
ssh -o BatchMode=yes -o ConnectTimeout=10 "${ALIAS}" true || die "cannot reach ${ALIAS}"

mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/${SITE}-$(date +%Y%m%d-%H%M%S).log"

# --- sync the working tree ----------------------------------------------------------
needs_scratch=0
for t in "${TARGETS[@]}"; do [[ "${t}" == module:* ]] || needs_scratch=1; done

if [[ "${needs_scratch}" -eq 1 && "${SYNC}" -eq 1 ]]; then
    TMP_LIST="$(mktemp)"
    ( cd "${REPO}" && comm -23 <(git ls-files -co --exclude-standard | sort) <(git ls-files -d | sort) ) > "${TMP_LIST}"
    info "syncing $(wc -l < "${TMP_LIST}" | tr -d ' ') files of ${BRANCH} to ${ALIAS}:~/${SCRATCH}"
    ( cd "${REPO}" && COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf - -T "${TMP_LIST}" 2>/dev/null ) |
        ssh -o BatchMode=yes "${ALIAS}" "rm -rf ~/${SCRATCH} && mkdir -p ~/${SCRATCH} && tar xzf - -C ~/${SCRATCH} \
            && git -C ~/TAPPaaS rev-parse --short HEAD > ~/${SCRATCH}/.installed-head \
            && cd ~/dev/scratch && ls -1t | tail -n +$((KEEP + 1)) | xargs -r rm -rf"
fi

# --- run the targets ----------------------------------------------------------------
# The generated script is meant to expand on the site, hence the single quotes.
# shellcheck disable=SC2016
remote_script() {
    local q_scratch q_deep
    q_scratch="$(printf '%q' "${SCRATCH}")"; q_deep="$(printf '%q' "${DEEP}")"
    printf 'set -u\nSCRATCH=~/%s\nDEEP=%s\n' "${q_scratch}" "${q_deep}"
    printf 'export TAPPAAS_CICD_DIR="$SCRATCH/src/foundation/tappaas-cicd"\n'
    printf '[ "$DEEP" = 1 ] && export TAPPAAS_TEST_DEEP=1\n'
    local t q
    for t in "${TARGETS[@]}"; do
        q="$(printf '%q' "${t}")"
        if [[ "${t}" == module:* ]]; then
            printf 'echo "@@BEGIN %s"; rc=0; /home/tappaas/bin/test-module.sh $( [ "$DEEP" = 1 ] && echo --deep ) %q </dev/null || rc=$?; echo "@@RC %s $rc"\n' \
                "${q}" "${t#module:}" "${q}"
        else
            printf 'echo "@@BEGIN %s"; rc=0; if [ -f "$SCRATCH/%s/test.sh" ]; then (cd "$SCRATCH/%s" && bash ./test.sh </dev/null) || rc=$?; else echo "no test.sh in %s"; rc=2; fi; echo "@@RC %s $rc"\n' \
                "${q}" "${t}" "${t}" "${q}" "${q}"
        fi
    done
}

info "running ${#TARGETS[@]} target(s) on ${ALIAS}$( [[ "${DEEP}" -eq 1 ]] && echo ' (deep)' ) — log: ${LOG}"
remote_script | ssh -o BatchMode=yes "${ALIAS}" 'bash -s' > "${LOG}" 2>&1 || true

# --- summarize ----------------------------------------------------------------------
worst=0
for t in "${TARGETS[@]}"; do
    rc="$(grep -F "@@RC ${t} " "${LOG}" | tail -1 | awk '{print $NF}')"
    [[ -n "${rc}" ]] || rc=2
    if [[ "${rc}" -eq 0 ]]; then
        printf 'PASS  %s\n' "${t}"
    else
        printf 'FAIL  %s (exit %s)\n' "${t}" "${rc}"
        { grep -F -A200 "@@BEGIN ${t}" "${LOG}" | sed -n '2,200p' |
            grep -E -i '✗|fail|error|fatal|no test.sh' | grep -v '@@' | head -8 | sed 's/^/      /'; } || true
    fi
    [[ "${rc}" -gt "${worst}" ]] && worst="${rc}"
done
printf 'log: %s\n' "${LOG}"
exit "${worst}"
