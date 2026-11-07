#!/bin/bash
# SPDX-License-Identifier: 0BSD
# Read-only Thunderbolt / DP tunnel diagnostics (needs tbtools). Run: sudo ./diag.sh > diag.txt 2>&1
echo "=== tblist";      tblist -Av
echo "=== tbadapters host router"; tbadapters -d 0 -r 0 -v 2>/dev/null || tbadapters -d 0 -r 0
echo "=== tbadapters dock router"; tbadapters -d 0 -r 3 -v 2>/dev/null || tbadapters -d 0 -r 3
echo "=== tbtunnels";   tbtunnels -d 0 -v 2>/dev/null || tbtunnels -d 0
echo "=== DPCD max link rate/lanes as seen by GPU (0x0001,0x0002) + trained (0x0100,0x0101)"
for a in /dev/drm_dp_aux*; do
  n=$(cat /sys/class/drm_dp_aux_dev/$(basename $a)/name 2>/dev/null)
  caps=$(dd if=$a bs=1 skip=1 count=2 2>/dev/null | od -An -tx1)
  trn=$(dd if=$a bs=1 skip=256 count=2 2>/dev/null | od -An -tx1)
  echo "$a [$n] max:$caps trained:$trn"
done
echo "=== i915_display_info"; cat /sys/kernel/debug/dri/*/i915_display_info 2>/dev/null
echo "=== dri debugfs DP entries"; ls /sys/kernel/debug/dri/*/ 2>/dev/null | grep -Ei 'dp|tunnel'
echo "=== kernel log (thunderbolt / i915 DP)"; journalctl -k -b --no-pager | grep -Ei 'thunderbolt|tunnel|i915.*(dp|link|mst)' | tail -80
