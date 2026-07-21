#!/system/bin/sh
echo "=== Power supplies ==="
ls /sys/class/power_supply/
echo ""
echo "=== Flash properties ==="
for f in /sys/class/power_supply/*/flash_active; do
  if [ -f "$f" ]; then
    echo "$f: $(cat $f 2>/dev/null)"
  fi
done
for f in /sys/class/power_supply/*/flash_trigger; do
  if [ -f "$f" ]; then
    echo "$f: $(cat $f 2>/dev/null)"
  fi
done
echo ""
echo "=== LED class ==="
ls /sys/class/leds/ 2>/dev/null || echo "no /sys/class/leds"
echo ""
echo "=== Battery status ==="
for f in /sys/class/power_supply/battery/status /sys/class/power_supply/battery/capacity; do
  if [ -f "$f" ]; then
    echo "$f: $(cat $f 2>/dev/null)"
  fi
done
echo ""
echo "=== USB present ==="
cat /sys/class/power_supply/usb/present 2>/dev/null || echo "N/A"
echo "=== USB online ==="
cat /sys/class/power_supply/usb/online 2>/dev/null || echo "N/A"
echo "=== USB current_max ==="
cat /sys/class/power_supply/usb/current_max 2>/dev/null || echo "N/A"
echo "=== USB input_current_settled ==="
cat /sys/class/power_supply/usb/input_current_settled 2>/dev/null || echo "N/A"
