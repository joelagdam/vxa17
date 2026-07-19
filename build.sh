#!/bin/bash
# VXA17 Kernel Build for Redmi 9T (lime) — Clang/LLVM toolchain
set -e

KERNEL_SOURCE="valeryn_kernel"
REPO_URL="https://github.com/frstprjkt/valeryn_xiaomi_sm6115.git"
BRANCH="android16"

echo "=== VXA17 Kernel Build (Clang/LLVM) ==="

# Clone kernel
if [ ! -d "$KERNEL_SOURCE" ]; then
    echo "[1/5] Cloning valeryn kernel source..."
    git clone --depth=1 --branch $BRANCH $REPO_URL $KERNEL_SOURCE
fi

cd $KERNEL_SOURCE

# Create missing min-tool-version.sh (missing from valeryn repo)
cat > scripts/min-tool-version.sh << 'MINTOOLEOF'
#!/bin/sh
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

# Clean source tree (use O= to target source tree, not out/)
echo "[2/5] Cleaning source tree..."
make O= mrproper || true

# Configure — use out/ directory for build artifacts
echo "[3/5] Configuring kernel..."
make ARCH=arm64 LLVM=1 O=out vendor/bengal-perf_defconfig

# Disable CC_WERROR in the output .config (not source tree .config)
scripts/config --file out/.config -d CC_WERROR || true
make ARCH=arm64 LLVM=1 O=out olddefconfig

# Build
echo "[4/5] Building kernel with Clang/LLVM..."
make ARCH=arm64 LLVM=1 O=out -j$(nproc)

# Package
echo "[5/5] Packaging..."
mkdir -p ../artifacts
cp out/arch/arm64/boot/Image.gz-dtb ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image.gz ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image ../artifacts/
cp out/.config ../artifacts/defconfig

echo "=== Done ==="
ls -la ../artifacts/
