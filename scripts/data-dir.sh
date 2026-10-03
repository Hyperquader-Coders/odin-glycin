#!/usr/bin/env bash
# Make the GLYCIN_DATA_DIR the tests use: a copy of the staged loader configs with Exec=
# rewritten from the install directory to the staged one, so the loaders run from the stage
# without being installed.
#   scripts/data-dir.sh <stage-lib-dir> <install-dir> <out-dir>
set -euo pipefail

lib=${1:?usage: data-dir.sh <stage-lib-dir> <install-dir> <out-dir>}
install=${2:?usage: data-dir.sh <stage-lib-dir> <install-dir> <out-dir>}
out=${3:?usage: data-dir.sh <stage-lib-dir> <install-dir> <out-dir>}
lib=$(cd "$lib" && pwd)

rm -rf "$out"
mkdir -p "$out/glycin-loaders/2+/conf.d"
for conf in "$lib"/share/glycin-loaders/2+/conf.d/*.conf; do
    sed "s|^Exec *= *$install|Exec=$lib|" "$conf" >"$out/glycin-loaders/2+/conf.d/$(basename "$conf")"
done
