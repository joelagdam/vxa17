# VXA17 - Valeryn Kernel for Xiaomi SM6115 (Android 17, A/B)

Custom kernel build for **Redmi 9T** (`lime`/`chime`) targeting Android 17 compatibility with A/B slot support.

## What This Is

- **Base**: valeryn kernel 4.19.325 (Qualcomm Bengal/SM6115)
- **Source**: [frstprjkt/valeryn_xiaomi_sm6115](https://github.com/frstprjkt/valeryn_xiaomi_sm6115) (android16 branch)
- **Device**: Xiaomi Redmi 9T (M2010J19SG)
- **Target**: Android 17 AOSP with 4.19 kernel (non-GKI, using CONFIG_FAKE_UNAME_5_10)
- **A/B**: Supports A/B slot flashing (boot_a/boot_b, dtbo_a/dtbo_b)

## Patches Applied

### 1. Torch/Charging Dynamic Fix
Fixes the PMI632 permanent boost issue where `headroom-mode=0` (FIXED_MODE)
forced bits at charger init and never released them, breaking USB charging.

**Solution**: Dynamic boost control - engage only while flash is active.

### 2. A/B Slot Support
Adds A/B slot awareness to the kernel build and flash scripts.

## A/B Partition Layout

The Redmi 9T is **A-only by default**. To enable A/B:

### Option A: Repurpose Recovery as boot_b (Recommended)
Since A/B devices don't need recovery:
- `boot` = `boot_a` (sde49)
- `recovery` = `boot_b` (sda9, repurposed)

### Option B: Repartition eMMC
Requires repartitioning the eMMC with A/B variants:
- `boot_a` / `boot_b`
- `dtbo_a` / `dtbo_b`
- `vbmeta_a` / `vbmeta_b`

**WARNING**: Repartitioning is risky and can brick the device. Use Option A.

## Building

### GitHub Actions (recommended)
Push to this repo and the CI will build automatically.
Download `kernel-lime-a17` artifact.

### Local Build
```bash
git clone --depth=1 https://github.com/joelagdam/vxa17.git
cd vxa17
chmod +x build.sh
./build.sh
```

## Flashing (A/B)

### Slot A (current slot)
```bash
fastboot flash boot_a new_boot.img
fastboot flash dtbo_a new_dtbo.img
fastboot set_active a
fastboot reboot
```

### Slot B (inactive slot)
```bash
fastboot flash boot_b new_boot.img
fastboot flash dtbo_b new_dtbo.img
fastboot set_active b
fastboot reboot
```

### A/B Slot Management
```bash
# Check current slot
fastboot getvar current-slot

# Switch slots
fastboot set_active a
fastboot set_active b

# Mark slot as good (after successful boot)
fastboot mark-boot-good
```

## Device Info
- SoC: Qualcomm SM6115 (Snapdragon 662)
- Boot: A-only (recovery can be repurposed as boot_b)
- Kernel: 4.19.325-valeryn-cip133-st17
- Android: 16 (SDK 36), targeting A17
- Super partition: 8GB with logical volumes