# AI handoff: Redmi 9T Lunaris torch vs USB charging

Updated: 2026-07-19

## Device and current ROM

- Device: Redmi 9T `lime` / platform family `chime`
- Model: `M2010J19SG`
- ADB serial: `24ea9cb0221`
- Current ROM: Lunaris AOSP chime Community 3.12 GMS, build dated 2026-07-04
- Kernel observed earlier: Linux `4.19.325-valeryn-cip133-st17`
- OrangeFox is available.
- Magisk/root exists, but the user explicitly does **not** want Magisk used for this torch/charging fix.

## User's required outcome

Keep all of these simultaneously:

1. Physical rear flashlight/torch works.
2. USB charging works when connected to a PC.
3. ADB remains usable.
4. Final package should be flashable through OrangeFox/recovery and should not depend on Magisk.

## Confirmed failure mechanism

The original Lunaris DTBO uses the PMI632 charger in its default/adaptive behavior. In that state, PC charging works, but the camera framework can report the torch ON while the physical LED remains dark when USB/ADB is connected.

V1 added this property under `/fragment@30/__overlay__`, whose target is `pmi632_charger`:

```dts
qcom,headroom-mode = <0>;
```

Qualcomm kernel interpretation:

- `FIXED_MODE = 0`
- `ADAPTIVE_MODE = 1`

In `drivers/power/supply/qcom/schgm-flash.c`, fixed mode writes:

- `FORCE_FLASH_BOOST_5V_BIT`
- `TORCH_PRIORITY_CONTROL_BIT`

These are applied during charger initialization and remain forced. Turning the flashlight off does not release them.

Live evidence with V1/V1.1:

```text
USB present: 1
USB online: 0
USB real_type: USB_CDP
USB current_max: 0
USB input_current_settled: 0
```

`dumpsys battery`:

```text
AC powered: false
USB powered: false
Max charging current: 0
Max charging voltage: 0
status: 3
Charging state: 0
```

ADB still works because USB data enumeration and charger input-current acceptance are separate. The PC sees the phone and ADB operates, but the charger driver votes zero usable current.

Camera evidence while the physical torch was on:

```text
Torch for camera id 0 turned on for client PID 2506
```

Thus the framework/HAL state is valid; the issue is PMI632 boost/charging coordination.

## Packages tested

### V1

File:

`C:\Users\KENT\Documents\kredmi9t\Redmi9T-Lunaris-3.12-Torch-Fix-AIO.zip`

Effect:

- Adds `qcom,headroom-mode = <0>`.
- Physical torch works.
- PC/ADB charging fails permanently, even after the LED is turned off.

### V2

File:

`C:\Users\KENT\Documents\kredmi9t\Redmi9T-Lunaris-3.12-Torch-Charging-Fix-AIO-v2.zip`

SHA-256:

`5ADF7D7536967DEC5468D391F79D66FC7AF3DA0F2ACD3D1529CB23F8F055DE1E`

Effect:

- Adds `qcom,headroom-mode = <1>`.
- Does not provide the required physical torch behavior under USB.

### Experimental V1.1

File:

`C:\Users\KENT\Documents\kredmi9t\Redmi9T-Lunaris-3.12-Torch-Charging-Fix-AIO-v1.1-EXPERIMENTAL.zip`

SHA-256:

`4458F3D8D461311A5CA656C45EA5D5E4D382203B9D0059BC7410BDE91BAB1518`

Changes:

```dts
- qcom,suspend-input-on-debug-batt;
+ qcom,headroom-mode = <0>;
```

Result: unsuccessful. Torch works, but PC charging remains at zero. This proves the debug-battery voter is not the main cause; fixed PMI632 boost is.

## Runtime ADB tests already attempted

Normal, non-root Android USB controls were tried:

- `svc usb setFunctions none`, then restore `adb`
- `svc usb resetUsbGadget`
- `svc usb resetUsbPort 0`
- ADB-only USB function
- Switching Android USB mode/no data transfer

ADB reconnected successfully, but charging remained zero.

Do not fake charging with `cmd battery set`; it changes displayed service state only and does not create physical charge current.

