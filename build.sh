#!/bin/bash
# VXA17 Kernel Build Script for Redmi 9T (lime/chime) - A/B Support
# Builds kernel from valeryn source with torch/charging fix + A/B support

set -e

KERNEL_SOURCE="valeryn_kernel"
REPO_URL="https://github.com/frstprjkt/valeryn_xiaomi_sm6115.git"
BRANCH="android16"

echo "=== VXA17 Kernel Build (A/B) ==="
echo "Target: Redmi 9T (lime/chime), SM6115 (bengal)"
echo "A/B Support: Enabled"
echo ""

# Step 1: Clone kernel source (shallow)
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "[1/6] Cloning valeryn kernel source..."
    git clone --depth=1 --branch $BRANCH $REPO_URL $KERNEL_SOURCE
else
    echo "[1/6] Kernel source already exists, skipping clone"
fi

cd $KERNEL_SOURCE

# Step 2: Apply patches
echo "[2/6] Applying patches..."
git apply ../patches/0001-torch-charging-fix.patch || echo "Patch 1 may already be applied"
git apply ../patches/0002-wire-flash-active.patch || echo "Patch 2 may already be applied"
git apply ../patches/0003-ab-slot-support.patch || echo "Patch 3 may already be applied"

# Step 3: Configure kernel (with A/B support)
echo "[3/6] Configuring kernel..."
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    vendor/bengal_defconfig

# Merge lime-specific config
if [ -f arch/arm64/configs/vendor/xiaomi/lime.config ]; then
    scripts/kconfig/merge_config.sh .config \
        arch/arm64/configs/vendor/xiaomi/lime.config
fi

# Merge A/B config
if [ -f ../configs/ab_config.fragment ]; then
    scripts/kconfig/merge_config.sh .config ../configs/ab_config.fragment
fi

# Step 4: Build kernel
echo "[4/6] Building kernel..."
make ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    -j$(nproc) 2>&1 | tee build.log

# Step 5: Package artifacts (A/B aware)
echo "[5/6] Packaging artifacts..."
mkdir -p ../artifacts/boot_a ../artifacts/boot_b
mkdir -p ../artifacts/dtbo_a ../artifacts/dtbo_b

cp arch/arm64/boot/Image.gz ../artifacts/boot_a/
cp arch/arm64/boot/Image.gz ../artifacts/boot_b/
cp .config ../artifacts/defconfig
cp build.log ../artifacts/

# Copy DTBO if available
if ls arch/arm64/boot/dts/vendor/qcom/*lime*.dtbo 1>/dev/null 2>&1; then
    cp arch/arm64/boot/dts/vendor/qcom/*lime*.dtbo ../artifacts/dtbo_a/
    cp arch/arm64/boot/dts/vendor/qcom/*lime*.dtbo ../artifacts/dtbo_b/
elif ls arch/arm64/boot/dts/vendor/qcom/*chime*.dtbo 1>/dev/null 2>&1; then
    cp arch/arm64/boot/dts/vendor/qcom/*chime*.dtbo ../artifacts/dtbo_a/
    cp arch/arm64/boot/dts/vendor/qcom/*chime*.dtbo ../artifacts/dtbo_b/
fi

# Step 6: Create flash script (A/B)
echo "[6/6] Creating A/B flash script..."
cat > ../artifacts/flash_ab.sh << 'FLASHEOF'
#!/bin/bash
# VXA17 A/B Flash Script for Redmi 9T
# Usage: ./flash_ab.sh [slot]
#   slot: "a" or "b" (default: current slot)

set -e

SLOT="${1:-current}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== VXA17 A/B Flash Script ==="

# Check if device is connected
if ! fastboot getvar current-slot 2>/dev/null; then
    echo "ERROR: No device connected or not in fastboot mode"
    echo "Boot to fastboot: adb reboot bootloader"
    exit 1
fi

# Get current slot
CURRENT_SLOT=$(fastboot getvar current-slot 2>&1 | grep "current-slot:" | cut -d' ' -f2)
echo "Current slot: $CURRENT_SLOT"

# Determine target slot
if [ "$SLOT" = "current" ]; then
    TARGET_SLOT="$CURRENT_SLOT"
else
    TARGET_SLOT="$SLOT"
fi
echo "Target slot: $TARGET_SLOT"

# Flash kernel
echo "Flashing kernel to slot $TARGET_SLOT..."
fastboot flash boot_$TARGET_SLOT "$SCRIPT_DIR/boot_$TARGET_SLOT/Image.gz"

# Flash DTBO if available
if [ -f "$SCRIPT_DIR/dtbo_$TARGET_SLOT/dtbo.img" ]; then
    echo "Flashing DTBO to slot $TARGET_SLOT..."
    fastboot flash dtbo_$TARGET_SLOT "$SCRIPT_DIR/dtbo_$TARGET_SLOT/dtbo.img"
fi

# Set active slot
echo "Setting active slot to $TARGET_SLOT..."
fastboot set_active $TARGET_SLOT

# Mark slot as good
echo "Marking slot $TARGET_SLOT as good..."
fastboot mark-boot-good

echo ""
echo "=== Flash Complete ==="
echo "Rebooting into slot $TARGET_SLOT..."
fastboot reboot
FLASHEOF
chmod +x ../artifacts/flash_ab.sh

echo ""
echo "=== Build Complete ==="
echo "Artifacts in: ../artifacts/"
echo ""
echo "To flash (A/B):"
echo "  ./artifacts/flash_ab.sh a    # Flash to slot A"
echo "  ./artifacts/flash_ab.sh b    # Flash to slot B"
echo ""
ls -la ../artifacts/