#!/usr/bin/env bash
# sbom-dryrun.sh — DRY RUN of the ADR-011 v0.3 pipeline on one installation.
#
# Read-only against every target. Inventories each layer with the tool the ADR
# proposes for it, matches against that layer's CVE source, then applies the two
# rules the measurements forced:
#
#   COVERAGE  a scan that saw no packages is a FAILURE, never a clean result
#             (trivy without /etc/debian_version, OSV on pkg:nix purls — both
#             reported "0 vulnerabilities" on 2026-09-27 having scanned nothing)
#   ACTION    the metric is "fix available and not applied", not CVE count
#
# Runs on the mothership as tappaas. Output: one line per target + summary.json.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-/tmp/sbom-dryrun/$(date +%Y%m%dT%H%M)}"; mkdir -p "$OUT"; cd "$OUT"
declare -a ROWS=()

row() {  # target kind seen coverage total crit high fixable crithi_fix verdict
    ROWS+=("$(jq -nc --arg t "$1" --arg k "$2" --argjson s "$3" --arg c "$4" \
        --argjson n "$5" --argjson cr "$6" --argjson hi "$7" --arg fx "$8" --arg chf "$9" --arg v "${10}" \
        '{target:$t,kind:$k,seen:$s,coverage:$c,findings:$n,critical:$cr,high:$hi,fixable:$fx,crit_high_fixable:$chf,verdict:$v}')")
    printf '  %-26s %-9s seen=%-4s cov=%-4s findings=%-5s crit=%-3s high=%-4s fixable=%-8s crit/high-fixable=%-6s %s\n' "$@"
}

# ── Nix closures: runtime path list → paths2cdx → cpe-enrich (vendor from the
# estate's own nixpkgs pin) → grype. One method for mothership and guests: a
# guest only lists its closure, nothing is installed there.
# grype grype has no fix-state for
# nix, so these land in TRIAGE, never in "fixable" — honest about what we know.
nix_target() {  # name path-list-file
    local n="$1" cdx seen cov g; cdx="$n.cdx.json"
    python3 "$HERE/paths2cdx.py" < "$2" > "$n.raw.cdx.json" 2>/dev/null
    bash "$HERE/cpe-enrich.sh" "$n.raw.cdx.json" "$cdx" 2>/dev/null
    seen=$(jq '.components|length' "$cdx" 2>/dev/null || echo 0)
    if (( seen >= 50 )) && jq -e '.components[]|select(.name=="glibc")' "$cdx" >/dev/null 2>&1; then cov=ok; else cov=FAIL; fi
    g="$n.grype.json"
    nix-shell -p grype --run "grype sbom:$cdx -o json --file $g -q" 2>/dev/null
    local tot cr hi
    tot=$(jq '[.matches[].vulnerability.id]|unique|length' "$g" 2>/dev/null || echo 0)
    cr=$(jq '[.matches[]|select(.vulnerability.severity=="Critical")|.vulnerability.id]|unique|length' "$g")
    hi=$(jq '[.matches[]|select(.vulnerability.severity=="High")|.vulnerability.id]|unique|length' "$g")
    local v="triage (nix: CPE-only, no fix-state)"; [[ $cov == FAIL ]] && v="SCAN FAILED — not clean"
    row "$n" nix "$seen" "$cov" "$tot" "$cr" "$hi" "unknown" "unknown" "$v"
}

