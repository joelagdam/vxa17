# VXA17 - Valeryn Kernel for Xiaomi SM6115 (Android 17)

Custom kernel build for **Redmi 9T** (`lime`/`chime`).

## What This Is

- **Base**: valeryn kernel 4.19.325 (Qualcomm Bengal/SM6115)
- **Source**: [frstprjkt/valeryn_xiaomi_sm6115](https://github.com/frstprjkt/valeryn_xiaomi_sm6115) (android16 branch)
- **Device**: Xiaomi Redmi 9T (M2010J19SG) — **A-only system-as-root (SAR)**
- **Target**: Android 17 AOSP with 4.19 kernel (non-GKI, using CONFIG_FAKE_UNAME_5_10)
- **GSI variant**: Flash **AB** GSI images (compatible with SAR A-only + true A/B)
- **Not A/B**: This device has a single boot partition, no slot switching.

## Patches Applied

### 1. Torch/Charging Dynamic Fix
Fixes the PMI632 permanent boost issue where `headroom-mode=0` (FIXED_MODE)
forced bits at charger init and never released them, breaking USB charging.

**Solution**: Dynamic boost control via `schgm_flash_set_active()` — boost is
released at charger init and toggled only while camera flash is active.

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

## Flashing

```bash
# Disable verity (unlocked bootloader)
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

# Flash boot image
fastboot flash boot boot-patched.img

# Flash DTBO (if needed)
fastboot flash dtbo dtbo.img

# Reboot
fastboot reboot
```

## Device Info
- SoC: Qualcomm SM6115 (Snapdragon 662)
- Boot: A-only system-as-root (SAR)
- Kernel: 4.19.325-valeryn-cip133-st17
- Android: 16 (SDK 36), targeting A17
- Super partition: 8GB with logical volumes