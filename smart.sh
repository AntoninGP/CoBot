#!/usr/bin/env bash
# smart.sh
set -Eeuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC1091
. ./utils.sh

# Charge conf
CONF_LOADED=0
if [[ -f ./main.conf ]]; then . ./main.conf; CONF_LOADED=1; fi
if [[ $CONF_LOADED -eq 0 && -f /etc/cobot/main.conf ]]; then . /etc/cobot/main.conf; CONF_LOADED=1; fi
[[ $CONF_LOADED -eq 1 ]] || die "main.conf introuvable."

have smartctl || die "smartctl manquant (smartmontools)."

discover_disks() {
  if [[ "${smart_nvme:-yes}" == "yes" ]]; then
    for d in /dev/nvme*n?; do [[ -e "$d" ]] && echo "$d"; done
  fi
  if [[ "${smart_sata:-yes}" == "yes" ]]; then
    for d in /dev/sd? /dev/hd? /dev/vd?; do [[ -e "$d" ]] && echo "$d"; done
  fi
}

MODE="${1:-}"
RUN_DIR="${2:-}"
[[ -z "$MODE" || -z "$RUN_DIR" ]] && { echo "Usage: $0 <short|long> <run_dir>"; exit 1; }

ensure_dir "$RUN_DIR"

extra_s="${smart_short_extra_s:-30}"
[[ "$MODE" == "long" ]] && extra_s="${smart_long_extra_s:-60}"

max_wait=0
mapfile -t disks < <(discover_disks)

if [[ "${#disks[@]}" -eq 0 ]]; then
  log "SMART: aucun disque détecté."
  echo "SKIP" > "${RUN_DIR}/SMART_${MODE}.status"
  exit 0
fi

for disk in "${disks[@]}"; do
  cap_file="${RUN_DIR}/smart_cap_$(basename "$disk").txt"
  smartctl -c "$disk" > "$cap_file" 2>&1 || true
  poll_s=60
  if [[ "$MODE" == "short" ]]; then
    est_min=$(grep -Eo 'Short self-test routine recommended polling time:.*\(([0-9]+)\) minutes' "$cap_file" | grep -Eo '\(([0-9]+)\)' | tr -d '()' | tail -n1)
  else
    est_min=$(grep -Eo 'Extended self-test routine recommended polling time:.*\(([0-9]+)\) minutes' "$cap_file" | grep -Eo '\(([0-9]+)\)' | tr -d '()' | tail -n1)
  fi
  if [[ -n "$est_min" ]]; then
    poll_s=$(( est_min * 60  ))
  fi
  (( poll_s += extra_s ))
  (( max_wait = poll_s > max_wait ? poll_s : max_wait ))
  smartctl -t "$MODE" "$disk" > "${RUN_DIR}/smart_trigger_${MODE}_$(basename "$disk").txt" 2>&1 || true
done

log "SMART ${MODE}: attente ~${max_wait}s…"
sleep "$max_wait"

# Collecte
fail=0
for disk in "${disks[@]}"; do
  b="$(basename "$disk")"
  smartctl -H -A "$disk" > "${RUN_DIR}/smart_health_${MODE}_${b}.txt" 2>&1 || true
  smartctl -l selftest "$disk" > "${RUN_DIR}/smart_selftest_${MODE}_${b}.txt" 2>&1 || true
  if grep -qiE 'SMART overall-health self-assessment test result: (FAILED|BAD)' "${RUN_DIR}/smart_health_${MODE}_${b}.txt"; then
    fail=1
  fi
done

if [[ $fail -eq 0 ]]; then echo "PASS" > "${RUN_DIR}/SMART_${MODE}.status"; else echo "FAIL" > "${RUN_DIR}/SMART_${MODE}.status"; fi

# hdparm bench (lecture non intrusive) pendant la phase courte
if [[ "${hdparm_enabled:-yes}" == "yes" && "$MODE" == "short" && $(have hdparm; echo $?) -eq 0 ]]; then
  for disk in "${disks[@]}"; do
    b="$(basename "$disk")"
    { 
      echo "=== hdparm -T (cache) ==="
      hdparm -T "$disk" 2>&1 || true
      echo "=== hdparm -t (buffered) ==="
      hdparm -t "$disk" 2>&1 || true
    } > "${RUN_DIR}/hdparm_${b}.txt"
  done
fi
