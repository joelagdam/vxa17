# VXA17 Kernel Build — Complete Reference for AI Agents

## Project Goal

Build a custom **Android 17 (VXA17)** kernel for the **Xiaomi Redmi 9T** (codenames: `lime` / `chime`) based on the **valeryn kernel 4.19.325** (Qualcomm Bengal/SM6115 SoC). The output is a bootable kernel image (`Image.gz-dtb` or `Image.gz`) that can be flashed via fastboot.

**End-to-end goal**: Download kernel artifact from GitHub Actions → flash to device → device boots Android 17 with the custom kernel.

---

## Repository Structure

```
vxa17/                          ← GitHub repo root (https://github.com/joelagdam/vxa17)
├── .github/
│   └── workflows/
│       └── build.yml           ← CI workflow: installs deps, runs build.sh, uploads artifact
├── build.sh                    ← Main build script (the ONLY script that matters)
├── configs/                    ← Empty dir (reserved for future custom defconfigs)
├── patches/                    ← Empty dir (patches currently applied inline or not at all)
├── README.md                   ← Project docs (flashing, A/B slot info, device info)
├── .gitignore                  ← Ignores build artifacts, .config, .vscode, etc.
└── .git/                       ← Git repo (origin: https://github.com/joelagdam/vxa17.git)
```

