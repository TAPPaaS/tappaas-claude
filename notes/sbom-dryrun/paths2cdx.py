#!/usr/bin/env python3
"""paths2cdx.py — a CycloneDX 1.4 SBOM from a Nix runtime-closure path list.

The zero-install guest method for ADR-011 v0.3. A guest runs only
`nix-store -q --requisites /run/current-system` (already present on every NixOS
guest); the list is carried to the mothership, which does everything else.

Store paths are <hash>-<pname>-<version>[-<output>]. The version starts at the
first dash-separated segment beginning with a digit — the same split nixpkgs'
own `builtins.parseDrvName` makes. Paths with no version (etc, firmware,
generated units) carry no identity a CVE database could match and are dropped,
and counted, so the coverage check can see how much was lost.

CPE vendor defaults to the product name — a placeholder; cpe-enrich.sh then
replaces it with the vendor nixpkgs declares (meta.identifiers.cpeParts).
"""
import json, re, sys, uuid

OUTPUTS = {"bin", "lib", "dev", "out", "man", "doc", "info", "debug", "static", "data", "dist", "py"}

def parse(path):
    base = path.rstrip("/").rsplit("/", 1)[-1]
    m = re.match(r"^[0-9a-z]{32}-(.+)$", base)
    if not m:
        return None
    parts = m.group(1).split("-")
    if parts and parts[-1] in OUTPUTS:
        parts = parts[:-1]
    for i, p in enumerate(parts):
        if i > 0 and p[:1].isdigit():
            ver = parts[i:]
            # a split output rides after the version (glibc-2.42-84-getent,
            # util-linux-2.42.3-swap): trailing segments that are not numeric
            # belong to the output name, not the version
            while len(ver) > 1 and not ver[-1][:1].isdigit():
                ver = ver[:-1]
            return "-".join(parts[:i]), "-".join(ver)
    return None

comps, dropped, seen = [], 0, set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    pv = parse(line)
    if not pv:
        dropped += 1
        continue
    name, ver = pv
    if (name, ver) in seen:
        continue
    seen.add((name, ver))
    comps.append({
        "type": "library", "name": name, "version": ver,
        "purl": f"pkg:nix/{name}@{ver}",
        "cpe": f"cpe:2.3:a:{name}:{name}:{ver}:*:*:*:*:*:*:*",
    })

# dbus-1, gtk-3.0: an API-level directory name, not a release. Drop a bare
# integer version when the same package also appears with a dotted one.
dotted = {c["name"] for c in comps if "." in c["version"]}
before = len(comps)
comps = [c for c in comps if not (c["version"].isdigit() and c["name"] in dotted)]
dropped += before - len(comps)

json.dump({
    "bomFormat": "CycloneDX", "specVersion": "1.4",
    "serialNumber": f"urn:uuid:{uuid.uuid4()}", "version": 1,
    "metadata": {"properties": [{"name": "tappaas:dropped-unversioned", "value": str(dropped)}]},
    "components": comps,
}, sys.stdout, indent=1)
print(f"paths2cdx: {len(comps)} components, {dropped} unversioned paths dropped", file=sys.stderr)