An APSD sysfs reset was investigated, but ordinary ADB cannot write the protected power-supply sysfs node. The user rejected Magisk for this fix. Do not pursue Magisk modules or persistent live SELinux rules.

## DTBO analysis

Original Lunaris DTBO and V1 were decompiled and compared. V1 differs from original only by adding:

```dts
qcom,headroom-mode = <0>;
```

The DTBO has one Android DTBO entry. The charger overlay also includes camera-flash references through `pmi632_flash0/1`, `pmi632_torch0/1`, and `pmi632_switch0`, but no alternative DT property was found that dynamically toggles boost.

There is no useful third `headroom-mode` value. DTBO is static, so it cannot express “force boost only while torch is active.”

## Kernel patch implementation

A **3-file kernel patch** at `patches/0001-dynamic-flash-boost.patch` provides the permanent solution.

### Patch files (all relative to kernel source root)

| File | Change |
|------|--------|
| `drivers/power/supply/qcom/schgm-flash.h` | Add `schgm_flash_set_active()` declaration |
| `drivers/power/supply/qcom/schgm-flash.c` | Add dynamic boost toggle implementation |
| `drivers/power/supply/qcom/qpnp-smb5.c` | Hook into `FLASH_ACTIVE` setter, call `schgm_flash_set_active()` |

### How it works

```c
// schgm-flash.h — new declaration
void schgm_flash_set_active(struct smb_charger *chg, bool active);

// schgm-flash.c — new function
void schgm_flash_set_active(struct smb_charger *chg, bool active)
{
    u8 reg;

    reg = active ? FORCE_FLASH_BOOST_5V_BIT : 0;
    smblib_masked_write(chg, SCHGM_FORCE_BOOST_CONTROL,
            FORCE_FLASH_BOOST_5V_BIT, reg);

    reg = active ? TORCH_PRIORITY_CONTROL_BIT : 0;
    smblib_masked_write(chg, SCHGM_TORCH_PRIORITY_CONTROL_REG,
            TORCH_PRIORITY_CONTROL_BIT, reg);
}

// qpnp-smb5.c — hook in existing FLASH_ACTIVE case
case POWER_SUPPLY_PROP_FLASH_ACTIVE:
    if ((chg->chg_param.smb_version == PMI632_SUBTYPE)
            && (chg->flash_active != val->intval)) {
        chg->flash_active = val->intval;
        schgm_flash_set_active(chg, !!chg->flash_active);  // ← added
        ...
    }
```

### Expected behavior

| State | FORCE_FLASH_BOOST | TORCH_PRIORITY | USB charging |
|-------|-------------------|----------------|-------------|
| No torch | 0 | 0 | Normal |
| Torch ON | 1 | 1 | Suspended |
| Torch OFF | 0 | 0 | Resumes |

### DTBO requirement

Set `qcom,headroom-mode = <1>` (ADAPTIVE_MODE) so init doesn't permanently force boost.
Without this, `schgm_flash_init()` applies FIXED_MODE at boot and the dynamic hook becomes ineffective.

### Patch application

Applied in `build.sh` step `[1a/5]` after clone, before config.

## Implementation status

- ✅ `patches/0001-dynamic-flash-boost.patch` created
- ✅ `build.sh` updated to apply patch after clone
- 🔲 Push to CI, verify kernel builds cleanly with patch
- 🔲 Patch DTBO to use `qcom,headroom-mode = <1>` (if currently <0>)
- 🔲 Flash boot + dtbo, validate torch + charging
- 🔲 Test photo flash, video, repeated cycles

## Important cautions

- Do not continue producing blind DTBO variants. The static-mode tradeoff is proven.
- Do not flash an unrelated generic kernel without verifying boot layout and device compatibility; bootloop risk is high.
- Do not use Magisk for the final fix.
- Do not use permanent SELinux permissive mode.
- V1/V1.1 should not remain installed if reliable charging is required.
- The kernel patch at `patches/0001-dynamic-flash-boost.patch` is the canonical fix; apply via build.sh step [1a/5].
- The original Lunaris ZIP contains its original `dtbo.img` and `vbmeta.img` at archive root:
  `C:\Users\KENT\Documents\kredmi9t\Lunaris-AOSP-chime-Community-3.12-GMS-2026070411.zip`

