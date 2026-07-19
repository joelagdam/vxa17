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

# Fix missing/empty firmware sample for FT8719 touchscreen
# Must be AFTER mrproper since .i files are treated as intermediates and get cleaned
FW_SAMPLE="drivers/input/touchscreen/FT8719/include/firmware/fw_sample.i"
if [ ! -s "$FW_SAMPLE" ]; then
    mkdir -p "$(dirname "$FW_SAMPLE")"
    echo "0" > "$FW_SAMPLE"
fi

# Configure — use out/ directory for build artifacts
echo "[3/5] Configuring kernel..."
make ARCH=arm64 LLVM=1 O=out vendor/bengal-perf_defconfig

# Disable CC_WERROR in the output .config (not source tree .config)
scripts/config --file out/.config -d CC_WERROR || true
make ARCH=arm64 LLVM=1 O=out olddefconfig

# Merge official Android 17 base config fragment for 4.19
echo "[3a/5] Merging Android 17 base config..."
# -m: merge only, don't run internal make (we olddefconfig ourselves below)
scripts/kconfig/merge_config.sh -m -O out out/.config ../configs/android-base-4.19.config || true

# ARM64 conditional requirements (from android-base-conditional.xml)
scripts/config --file out/.config -e ARM64_PAN
scripts/config --file out/.config -e ARM64_SW_TTBR0_PAN
scripts/config --file out/.config -e ARMV8_DEPRECATED
scripts/config --file out/.config -e COMPAT
scripts/config --file out/.config -e CP15_BARRIER_EMULATION
scripts/config --file out/.config -e SETEND_EMULATION
scripts/config --file out/.config -e SWP_EMULATION
scripts/config --file out/.config -e BPF_JIT_ALWAYS_ON

# Fix empty usermodehelper path (Android 14+ requires non-empty)
scripts/config --file out/.config --set-str STATIC_USERMODEHELPER_PATH /sbin/umhelper

# Resolve any new dependencies from the merge
make ARCH=arm64 LLVM=1 O=out olddefconfig

# Build — capture full output to log file for debugging
echo "[4/5] Building kernel with Clang/LLVM..."
make ARCH=arm64 LLVM=1 O=out -j$(nproc) 2>&1 | tee ../build.log
BUILD_EXIT=${PIPESTATUS[0]}

if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "=== BUILD FAILED (exit code $BUILD_EXIT) ==="
    echo "=== Last 50 lines of build log: ==="
    tail -50 ../build.log
    echo ""
    echo "=== Searching for error lines: ==="
    grep -i "error:" ../build.log | tail -30
    exit $BUILD_EXIT
fi

# Package
echo "[5/5] Packaging..."
mkdir -p ../artifacts
cp out/arch/arm64/boot/Image.gz-dtb ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image.gz ../artifacts/ 2>/dev/null || \
cp out/arch/arm64/boot/Image ../artifacts/
cp out/.config ../artifacts/defconfig

echo "=== Done ==="
ls -la ../artifacts/
