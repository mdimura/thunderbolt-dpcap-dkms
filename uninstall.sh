#!/bin/bash
# SPDX-License-Identifier: 0BSD
# Remove the thunderbolt-dpcap DKMS module and its config (stock driver is used after reboot). Run as root.
set -euo pipefail
dkms remove thunderbolt-dpcap/1.0 --all || true
rm -rf /usr/src/thunderbolt-dpcap-1.0 /var/cache/thunderbolt-dpcap
rm -f /etc/modprobe.d/thunderbolt-dpcap.conf
depmod -a
echo "Removed. Reboot to load the stock thunderbolt driver."
