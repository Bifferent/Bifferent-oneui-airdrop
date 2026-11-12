#!/usr/bin/env bash
# Measure mosey AWDL (wonder0) throughput while a transfer is running.
# Usage: ./scripts/measure_throughput.sh [duration_seconds] [interval_seconds]
set -euo pipefail
DURATION=${1:-300}
INTERVAL=${2:-2}
command -v adb >/dev/null || { echo "adb not found" >&2; exit 1; }

RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

echo "Sampling /sys/class/net/wonder0/statistics for ${DURATION}s (interval ${INTERVAL}s)."
echo "Start a transfer from/to the Apple device now..."

END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
  TS=$(date +%s)
  OUT=$(adb shell 'cat /sys/class/net/wonder0/statistics/tx_bytes 2>/dev/null; cat /sys/class/net/wonder0/statistics/rx_bytes 2>/dev/null' 2>/dev/null | tr -d '\r' || true)
  TX=$(echo "$OUT" | sed -n '1p')
  RX=$(echo "$OUT" | sed -n '2p')
  [ -z "$TX" ] && TX=-1
  [ -z "$RX" ] && RX=-1
  echo "$TS $TX $RX" >> "$RAW"
  sleep "$INTERVAL"
done

python3 - "$RAW" <<'PY'
import sys

rows = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) == 3:
        try:
            rows.append(tuple(int(x) for x in p))
        except ValueError:
            pass

valid = [r for r in rows if r[1] >= 0]
if len(valid) < 2:
    print("no wonder0 samples captured (is the interface up and a transfer running?)")
    sys.exit(1)

# split into segments at counter resets (interface re-created between sessions)
segments, cur, last = [], [], None
for r in valid:
    if last is not None and r[1] < last:
        segments.append(cur)
        cur = []
    cur.append(r)
    last = r[1]
segments.append(cur)

big = max(segments, key=lambda s: s[-1][1] - s[0][1])
t0, x0 = big[0][0], big[0][1]
t1, x1 = big[-1][0], big[-1][1]
dt = t1 - t0
print(f"samples: {len(big)}  duration: {dt}s")
print(f"tx: {(x1 - x0) / dt / 1048576:.2f} MB/s  ({(x1 - x0) * 8 / dt / 1e6:.1f} Mbps)")
print(f"total tx: {x1 - x0} bytes")

best = 0.0
for i in range(len(big)):
    for j in range(i + 1, len(big)):
        if big[j][0] - big[i][0] >= 5:
            best = max(best, (big[j][1] - big[i][1]) / (big[j][0] - big[i][0]))
            break
print(f"peak(5s): {best / 1048576:.2f} MB/s  ({best * 8 / 1e6:.1f} Mbps)")
PY
