#!/usr/bin/env bash
# cpe-enrich.sh <in.cdx.json> <out.cdx.json>
# Replace each component's naive vendor=name CPE with the one the MOTHERSHIP's
# nixpkgs declares (meta.identifiers.cpeParts) — same estate pin as every guest,
# so the identity is exact. Components nixpkgs gives no CPE keep the naive one.
set -euo pipefail
in="$1"; out="$2"; cache=$(mktemp); trap 'rm -f "$cache"' EXIT
names=$(jq -c '[.components[].name]|unique' "$in")
nix-instantiate --eval --strict --json -E "
  let pkgs = import <nixpkgs> {}; names = builtins.fromJSON ''${names}'';
      look = n: let r = builtins.tryEval (
                  let p = pkgs.\${n} or null; in
                  if p == null then null else (p.meta.identifiers.cpeParts or null));
                in if r.success then r.value else null;
  in builtins.listToAttrs (map (n: { name = n; value = look n; }) names)
" > "$cache" 2>/dev/null
jq --slurpfile cp "$cache" '
  .components |= map(
    . as $c | ($cp[0][$c.name]) as $p |
    if $p != null and ($p.vendor // null) != null
    then .cpe = "cpe:2.3:a:\($p.vendor):\($p.product // $c.name):\($c.version):*:*:*:*:*:*:*"
       | .properties = [{name:"tappaas:cpe-source", value:"nixpkgs-meta"}]
    else .properties = [{name:"tappaas:cpe-source", value:"naive"}] end)' "$in" > "$out"
echo "cpe-enrich: $(jq '[.components[]|select(.properties[0].value=="nixpkgs-meta")]|length' "$out") of $(jq '.components|length' "$out") from nixpkgs meta" >&2
