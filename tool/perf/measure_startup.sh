#!/usr/bin/env bash
# Cold-start timeline on a device/emulator (see tool/perf/README.md).
#
#   tool/perf/measure_startup.sh <apk> [runs] [package]
#
# Installs <apk>, does one warm-up start (seeds the learner), then [runs]
# cold starts (force-stop + `am start -W`). For each run prints the
# `STARTUP <step> <ms since main()>` marks and the ms from the launch intent
# (ActivityTaskManager "START") to each mark, then the medians.
set -euo pipefail
APK=$1
RUNS=${2:-7}
PKG=${3:-com.lingora.lingora.perf}
ADB=${ADB:-adb}
DEV=${DEV:-emulator-5554}
A="$ADB -s $DEV"
ACT="$PKG/com.lingora.lingora.MainActivity"

$A install -r "$APK" >/dev/null
$A shell am force-stop "$PKG"
$A shell am start -W -n "$ACT" >/dev/null
sleep 6

ms() { # logcat "MM-DD HH:MM:SS.mmm" -> ms of day
  local t=${1#* }
  local h=${t%%:*} rest=${t#*:}
  local m=${rest%%:*} s=${rest#*:}
  echo $(( (10#$h * 3600 + 10#$m * 60) * 1000 + 10#${s%.*} * 1000 + 10#${s#*.} ))
}

out=$(mktemp)
for i in $(seq 1 "$RUNS"); do
  $A shell am force-stop "$PKG"
  sleep 1
  $A logcat -c
  total=$($A shell am start -W -n "$ACT" | tr -d '\r' | awk '/TotalTime/ {print $2}')
  sleep 5
  log=$($A logcat -d -v time | tr -d '\r')
  start_line=$(grep -m1 "START u0.*$PKG" <<<"$log" || true)
  [ -z "$start_line" ] && { echo "run $i: no START line"; continue; }
  t0=$(ms "$(cut -c1-18 <<<"$start_line")")
  echo "run $i (am TotalTime ${total}ms)"
  while read -r line; do
    t=$(ms "$(cut -c1-18 <<<"$line")")
    name=$(awk '{for(i=1;i<=NF;i++) if($i=="STARTUP") print $(i+1)}' <<<"$line")
    dart=$(awk '{for(i=1;i<=NF;i++) if($i=="STARTUP") print $(i+2)}' <<<"$line")
    printf '  %-18s main+%5sms  launch+%5sms\n' "$name" "$dart" "$((t - t0))"
    echo "$name $((t - t0))" >>"$out"
  done < <(grep "STARTUP " <<<"$log")
  echo "am_total $total" >>"$out"
done

echo "== medians (ms from launch intent) =="
for name in $(awk '{print $1}' "$out" | awk '!seen[$0]++'); do
  vals=$(awk -v n="$name" '$1==n {print $2}' "$out" | sort -n)
  count=$(wc -l <<<"$vals")
  med=$(sed -n "$(( (count + 1) / 2 ))p" <<<"$vals")
  printf '  %-18s %6s  (n=%s, min %s, max %s)\n' "$name" "$med" "$count" "$(head -1 <<<"$vals")" "$(tail -1 <<<"$vals")"
done
rm -f "$out"
