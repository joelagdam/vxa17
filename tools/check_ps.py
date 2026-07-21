import subprocess, os

script = r"""for f in /sys/class/power_supply/*/*; do
  d=$(basename $(dirname $f))
  b=$(basename $f)
  v=$(cat $f 2>/dev/null)
  echo "$d/$b: $v"
done
"""
with open('/data/local/tmp/check_ps.sh', 'w') as f:
    f.write(script)

subprocess.run(['adb', 'push', 'tools/check_ps.sh', '/data/local/tmp/check_ps.sh'])
subprocess.run(['adb', 'shell', 'sh', '/data/local/tmp/check_ps.sh'])
