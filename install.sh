#!/bin/bash
# SPDX-License-Identifier: 0BSD
# Install the thunderbolt-dpcap DKMS module (Arch Linux). Run as root.
#   DP_MAX_BW=<Mb/s>  per-tunnel cap written to modprobe.d (default 17280 = HBR2 x4)
#   --reload          try to reload the thunderbolt driver right away (often fails
#                     because typec holds it; reboot instead)
set -euo pipefail
DP_MAX_BW=${DP_MAX_BW:-17280}
here="$(cd "$(dirname "$0")" && pwd)"
kver=$(uname -r)

echo "== packages"; pacman -S --needed --noconfirm dkms linux-headers pahole
echo "== dkms";
dkms remove thunderbolt-dpcap/1.0 --all >/dev/null 2>&1 || true
rm -rf /usr/src/thunderbolt-dpcap-1.0
install -d /usr/src/thunderbolt-dpcap-1.0
install -m644 "$here/dkms.conf" "$here/dp_max_bw.patch" /usr/src/thunderbolt-dpcap-1.0/
install -m755 "$here/fetch-src.sh" /usr/src/thunderbolt-dpcap-1.0/
dkms install thunderbolt-dpcap/1.0 -k "$kver" || { cat /var/lib/dkms/thunderbolt-dpcap/1.0/build/make.log 2>/dev/null | tail -40; exit 1; }

echo "== modprobe option"
echo "options thunderbolt dp_max_bw=$DP_MAX_BW" > /etc/modprobe.d/thunderbolt-dpcap.conf
echo "module file: $(modinfo -n thunderbolt)"; modinfo -p thunderbolt | grep dp_max_bw

if lsinitcpio /boot/initramfs-linux.img 2>/dev/null | grep -q 'thunderbolt'; then
    echo "== thunderbolt is in initramfs, regenerating"; mkinitcpio -P
else
    echo "== thunderbolt not in initramfs, nothing to regenerate"
fi

if [[ ${1:-} == --reload ]]; then
    echo "== reloading thunderbolt driver"
    modprobe -r thunderbolt_net thunderbolt_stream thunderbolt 2>&1 || true
    modprobe thunderbolt
    sleep 20
    echo "dp_max_bw now: $(cat /sys/module/thunderbolt/parameters/dp_max_bw)"
    tbtunnels -d 0
fi
