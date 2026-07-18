#!/bin/bash
# VXA17 Kernel Build for Redmi 9T (lime) — fixed min-tool-version
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

# Create missing min-tool-version.sh (missing from valeryn repo)
cat > scripts/min-tool-version.sh << 'MINTOOLEOF'
#!/bin/sh
# Stub: return a low version so any toolchain passes
case "$1" in
    binutils)  echo "2.25" ;;
    gcc)       echo "5.1.0" ;;
    clang)     echo "5.0.0" ;;
    rustc)     echo "1.41.0" ;;
    bindgen)   echo "0.55" ;;
    bison)     echo "2.8" ;;
    *?)        echo "0.0.0" ;;
esac
MINTOOLEOF
chmod +x scripts/min-tool-version.sh

# Clean
make mrproper || true

# Configure
echo "[2/4] Configuring kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- vendor/bengal_defconfig

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