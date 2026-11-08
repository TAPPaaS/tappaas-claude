#!/bin/sh
# tappaas-dev-bin.sh <checkout> — build a mothership-shaped bin directory for a
# TAPPaaS checkout on a dev machine and print its path.
#
# A mothership's /home/tappaas/bin holds symlinks into the repo (tappaas-cicd's
# install.sh: scripts/*.sh and lib/*.sh, then each manager/controller component's
# install.sh links its entry scripts). Scripts source
# "${TAPPAAS_BIN:-/home/tappaas/bin}/common-install-routines.sh" and test suites
# look their entry scripts up on PATH, so tappaas-env exports TAPPAAS_BIN to this
# directory and puts it first on PATH. Every component *.sh and extensionless
# executable is linked except the verb scripts (install/update/test/validate.sh):
# a superset of what the component install.sh files link. Nix-built
# TypeScript bins are not linked; suites that need them skip or fail as on a
# mothership without them.
#
# The directory is rebuilt on every call (a few hundred symlinks, well under a
# second) into ~/.tappaas/devenv/bin/<name>-<hash of the checkout path>, swapped
# in with a rename so a concurrent run never sees it half-built.
set -eu

top="$(cd "${1:?usage: tappaas-dev-bin.sh <checkout>}" && pwd -P)"
cicd="${top}/src/foundation/tappaas-cicd"
[ -f "${cicd}/lib/common-install-routines.sh" ] || {
    echo "tappaas-dev-bin: ${top} is not a TAPPaaS checkout" >&2; exit 1; }

root="${HOME}/.tappaas/devenv/bin"
key="$(printf '%s' "${top}" | shasum | cut -c1-8)"
dest="${root}/$(basename "${top}")-${key}"
mkdir -p "${root}"
new="$(mktemp -d "${dest}.new.XXXXXX")"

link() { ln -sfn "$1" "${new}/$(basename "$1")"; }
for f in "${cicd}"/scripts/*.sh "${cicd}"/lib/*.sh; do
    [ -f "${f}" ] && link "${f}"
done
for d in "${cicd}"/manager/*/ "${cicd}"/controller/*/; do
    for f in "${d}"*; do
        [ -f "${f}" ] || continue
        b="$(basename "${f}")"
        case "${b}" in install.sh|update.sh|test.sh|validate.sh) continue ;; esac
        # *.sh entry scripts, and executables without an extension (the bash
        # managers/controllers that link_component_executables links).
        case "${b}" in *.sh) ;; *.*) continue ;; *) [ -x "${f}" ] || continue ;; esac
        link "${f}"
    done
done

old="${dest}.old.$$"
[ -d "${dest}" ] && mv "${dest}" "${old}"
mv "${new}" "${dest}"
rm -rf "${old}"
echo "${dest}"