**Note**: `build.sh` clones the kernel source at runtime into `vxa17/valeryn_kernel/`. This directory is NOT committed to git (it's ~500MB+).

---

## Source Kernel Details

| Field | Value |
|-------|-------|
| **Source repo** | [frstprjkt/valeryn_xiaomi_sm6115](https://github.com/frstprjkt/valeryn_xiaomi_sm6115) |
| **Branch** | `android16` |
| **Kernel version** | 4.19.325 |
| **Codename in repo** | `valeryn-cip133-st17` |
| **SoC** | Qualcomm SM6115 (Snapdragon 662) — "Bengal" platform |
| **Architecture** | arm64 |
| **Missing file** | `scripts/min-tool-version.sh` — must be created as a stub (see build.sh) |

### Available Defconfigs (in source repo)

Located at `arch/arm64/configs/vendor/`:

| Config | Size | Notes |
|--------|------|-------|
| `bengal_defconfig` | 19KB | Generic Bengal config (used in early CI runs, failed) |
| `bengal-perf_defconfig` | 17KB | **Production/performance config (CURRENT — use this)** |
| `bengal-lite_defconfig` | 19KB | Lite variant |
| `bengal-lite-perf_defconfig` | 17KB | Lite performance variant |
| `chime-stock_defconfig` | 148KB | Full stock config for Redmi 9T (chime) — very large |
| `sdm660_defconfig` / `sdm660-perf_defconfig` | ~18-20KB | SDM660 configs (NOT for SM6115) |
| `defconfig` | 17KB | Top-level generic defconfig |
| `gki_defconfig` | 13KB | GKI defconfig |

**Use `vendor/bengal-perf_defconfig`** — it's the production config for this SoC.

---

## Build System — Critical Details

### Toolchain: Clang/LLVM (NOT GCC)

The valeryn kernel was **designed for Clang/LLVM**. The kernel Makefile has:
- Full `LLVM=1` support (auto-detects clang, ld.lld, llvm-ar, etc.)
- Hardcoded `-Werror=...` flags that break with newer GCC versions (GCC 13+ on Ubuntu 24.04)
- Clang-specific flags (`-mllvm`, `--target=`, `-integrated-as`, etc.)

**Never use GCC.** The CI installs `clang lld llvm` packages.

### Output Directory: `O=out`

The kernel Makefile has `KBUILD_OUTPUT := out` hardcoded at the top. This means:
- Every `make` command creates `out/` and runs a sub-make there
- The sub-make's working directory is `out/`
- Source tree (`..`) is checked by `prepare3` for cleanliness
- **Always pass `O=out` explicitly** to avoid ambiguity

### The `prepare3` Trap

The kernel's `prepare3` rule checks if the source tree is clean:
```makefile
if [ -f $(srctree)/.config -o -d $(srctree)/include/config ]; then
    echo "not clean, please run 'make mrproper'"
    /bin/false
fi
```

**What causes false "not clean" failures:**
1. Running `scripts/config --file .config` when `.config` doesn't exist in the source tree — this **creates an empty `.config`** in the source tree
2. Running `make mrproper` without `O=` — this runs mrproper in `out/`, not the source tree
3. Any command that writes to `source_tree/.config` or creates `source_tree/include/config/`

**The fix**: Always use `O=out` for make commands, and `scripts/config --file out/.config` for config edits.

### Build Command Sequence

```bash
cd valeryn_kernel

# 1. Clean SOURCE TREE (must use O= to target source tree, not out/)
make O= mrproper || true

# 2. Configure (creates out/.config)
make ARCH=arm64 LLVM=1 O=out vendor/bengal-perf_defconfig

# 3. Post-configure tweaks (edit out/.config, not source tree .config)
scripts/config --file out/.config -d CC_WERROR || true
make ARCH=arm64 LLVM=1 O=out olddefconfig

# 4. Build
make ARCH=arm64 LLVM=1 O=out -j$(nproc)

# 5. Package (output is in out/arch/arm64/boot/)
cp out/arch/arm64/boot/Image.gz-dtb ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image.gz ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image ../artifacts/
```

### Make Variables Reference

| Variable | Value | Purpose |
|----------|-------|---------|
| `ARCH` | `arm64` | Target architecture |
| `LLVM` | `1` | Use Clang/LLVM toolchain instead of GCC |
| `O` | `out` | Output directory for build artifacts |
| `CROSS_COMPILE` | *(not needed with LLVM=1)* | Only for GCC builds |
| `-j$(nproc)` | *(auto)* | Parallel jobs = CPU count |

### Config Tweaks

| Config Option | Action | Reason |
|---------------|--------|--------|
| `CC_WERROR` | Disable (`-d`) | Newer compilers warn on 4.19 code; these warnings become errors with CC_WERROR=y |

---

## CI Workflow (`build.yml`)

- **Runner**: `ubuntu-latest` (Ubuntu 24.04, 2 cores, ~7GB RAM)
- **Timeout**: 90 minutes (full kernel build takes 30-60 min)
- **Trigger**: Push to `main` or `android16` branches, or manual `workflow_dispatch`
- **Artifact**: `kernel-lime-a17` (retained for 30 days)

### CI Dependencies

```bash
build-essential bc flex bison libssl-dev libelf-dev
python3 clang lld llvm device-tree-compiler
```

### CI Build Steps

1. Checkout repo (shallow clone)
2. Install dependencies (apt-get)
3. Run `build.sh` (clones kernel, configures, builds, packages)
4. Upload `artifacts/` directory as `kernel-lime-a17`

---

## Known Issues & Fixes (History)

| Commit | Issue | Fix |
|--------|-------|-----|
| `43df4ec` | Initial build attempt | Set up CI + build script |
| `eee13c2` | A/B slot support needed | Added A/B awareness |
| `54a5cea` | A-only build for Lunaris | Single Image.gz for stock boot.img |
| `eb2e441` | Patches not applying in CI | Inline patching during build |
| `0d28c27` | Patches causing conflicts | Clean build without patches |
| `ac68e85` | Clang download failing | Switch to system GCC |
| `0a29753` | mrproper/merge_config issues | Skip merge_config, add mrproper |
| `1d26093` | `min-tool-version.sh` missing | Created stub returning low versions |
| `d6e332d` | GCC 13 + 4.19 = Werror failures | **Switch to Clang/LLVM** |
| `135001a` | prepare3 "not clean" error | Use `O= mrproper` for source tree |
| `d22d717` | scripts/config creating .config in source tree | Use `O=out` everywhere, `--file out/.config` |

---

## Device Details

| Field | Value |
|-------|-------|
| **Device** | Xiaomi Redmi 9T |
| **Model** | M2010J19SG |
| **Codenames** | `lime` (global), `chime` (India/China) |
| **SoC** | Qualcomm SM6115 (Snapdragon 662) |
| **Boot type** | A-only by default (recovery can be repurposed as boot_b) |
| **Kernel** | 4.19.325 (non-GKI) |
| **Android target** | Android 17 (SDK 36) |
| **Super partition** | 8GB with logical volumes |

---

## Flashing Instructions

### Prerequisites
- Unlocked bootloader
- fastboot drivers installed
- `Image.gz-dtb` (or `Image.gz`) from CI artifact

### A/B Slot Flashing

```bash
# Check current slot
fastboot getvar current-slot

# Flash to Slot A
fastboot flash boot_a Image.gz-dtb
fastboot set_active a
fastboot reboot

# Flash to Slot B
fastboot flash boot_b Image.gz-dtb
fastboot set_active b
fastboot reboot

# After successful boot, mark slot good
fastboot mark-boot-good
```

### A-only Flashing (default)

```bash
fastboot flash boot Image.gz-dtb
fastboot reboot
```

---

## Torch/Charging Fix (Not Currently Applied as Patch)

The original goal included a fix for the PMI632 permanent boost issue:
- **Problem**: `headroom-mode=0` (FIXED_MODE) forces bits at charger init, never releases them, breaking USB charging
- **Solution**: Dynamic boost control — engage only while flash is active
- **Affected files**: `drivers/power/supply/qcom/schgm-flash.c`, `drivers/power/supply/qcom/qpnp-smb5.c`
- **Status**: Patches exist in `patches/` directory (currently empty) and were previously applied inline. They need to be re-added if the torch/charging fix is desired.

---

## Key Paths (After Build)

```
vxa17/
├── build.sh
├── valeryn_kernel/              ← Cloned at build time (not in git)
│   ├── scripts/min-tool-version.sh  ← Created by build.sh (missing from source)
│   ├── out/                     ← Build output directory
│   │   ├── .config              ← Active kernel config
│   │   ├── arch/arm64/boot/
│   │   │   ├── Image.gz-dtb     ← PRIMARY output (Qualcomm standard)
│   │   │   ├── Image.gz         ← Fallback output
│   │   │   └── Image            ← Raw uncompressed fallback
│   │   └── ...
│   ├── arch/arm64/configs/vendor/
│   │   ├── bengal-perf_defconfig  ← THE config we use
│   │   └── ...
│   └── Makefile                 ← Top-level (contains KBUILD_OUTPUT := out)
└── artifacts/                   ← CI uploads this
    ├── Image.gz-dtb             ← The kernel image
    └── defconfig                ← Copy of out/.config
```

---

## If You Need to Modify Something

### To change the defconfig:
Edit `build.sh` line 40: `make ARCH=arm64 LLVM=1 O=out vendor/bengal-perf_defconfig`

### To add a post-configure config tweak:
Add after line 43 in `build.sh`:
```bash
scripts/config --file out/.config --enable CONFIG_OPTION_NAME
```
Then run `make ARCH=arm64 LLVM=1 O=out olddefconfig` to resolve dependencies.

### To add a patch:
```bash
cd valeryn_kernel
git apply ../patches/0001-my-fix.patch
```
Or inline it in `build.sh` after the clone step.

### To change the toolchain:
**Don't.** Use Clang/LLVM. If you must use GCC, you'll need to suppress `-Werror` flags and likely hit compatibility issues.

### To build locally:
```bash
# Prerequisites (Ubuntu/Debian)
sudo apt install build-essential bc flex bison libssl-dev libelf-dev python3 clang lld llvm device-tree-compiler

# Build
cd vxa17
chmod +x build.sh
./build.sh
```

---

## Common Pitfalls

1. **Never use `scripts/config --file .config`** — always `--file out/.config`
2. **Never run `make mrproper` without `O=`** — it runs in `out/`, not the source tree
3. **Never use GCC** — the kernel has Clang-specific code paths
4. **Never skip `olddefconfig`** after config changes — unresolved symbols cause build failures
5. **Never commit `valeryn_kernel/`** — it's ~500MB+ and cloned at build time
6. **The CI runner has 2 cores** — full build takes 30-60 min; don't set timeout below 90
7. **`Image.gz-dtb`** is the Qualcomm standard output — prefer it over `Image.gz`
