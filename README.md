# Versal AI Edge VD100 — AIE-ML v2 Pipeline + XRT + Ethereum

Custom Yocto Linux on the Alinx VD100 (XCVE2302-SFVA784-1LP-E-S) — AIE-ML v2 moving average crossover pipeline via XRT, with trading signals logged on-chain to an Ethereum smart contract on a local Hardhat node.

> No VCK190. No MATLAB. No Simulink. Bare-metal VHDL, a UART, and a debugger's mindset.

---

## The Platform

```
vd100-aie-pipeline (Vitis 2025.2)
    └─ vd100_ma_system_project → aie.xclbin + aie.merged.cdo.bin
        └─ sdtgen set_dt_param -zocl enable → System Device Tree (vd100_dts)
            └─ Yocto Scarthgap + meta-vd100_v3
                └─ VD100 Linux 1.0 + XRT 2025.2 + zocl
                    ├─ PLM → U-Boot → systemd-boot → Linux
                    ├─ BOOT.BIN — includes aie_dev_part + aie_image CDOs
                    │   └─ xilinx-bootbin bbappend — injects AIE partitions
                    ├─ zocl.ko → AIE-ML v2 runtime driver
                    ├─ XRT → /opt/xilinx/xrt/
                    ├─ vd100-ps-ma-client → MA crossover via AIE (XRT, batch)
                    │   └─ golden test vector → BUY/SELL/HOLD validated on hardware
                    ├─ vd100-ma-trading-signal → live Binance feed → signal → Hardhat
                    │   ├─ SW mode: A72 MA crossover (~1440ns per block)
                    │   ├─ AIE mode: XRT pipeline (integrated, benchmarked)
                    │   └─ BUY/SELL → TradingSignalLog.sol (JSON-RPC → Hardhat)
                    └─ Ethernet, USB, I2C, GPIO, Sysmon (inherited from v2)
```

---

## What's New in v3

| Feature | v1 | v2 | v3 |
|---------|----|----|-----|
| Cold boot → Linux login | Y | Y | Y |
| Ethernet, USB, SSH | Y | Y | Y |
| I2C, LM75, EEPROM, sysmon | — | Y | Y |
| PS_LED / PL LED / PS_KEY IRQ | — | Y | Y |
| XRT 2025.2 runtime | — | — | Y |
| zocl kernel driver | — | — | Y |
| AIE-ML v2 pipeline (BOOT.BIN CDOs) | — | — | Y |
| `vd100-ps-ma-client` XRT app (batch) | — | — | Y |
| `vd100-ma-trading-signal` (live Binance feed) | — | — | Y |
| BOOT.BIN bbappend (aie_dev_part + aie_image) | — | — | Y |
| Ethereum JSON-RPC signal logging | — | — | Y |

---

## Dependencies — vd100-aie-pipeline

