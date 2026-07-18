# VXA17 - Valeryn Kernel for Xiaomi SM6115 (Android 17)

Custom kernel build for **Redmi 9T** (`lime`/`chime`) targeting Android 17 compatibility.

## What This Is

- **Base**: valeryn kernel 4.19.325 (Qualcomm Bengal/SM6115)
- **Source**: [frstprjkt/valeryn_xiaomi_sm6115](https://github.com/frstprjkt/valeryn_xiaomi_sm6115) (android16 branch)
- **Device**: Xiaomi Redmi 9T (M2010J19SG)
- **Target**: Android 17 AOSP with 4.19 kernel (non-GKI, using CONFIG_FAKE_UNAME_5_10)

## Patches Applied

### 1. Torch/Charging Dynamic Fix
Fixes the PMI632 permanent boost issue where `headroom-mode=0` (FIXED_MODE)
forced `FORCE_FLASH_BOOST_5V_BIT` and `TORCH_PRIORITY_CONTROL_BIT` at charger
init and never released them, breaking USB charging even after torch was off.

**Solution**: Dynamic boost control - engage only while flash is active, release
when flash turns off so adaptive USB charging resumes.

### Files Modified
- `drivers/power/supply/qcom/schgm-flash.c` - Add `schgm_flash_set_active()`
- `drivers/power/supply/qcom/schgm-flash.h` - Declare new function
- `drivers/power/supply/qcom/qpnp-smb5.c` - Wire `FLASH_ACTIVE` property to dynamic boost

## Building

### GitHub Actions (recommended)
Push to this repo and the CI will build automatically. Download `kernel-lime-a17` artifact.

### Local Build
```bash
git clone --depth=1 https://github.com/joelagdam/vxa17.git
cd vxa17/kernel_source
git apply patches/*.patch
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- vendor/bengal_defconfig
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

## Flashing

```bash
# Unpack current boot image
magiskboot unpack boot.img

# Replace kernel
cp kernel_source/arch/arm64/boot/Image.gz kernel

# Repack
magiskboot repack boot.img new_boot.img

# Flash
fastboot flash boot new_boot.img
fastboot reboot
```

## Device Info
- SoC: Qualcomm SM6115 (Snapdragon 662)
- Boot: A-only, OrangeFox recovery
- Kernel: 4.19.325-valeryn-cip133-st17
- Android: 16 (SDK 36), targeting A17