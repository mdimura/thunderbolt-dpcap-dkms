# thunderbolt-dpcap-dkms

A DKMS-built Linux `thunderbolt` driver with one extra module parameter,
`dp_max_bw`. It caps how much bandwidth a single DisplayPort tunnel may reserve.
Two monitors on one Thunderbolt 4 / USB4 dock then share the link fairly and
**both run at 4K@60 Hz on every boot**, whatever order the tunnels are set up in.

## Problem being solved

- Two 4K monitors on a TB4/USB4 dock with two DP outputs.
- After a boot (or a dock re-plug), one monitor is stuck at **4K@30 Hz**. Its
  4K@60 modes are missing entirely.
- Which monitor gets 60 Hz looks random.
- Unplugging and re-plugging the monitors in a particular order sometimes gives
  60 Hz on both, until the next reboot.

Seen with: Dell WD22TB4 dock, Alder Lake (Iris Xe) laptop, two Samsung
LU28R55 monitors on HDMI, kernel 7.2.14-arch1. Any host *without* USB4 DP
bandwidth allocation mode should be affected in the same way.

## Root cause

A TB4 link is 2 × 20 Gb/s. The driver reserves a 10% guard band, so
**36 000 Mb/s** is usable for tunnels. Without bandwidth allocation mode, DP
tunnels are sized once, when they are created:

1. At boot both DP tunnels are created back to back.
2. The first tunnel has not finished its DPRX capability read yet, so it is
   counted at the full DP IN/OUT capability: **HBR3 × 4 = 25 920 Mb/s**
   (`tb_dp_consumed_bandwidth()` in `drivers/thunderbolt/tunnel.c`).
3. The second tunnel gets the leftover, about 10 000 Mb/s, and is reduced to
   **HBR × 4 = 8 640 Mb/s**. 4K@60 at 8 bpc needs about 12 800 Mb/s, so the
   GPU only offers 30 Hz modes.
4. The first tunnel then settles at its real rate, e.g. HBR2 × 4 = 17 280 Mb/s.
   Nothing revisits the second tunnel: only a hardware hotplug rebuilds it.
   Suspend/resume restores the reduced cap.

Example `tbtunnels` output from the broken state:

```
Route 0 Adapter 5 ⇔ Route 3 Adapter 13: DisplayPort   Rate: 5400 Mb/s * 4   -> 60 Hz
Route 0 Adapter 6 ⇔ Route 3 Adapter 14: DisplayPort   Rate: 2700 Mb/s * 4   -> 30 Hz
USB 3 tunnel: Allocated 9003 Mb/s
```

Both tunnels at HBR2 × 4 (2 × 17 280 = 34 560 Mb/s) fit in the 36 000 Mb/s
budget. The bandwidth is there; it just isn't shared fairly.

## The fix

[`dp_max_bw.patch`](dp_max_bw.patch) adds the parameter:

```
thunderbolt.dp_max_bw=<Mb/s>   # 0 = no limit (default, stock behaviour)
```

`tb_tunnel_one_dp()` clamps the available bandwidth for each new DP tunnel to
this value. The tunnel then gets the fastest rate/lane combination that fits
under the cap. With `dp_max_bw=17280` every tunnel gets HBR2 × 4. That is
enough for one 4K@60 8 bpc stream, both SST (single-stream) and through a dock's
MST (multi-stream) hub, and two such tunnels fit on the link in either order.

### Choosing the value

| Cap (Mb/s) | Link per tunnel | Notes |
|---|---|---|
| 17280 | HBR2 × 4 | Default here. 4K@60 8 bpc; fits 2 tunnels + USB3 minimum (900 Mb/s) |
| 12960 | HBR3 × 2 | Only if *every* sink path supports HBR3; MST 4K@60 does **not** fit |
| 0 | unlimited | Stock behaviour |

There is about 540 Mb/s of slack with two 17280 tunnels. If USB3 traffic
through the dock is unusually heavy at the moment the second tunnel is set up,
that tunnel can still be reduced.

## Requirements

- Arch Linux, stock `linux` kernel (version string `X.Y.Z-archN-M`). At build
  time, `fetch-src.sh` downloads `drivers/thunderbolt` for the exact kernel tag
  from [archlinux/linux](https://github.com/archlinux/linux), so the build needs
  network access, including during kernel upgrades.
- `dkms`, `linux-headers`, `pahole` (`install.sh` installs them).
- Module signature enforcement / Secure Boot lockdown off. DKMS signs the
  module with its own self-signed key, and the kernel logs a (harmless) taint
  message.

Other distributions: change `fetch-src.sh` so it fetches the matching
`drivers/thunderbolt` sources for your kernel. The rest is distribution-agnostic
apart from the `pacman` line in `install.sh`.

## Install

```sh
git clone https://github.com/mdimura/thunderbolt-dpcap-dkms.git
cd thunderbolt-dpcap-dkms
sudo ./install.sh                 # or: sudo DP_MAX_BW=17280 ./install.sh
sudo reboot
```

`install.sh` copies the package to `/usr/src/thunderbolt-dpcap-1.0` and runs
`dkms install`. It writes `options thunderbolt dp_max_bw=…` to
`/etc/modprobe.d/thunderbolt-dpcap.conf` and regenerates the initramfs if
`thunderbolt` is in it. `--reload` tries to load the new driver without a
reboot, but that usually fails because `typec` holds the module.

The module is installed to `/usr/lib/modules/$(uname -r)/updates/dkms/`, which
takes priority over the stock one. DKMS rebuilds it on kernel upgrades. If the
patch stops applying to a new kernel, the build fails and the stock driver is
used, which brings the 30 Hz problem back.

## Verify

```sh
cat /sys/module/thunderbolt/parameters/dp_max_bw    # 17280
modinfo -n thunderbolt                              # .../updates/dkms/thunderbolt.ko.zst
sudo tbtunnels -d 0                                 # DP tunnels at 5400 Mb/s * 4
kscreen-doctor -o | grep -o '3840x2160@60[^ ]*'     # KDE; or check your DE's display settings
```

`diag.sh` (needs [tbtools](https://github.com/intel/tbtools)) collects
everything relevant: routers, adapters, tunnels, the DPCD link caps each GPU
port sees, i915 display state and the kernel log.

```sh
sudo ./diag.sh > diag.txt 2>&1
```

## Uninstall

```sh
sudo ./uninstall.sh && sudo reboot
```

## Upstream

The real fix belongs in the kernel. The driver could defer creating a DP tunnel
until pending DPRX reads complete, or re-balance reduced tunnels once they do.
Until then, this parameter is a small, opt-in workaround.

## License

Scripts and documentation: [0BSD](LICENSE). `dp_max_bw.patch` modifies GPL-2.0
kernel code and is [GPL-2.0-only](LICENSES/GPL-2.0-only.txt), as is the
resulting kernel module.