This layer depends on artifacts produced by the
[vd100-aie-pipeline](https://github.com/adilsondias-engineer/vd100-aie-pipeline)
Vitis project. Before building, ensure the following are available:

| Artifact | Source (vd100-aie-pipeline) | Destination (meta-vd100_v3) |
|----------|----------------------------|-----------------------------|
| `aie.merged.cdo.bin` | `vd100_ma_system_project/build/hw/package/` | `recipes-bsp/bootbin/files/` |
| `aie.cdo.device.partition.reset.bin` | `vd100_ma_system_project/build/hw/package/libadf/sw/` | `recipes-bsp/bootbin/files/` |
| `aie.xclbin` | `vd100_ma_system_project/build/hw/binary_container_1.xclbin` | deployed to VD100 manually |
| SDT (with zocl) | `sdtgen set_dt_param -zocl enable` | `recipes-bsp/device-tree/` |

> **xclbin is not packaged by Yocto.** Deploy it manually after each system project rebuild:
> ```bash
> scp aie.xclbin root@vd100:~/files/build/
> ```

---

## Repository Structure

| Path | Contents |
|------|----------|
| `conf/` | Distro config (`vd100.conf`) — requires `amd-edf.conf` |
| `recipes-bsp/bootbin/` | `xilinx-bootbin_1.0.bbappend` — injects AIE CDO partitions into BOOT.BIN |
| `recipes-bsp/bootbin/files/` | `aie.merged.cdo.bin`, `aie.cdo.device.partition.reset.bin` |
| `recipes-bsp/device-tree/` | DTS patches including zocl 32-IRQ node |
| `recipes-bsp/u-boot/` | U-Boot configuration |
| `recipes-bsp/vd100-firmware/` | Firmware artifacts |
| `recipes-apps/vd100-ps-ma-client/` | XRT batch client — golden test vector, confirms AIE pipeline |
| `recipes-apps/vd100-ma-trading-signal/` | Live Binance feed → SW/AIE MA → Hardhat smart contract |
| `recipes-kernel/linux/linux-xlnx/` | Kernel config (`bsp.cfg`), optional debug patch |
| `recipes-modules/` | Out-of-tree kernel modules |

---

## Critical: BOOT.BIN AIE CDO Partitions

The most impactful undocumented issue in Versal AIE development under Linux.

The upstream `xilinx-bootbin` recipe generates a BOOT.BIN containing only platform
boot components. Without the AIE CDO partitions, PLM processes only the 470-byte
`aie2_subsys.cdo` and leaves all AIE tiles `clock_gated` permanently. XRT then
hangs silently in `graph.run()` with no error, no timeout, no kernel panic.

### Symptom

```
# All tiles clock_gated — XRT hangs in ioctl retry loop
cat /sys/class/aie/aieaperture_0_17/aiepart_0_17/core | head -3
7_2: cs: clock_gated; ds: mm2s: clock_gated, s2mm: clock_gated; ls: clock_gated
8_2: cs: clock_gated; ds: mm2s: clock_gated, s2mm: clock_gated; ls: clock_gated

# dmesg floods with:
aie aiepart_0_17: Tile(7,2) is gated. Failed to write to 0xe200004
```

### Fix — `xilinx-bootbin_1.0.bbappend`

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://aie.cdo.device.partition.reset.bin \
            file://aie.merged.cdo.bin"

python do_configure:append() {
    # os and shutil already in scope from parent recipe — do NOT re-import
    workdir = d.getVar('WORKDIR')
    b = d.getVar('B')
    for f in ['aie.cdo.device.partition.reset.bin', 'aie.merged.cdo.bin']:
        src = os.path.join(workdir, f)
        dst = os.path.join(b, f)
        shutil.copyfile(src, dst)
        bb.note('VD100 AIE: copied %s -> %s' % (src, dst))
    fp = d.getVar('BIF_FILE_PATH')
    with open(fp, 'r') as fh:
        content = fh.read()
    content = content.rstrip()
    if content.endswith('}'):
        content = content[:-1]
    content += """
\timage {
\t\tname=aie_dev_part, id=0x18800000
\t\t{ type=cdo, file=aie.cdo.device.partition.reset.bin }
\t}
\timage {
\t\tname=aie_image, id=0x18800000
\t\t{ type=cdo, file=aie.merged.cdo.bin }
\t}
}"""
    with open(fp, 'w') as fh:
        fh.write(content)
    bb.note('VD100 AIE: BIF updated with aie_dev_part and aie_image')
}
```

> **BitBake scoping:** `os` and `shutil` are imported by the parent `do_configure`.
> Adding `import os` in the bbappend creates a local binding that shadows the existing
> one before assignment — causes `UnboundLocalError`. Do not re-import.

### Verify BOOT.BIN

```bash
bootgen -read /run/media/mmcblk0p1/efi/BOOT.BIN -arch versal 2>/dev/null | grep -E "Image:|aie"
```

Expected — all three AIE images present:
```
+---Image: aie2_subsys [id:0x421c028]
+---Image: aie_dev_part [id:0x18800000]
+---Image: aie_image [id:0x18800000]
```

---

## Critical: zocl DT Node

The zocl kernel driver requires 32 IRQs from the AXI interrupt controller.
Generate the correct DT node using sdtgen — **not** a hand-crafted DTS:

```bash
sdtgen set_dt_param -dir sdt_out -zocl enable
```

Without `-zocl enable`:
- zocl probes with 4 hardcoded GIC SPI IRQs
- Hardware state is misreported (`reset` instead of `clock_gated`)
- AXI errors cause kernel panics instead of returning `EINVAL`

The generated node uses `interrupts-extended = <&axi_intc_0 0 4>` through
`<&axi_intc_0 31 4>` — 32 IRQs from the AXI interrupt controller.

---

## XRT 2025.2

XRT is provided by `meta-xilinx-tools`. Enable in image recipe:

```bitbake
IMAGE_INSTALL:append = " xrt zocl vd100-ps-ma-client vd100-ma-trading-signal"
```

XRT installs to `/opt/xilinx/xrt/` (not `/usr`). Both app recipes pass
`EXTRA_OECMAKE += "-DXRT_ROOT=${STAGING_DIR_TARGET}/opt/xilinx/xrt"` to CMake.

Runtime requirements:
- `zocl.ko` loaded (`lsmod | grep zocl`)
- `libxrt_coreutil.so` + `libxrt_core.so` at `/opt/xilinx/xrt/lib/`
- BOOT.BIN with AIE CDO partitions (see above)

---

## vd100-ma-trading-signal Recipe

Located at `recipes-apps/vd100-ma-trading-signal/vd100-ma-trading-signal_1.0.bb`.

Production streaming application — connects to Binance WebSocket, computes MA
crossover on live BTCUSDT mid prices, posts BUY/SELL signals to an Ethereum
smart contract via JSON-RPC.

Recipe dependencies:

```bitbake
DEPENDS = "xrt spdlog boost nlohmann-json libcurl"
```

Usage on VD100:

```bash
# SW mode (production — 1440ns per block on A72)
sudo vd100_ma_trading_signal /home/root/config.json

# AIE mode (integrated, see performance notes)
# Set "mode": "aie" in config.json
sudo vd100_ma_trading_signal /home/root/config.json
```

`sudo` required — XRT needs root access to `/dev/dri/renderD128`.

### Hardhat setup (on workstation)

```bash
npx hardhat node --hostname 0.0.0.0   # bind all interfaces so VD100 can reach it
npx hardhat run scripts/deploy.js --network localhost
```

Contract address after first deploy: `0x5FbDB2315678afecb367f032d93F642f64180aa3`
From account (Hardhat #0): `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`

### AIE mode — performance findings

The AIE pipeline is fully integrated and produces correct results. XRT lifecycle
overhead on XCVE2302 (~47ms per call) dominates due to AMD's intentional
`force_program` on every `hw_context` creation — required because AIE tile state
is not cleanly reset otherwise (documented in XRT source `shim.cpp`).

| Mode | Latency per block |
|------|-------------------|
| SW (A72) | ~1440ns |
| AIE (XRT full lifecycle) | ~47ms |

SW mode is the production path for per-tick latency. AIE mode wins for batch
workloads (1000+ blocks per session). See
[vd100-ma-trading-signal](https://github.com/adilsondias-engineer/vd100-ma-trading-signal)
for full analysis.

---

## vd100-ps-ma-client Recipe

Located at `recipes-apps/vd100-ps-ma-client/vd100-ps-ma-client_1.0.bb`.

Builds the XRT host application from source via CMake cross-compilation.
The compiled binary is installed to `/usr/bin/vd100-ps-ma-client`.

Usage on VD100:
```bash
# Golden test vector (built-in)
sudo vd100-ps-ma-client /home/root/files/build/aie.xclbin

# Custom price file (one int32/line, multiple of 56 samples)
sudo vd100-ps-ma-client /home/root/files/build/aie.xclbin prices.txt
```

`sudo` required — XRT needs root access to `/dev/dri/renderD128` (zocl).

Expected output:
```
+---------+----------+----------+--------+
|  Block  | fast_ma  | slow_ma  | Signal |
+---------+----------+----------+--------+
|      1  |    5000  |    5000  |  HOLD  |
|      2  |    4990  |    4990  |  HOLD  |
|      3  |    5051  |    5002  |  BUY   |
|      4  |    5600  |    5600  |  HOLD  |
+---------+----------+----------+--------+
[DONE] 4 block(s) processed via AIE-ML v2 (XCVE2302)
```

---

## Build

```bash
# On yoctoBuilder (Ubuntu 22.04 VM)
cd /work/yocto
source setupsdk

# Full image build (~20 min clean)
bitbake edf-linux-disk-image

# BOOT.BIN only (after updating AIE CDO files)
bitbake xilinx-bootbin -c cleansstate && bitbake xilinx-bootbin

# XRT app only
bitbake vd100-ps-ma-client

# After kernel or zocl changes
bitbake zocl -c cleansstate && bitbake zocl
bitbake edf-linux-disk-image
```

> **zocl is an out-of-tree module.** Always run `cleansstate` after kernel changes
> before rebuilding zocl — the module must be compiled against the new kernel headers.

---

## Rebuild After CDO Update

When `vd100_ma_system_project` is rebuilt (new xclbin), update the CDO files:

```bash
# Copy updated CDOs to meta layer
cp <vd100-aie-pipeline>/vd100_ma_system_project/build/hw/package/aie.merged.cdo.bin \
   /work/yocto/sources/meta-vd100_v3/recipes-bsp/bootbin/files/

cp <vd100-aie-pipeline>/vd100_ma_system_project/build/hw/package/libadf/sw/aie.cdo.device.partition.reset.bin \
   /work/yocto/sources/meta-vd100_v3/recipes-bsp/bootbin/files/

# Rebuild BOOT.BIN
bitbake xilinx-bootbin -c cleansstate && bitbake xilinx-bootbin

# Deploy new xclbin to VD100
scp <vd100-aie-pipeline>/vd100_ma_system_project/build/hw/binary_container_1.xclbin \
    root@vd100:~/files/build/aie.xclbin
```

> xclbin and BOOT.BIN CDOs must always come from the same build.
> Running a new xclbin against old CDOs will fail.

---

## Yocto Environment

| Item | Value |
|------|-------|
| Yocto release | Scarthgap (5.0) |
| meta-xilinx branch | `rel-v2025.2` |
| Base image | `edf-linux-disk-image` (AMD EDF) |
| Machine | `versal-generic-xcve2302` |
| Distro | `vd100` |
| Package format | RPM |
| Kernel | `6.12.40-xilinx` (stock, no patches) |
| XRT | 2025.2 |
| Build host | Ubuntu 22.04 (yoctoBuilder VM) |
| Build cores | 10 of 16 allocated to bitbake |
| Clean rebuild time | ~20 min |

---

## Key Lessons Learned

- **BOOT.BIN CDO gap** — the dominant undocumented issue. No error is raised;
  tiles silently remain `clock_gated`. Always verify with `bootgen -read`.
- **`sdtgen -zocl enable` is mandatory** — the flag is not optional, not default,
  and not documented as required in any AMD reference for XCVE2302.
- **No kernel patches required** — stock `linux-xlnx` + correct zocl DT node +
  correct BOOT.BIN CDOs = working pipeline. All kernel workarounds explored during
  development were symptoms of the missing CDO issue.
- **BitBake Python scoping** — imports in `do_configure:append` conflict with parent
  recipe imports. Do not re-import `os` or `shutil` in bbappend functions.
- **zocl OOT module** — must be rebuilt with `cleansstate` after every kernel change.
- **JTAG interference** — connecting Vitis JTAG while the XRT application runs causes
  AIE array reinitialisation → zero output. Disconnect JTAG before running.

---

## Related

| Repository | Description |
|-----------|-------------|
| [versal-ai-edge-vd100-linux](https://github.com/adilsondias-engineer/versal-ai-edge-vd100-linux) | Root repo — meta-vd100_v3 is a submodule here |
| [meta-vd100](https://github.com/adilsondias-engineer/meta-vd100) | v1 — SD boot, Ethernet, USB, SSH |
| [meta-vd100_v2](https://github.com/adilsondias-engineer/meta-vd100_v2) | v2 — + I2C, LM75, PL LED, PS_KEY IRQ |
| [vd100-aie-pipeline](https://github.com/adilsondias-engineer/vd100-aie-pipeline) | AIE pipeline — Vivado BD, Vitis system project, xclbin |
| [vd100-ps-ma-client](https://github.com/adilsondias-engineer/vd100-ps-ma-client) | XRT batch client — golden test vector validation |
| [vd100-ma-trading-signal](https://github.com/adilsondias-engineer/vd100-ma-trading-signal) | Live Binance feed → SW/AIE MA → Ethereum smart contract |

---

*XCVE2302 — Versal AI Edge — Yocto Scarthgap — AMD EDF 25.11 — XRT 2025.2 — VD100 Linux 1.0*
