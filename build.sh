#!/bin/bash
# VXA17 Kernel Build for Redmi 9T (lime) — A-only
# Applies patches inline during build (no git apply needed)

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
fi

cd $KERNEL_SOURCE

# Step 2: Apply torch/charging fix INLINE (no patch files)
echo "[2/5] Applying torch/charging fix..."

# 2a: Add schgm_flash_set_active() to schgm-flash.c
# Insert new function after schgm_flash_torch_priority() closing brace
FLASH_C="drivers/power/supply/qcom/schgm-flash.c"

# Check if already patched
if grep -q "schgm_flash_set_active" "$FLASH_C"; then
    echo "  schgm-flash.c already patched, skipping"
else
    # Find the line after the closing brace of schgm_flash_torch_priority
    # and insert the new function before schgm_flash_init
    python3 -c "
import re
with open('$FLASH_C', 'r') as f:
    content = f.read()

new_func = '''
void schgm_flash_set_active(struct smb_charger *chg, bool active)
{
\tint rc;
\tu8 reg;

\tif (chg->headroom_mode == -EINVAL)
\t\treturn;

\t/*
\t * Dynamic boost control: force 5V boost + torch priority ONLY while
\t * flash is active.  When flash turns off, clear both bits so adaptive
\t * USB charging can resume.
\t */
\treg = active ? FORCE_FLASH_BOOST_5V_BIT : 0;
\trc = smblib_write(chg, SCHGM_FORCE_BOOST_CONTROL, reg);
\tif (rc < 0) {
\t\tpr_err(\"Couldn't set force boost control rc=%d\n\", rc);
\t\treturn;
\t}

\treg = active ? TORCH_PRIORITY_CONTROL_BIT : 0;
\trc = smblib_write(chg, SCHGM_TORCH_PRIORITY_CONTROL_REG, reg);
\tif (rc < 0) {
\t\tpr_err(\"Couldn't set torch priority control rc=%d\n\", rc);
\t\treturn;
\t}

\tpr_debug(\"Flash dynamic boost %s\n\", active ? \"engaged\" : \"released\");
}
'''

# Insert before 'int schgm_flash_init'
content = content.replace(
    'int schgm_flash_init(struct smb_charger *chg)',
    new_func.strip() + '\n\nint schgm_flash_init(struct smb_charger *chg)'
)

with open('$FLASH_C', 'w') as f:
    f.write(content)
print('  Injected schgm_flash_set_active() into schgm-flash.c')
"
fi

# 2b: Add declaration to schgm-flash.h
FLASH_H="drivers/power/supply/qcom/schgm-flash.h"
if grep -q "schgm_flash_set_active" "$FLASH_H"; then
    echo "  schgm-flash.h already patched, skipping"
else
    python3 -c "
with open('$FLASH_H', 'r') as f:
    content = f.read()

content = content.replace(
    'bool is_flash_active(struct smb_charger *chg);',
    'bool is_flash_active(struct smb_charger *chg);\nvoid schgm_flash_set_active(struct smb_charger *chg, bool active);'
)

with open('$FLASH_H', 'w') as f:
    f.write(content)
print('  Added schgm_flash_set_active() declaration to schgm-flash.h')
"
fi

# 2c: Wire flash_active setter in qpnp-smb5.c
SMB5_C="drivers/power/supply/qcom/qpnp-smb5.c"
if grep -q "schgm_flash_set_active" "$SMB5_C"; then
    echo "  qpnp-smb5.c already patched, skipping"
else
    python3 -c "
with open('$SMB5_C', 'r') as f:
    content = f.read()

# Add dynamic boost call when flash_active changes for PMI632
old = '''case POWER_SUPPLY_PROP_FLASH_ACTIVE:
\t\tif ((chg->chg_param.smb_version == PMI632_SUBTYPE)
\t\t\t\t&& (chg->flash_active != val->intval)) {
\t\t\tchg->flash_active = val->intval;'''

new = '''case POWER_SUPPLY_PROP_FLASH_ACTIVE:
\t\tif ((chg->chg_param.smb_version == PMI632_SUBTYPE)
\t\t\t\t&& (chg->flash_active != val->intval)) {
\t\t\t/*
\t\t\t * Dynamic boost: engage 5V boost while torch is on,
\t\t\t * release when torch turns off to resume charging.
\t\t\t */
\t\t\tschgm_flash_set_active(chg, val->intval);

\t\t\tchg->flash_active = val->intval;'''

content = content.replace(old, new)

with open('$SMB5_C', 'w') as f:
    f.write(content)
print('  Wired flash_active to dynamic boost in qpnp-smb5.c')
"
fi

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

echo ""
echo "=== Build Complete ==="
ls -la ../artifacts/