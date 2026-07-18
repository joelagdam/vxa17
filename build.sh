#!/bin/bash
# VXA17 Kernel Build Script for Redmi 9T (lime/chime) — A-only
# Builds kernel from valeryn source with torch/charging fix

set -e

KERNEL_SOURCE="valeryn_kernel"
REPO_URL="https://github.com/frstprjkt/valeryn_xiaomi_sm6115.git"
BRANCH="android16"

echo "=== VXA17 Kernel Build (A-only) ==="
echo "Target: Redmi 9T (lime/chime), SM6115 (bengal)"
echo ""

# Step 1: Clone kernel source (shallow)
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "[1/5] Cloning valeryn kernel source..."
    git clone --depth=1 --branch $BRANCH $REPO_URL $KERNEL_SOURCE
else
    echo "[1/5] Kernel source already exists, skipping clone"
fi

cd $KERNEL_SOURCE

# Step 2: Apply patches
echo "[2/5] Applying patches..."
git apply ../patches/0001-torch-charging-fix.patch || echo "Patch 1 may already be applied"
git apply ../patches/0002-wire-flash-active.patch || echo "Patch 2 may already be applied"

# Step 3: Configure kernel
echo "[3/5] Configuring kernel..."
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    vendor/bengal_defconfig

# Merge lime-specific config
if [ -f arch/arm64/configs/vendor/xiaomi/lime.config ]; then
    scripts/kconfig/merge_config.sh .config \
        arch/arm64/configs/vendor/xiaomi/lime.config
fi

# Step 4: Build kernel
echo "[4/5] Building kernel..."
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    -j$(nproc) 2>&1 | tee build.log

# Step 5: Package artifacts (A-only)
echo "[5/5] Packaging artifacts..."
mkdir -p ../artifacts
cp arch/arm64/boot/Image.gz ../artifacts/
cp .config ../artifacts/defconfig
cp build.log ../artifacts/

# Copy DTBO if available
find arch/arm64/boot/dts -name "*.dtbo" -exec cp {} ../artifacts/ \; 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo ""
echo "Artifacts:"
ls -la ../artifacts/
echo ""
echo "To flash on Lunaris (A-only):"
echo "  1. Unpack stock boot.img:"
echo "     magiskboot unpack boot.img"
echo "  2. Replace kernel:"
echo "     cp artifacts/Image.gz kernel"
echo "  3. Repack:"
echo "     magiskboot repack boot.img new_boot.img"
echo "  4. Flash:"
echo "     fastboot flash boot new_boot.img"
echo "     fastboot reboot"