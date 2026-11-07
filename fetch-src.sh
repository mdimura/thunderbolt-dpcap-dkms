#!/bin/bash
# SPDX-License-Identifier: 0BSD
# Download drivers/thunderbolt sources matching an Arch kernel release and apply dp_max_bw.patch.
# Usage: fetch-src.sh <kernelver>   (e.g. 7.2.14-arch1-1); run from the DKMS build directory.
set -euo pipefail
kver="$1"
here="$(cd "$(dirname "$0")" && pwd)"
cache=/var/cache/thunderbolt-dpcap

if [[ $kver =~ ^([0-9]+\.[0-9]+)\.([0-9]+)-arch([0-9]+)-[0-9]+$ ]]; then
    mm=${BASH_REMATCH[1]}; sub=${BASH_REMATCH[2]}; arel=${BASH_REMATCH[3]}
else
    echo "thunderbolt-dpcap: unsupported kernel version '$kver' (expected X.Y.Z-archN-M)" >&2
    exit 1
fi
tags=("v$mm.$sub-arch$arel")
[[ $sub == 0 ]] && tags=("v$mm-arch$arel" "${tags[@]}")

src="$here/src"
rm -rf "$src"; mkdir -p "$src"
ok=
for tag in "${tags[@]}"; do
    if [[ -s $cache/$tag/tb.c ]]; then
        cp -a "$cache/$tag/." "$src/"; ok=$tag; break
    fi
    list=$(curl -sfL --retry 3 "https://api.github.com/repos/archlinux/linux/contents/drivers/thunderbolt?ref=$tag" || true)
    [[ -n $list ]] || continue
    urls=$(python3 -c 'import sys,json; [print(x["download_url"]) for x in json.load(sys.stdin) if x["type"]=="file"]' <<<"$list")
    (cd "$src" && xargs -n8 curl -sfL --retry 3 --remote-name-all <<<"$urls")
    for u in $urls; do [[ -s $src/$(basename "$u") ]] || { echo "thunderbolt-dpcap: failed to fetch $u" >&2; exit 1; }; done
    mkdir -p "$cache/$tag"; cp -a "$src/." "$cache/$tag/"
    ok=$tag; break
done
[[ -n $ok ]] || { echo "thunderbolt-dpcap: could not obtain sources for ${tags[*]}" >&2; exit 1; }

echo "thunderbolt-dpcap: using archlinux/linux $ok"
patch -d "$src" -p3 --forward --dry-run < "$here/dp_max_bw.patch" >/dev/null
patch -d "$src" -p3 --forward < "$here/dp_max_bw.patch"
