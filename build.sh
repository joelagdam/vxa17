#!/bin/bash
# VXA17 Kernel Build for Redmi 9T (lime) — GCC, fixed
set -e

KERNEL_SOURCE="valeryn_kernel"
REPO_URL="https://github.com/frstprjkt/valeryn_xiaomi_sm6115.git"
BRANCH="android16"

echo "=== VXA17 Kernel Build ==="

# Clone kernel
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "[1/4] Cloning valeryn kernel source..."
    git clone --depth=1 --branch $BRANCH $REPO_URL $KERNEL_SOURCE
fi

cd $KERNEL_SOURCE

# Clean any stale build artifacts
echo "[2/4] Cleaning..."
make mrproper || true

# Configure — use bengal_defconfig directly, skip merge_config
echo "[3/4] Configuring kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- vendor/bengal_defconfig

# Build
echo "[4/4] Building kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# Package
mkdir -p ../artifacts
cp arch/arm64/boot/Image.gz ../artifacts/
cp .config ../artifacts/defconfig

echo "=== Done ==="
ls -la ../artifacts/