# ── Image / Debian: trivy, which carries distro fix-state.
trivy_target() {  # name kind trivy-json
    local n="$1" k="$2" j="$3" fam seen cov tot cr hi fx chf v
    fam=$(jq -r '.Metadata.OS.Family // "none"' "$j" 2>/dev/null)
    seen=$(jq '[.Results[]?.Packages[]?]|length' "$j" 2>/dev/null || echo 0)
    if [[ $fam != none ]] && (( seen > 0 )); then cov=ok; else cov=FAIL; fi
    tot=$(jq '[.Results[]?.Vulnerabilities[]?.VulnerabilityID]|unique|length' "$j")
    cr=$(jq '[.Results[]?.Vulnerabilities[]?|select(.Severity=="CRITICAL")|.VulnerabilityID]|unique|length' "$j")
    hi=$(jq '[.Results[]?.Vulnerabilities[]?|select(.Severity=="HIGH")|.VulnerabilityID]|unique|length' "$j")
    fx=$(jq '[.Results[]?.Vulnerabilities[]?|select((.FixedVersion//"")!="")|.VulnerabilityID]|unique|length' "$j")
    chf=$(jq '[.Results[]?.Vulnerabilities[]?|select((.FixedVersion//"")!="" and (.Severity=="CRITICAL" or .Severity=="HIGH"))|.VulnerabilityID]|unique|length' "$j")
    if [[ $cov == FAIL ]]; then v="SCAN FAILED — not clean"
    elif (( chf > 0 )); then v="ACT: $chf critical/high fixable"
    elif (( fx > 0 )); then v="act (low/medium only)"
    else v="nothing actionable — watch"; fi
    row "$n" "$k" "$seen" "$cov" "$tot" "$cr" "$hi" "$fx" "$chf" "$v"
}

echo "== dry run → $OUT"

# 1. mothership closure
nix-store -q --requisites "$(readlink -f /run/current-system)" > mothership.paths
nix_target mothership mothership.paths

# 2. a guest closure: the guest only LISTS it (read-only, nothing installed)
ssh -n -o BatchMode=yes "tappaas@${GUEST_IP:-10.0.0.181}" 'nix-store -q --requisites /run/current-system' > identity.paths 2>/dev/null
nix_target identity identity.paths

# 2b. a guest that could not be reached — the coverage rule must catch it
: > unreachable.paths
nix_target unreachable-guest unreachable.paths

# 3. the image as RUNNING, by digest — not by tag
DIG="${AUTHENTIK_DIGEST:-sha256:dc07e81b4462a1dad9c6720f4c73993e37d7cb2d2f94a306187318704d112e71}"
nix-shell -p trivy --run "trivy image --quiet --scanners vuln --list-all-pkgs --format json --output authentik.trivy.json ghcr.io/goauthentik/server@$DIG" 2>/dev/null
trivy_target "authentik (image@digest)" image authentik.trivy.json

# 4. a PVE node — only its package list is copied; nothing on the node changes
R=pve-root; mkdir -p $R/etc $R/var/lib/dpkg
for f in etc/os-release etc/debian_version var/lib/dpkg/status; do scp -q "root@tappaas1.mgmt.internal:/$f" "$R/$f" 2>/dev/null; done
nix-shell -p trivy --run "trivy rootfs --quiet --scanners vuln --list-all-pkgs --format json --output pve.trivy.json $R" 2>/dev/null
trivy_target "tappaas1 (debian)" debian pve.trivy.json

# 4b. the same node with the file the detector needs REMOVED — the coverage rule must catch it
rm -f $R/etc/debian_version
nix-shell -p trivy --run "trivy rootfs --quiet --scanners vuln --list-all-pkgs --format json --output pve-broken.trivy.json $R" 2>/dev/null
trivy_target "tappaas1 NO debian_version" debian pve-broken.trivy.json

# 5. OPNsense — its own scanner. "fixable" here means: does the channel offer an update?
FW=10.0.0.1
aud=$(ssh -n -o BatchMode=yes root@$FW 'sh -c "pkg audit 2>/dev/null"' 2>/dev/null)
pk=$(ssh -n -o BatchMode=yes root@$FW 'sh -c "pkg info | wc -l"' 2>/dev/null | tr -d ' ')
tot=$(awk '/CVE:/{print $2}' <<<"$aud" | sort -u | wc -l | tr -d ' ')
upd=$(ssh -n -o BatchMode=yes root@$FW 'sh -c "configctl firmware status"' 2>/dev/null | grep -c "up to da")
cov=ok; (( ${pk:-0} > 0 )) || cov=FAIL
v="waiting on upstream (channel current)"; (( upd > 0 )) || v="ACT: firmware update available"
row "firewall (opnsense)" freebsd "${pk:-0}" "$cov" "$tot" 0 0 "via-channel" "-" "$v"

printf '%s\n' "${ROWS[@]}" | jq -s '.' > summary.json
echo "== summary.json written ($(jq length summary.json) targets)"
