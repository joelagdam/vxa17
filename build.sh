#!/bin/bash
# VXA17 Kernel Build for Redmi 9T (lime) — using system GCC
set -e

KERNEL_SOURCE="valeryn_kernel"
REPO_URL="https://github.com/frstprjkt/valeryn_xiaomi_sm6115.git"
BRANCH="android16"

echo "=== VXA17 Kernel Build (GCC) ==="

# Clone kernel
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "[1/4] Cloning valeryn kernel source..."
    git clone --depth=1 --branch $BRANCH $REPO_URL $KERNEL_SOURCE
fi

cd $KERNEL_SOURCE

# Configure
echo "[2/4] Configuring kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- vendor/bengal_defconfig

# Merge lime config
if [ -f arch/arm64/configs/vendor/xiaomi/lime.config ]; then
    scripts/kconfig/merge_config.sh .config arch/arm64/configs/vendor/xiaomi/lime.config
fi

# Build
echo "[3/4] Building kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# Package
echo "[4/4] Packaging..."
mkdir -p ../artifacts
cp arch/arm64/boot/Image.gz ../artifacts/
cp .config ../artifacts/defconfig

echo "=== Done ==="
ls -la ../artifacts/