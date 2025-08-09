#!/usr/bin/env bash
# cpu.sh - CPU stress tests (fast/long) with optional temp threshold
set -Eeuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC1091
. ./utils.sh

# Load conf
CONF_LOADED=0
if [[ -f ./main.conf ]]; then . ./main.conf; CONF_LOADED=1; fi
if [[ $CONF_LOADED -eq 0 && -f /etc/cobot/main.conf ]]; then . /etc/cobot/main.conf; CONF_LOADED=1; fi
[[ $CONF_LOADED -eq 1 ]] || die "main.conf introuvable."

mode="${1:-}"
run_dir="${2:-}"
[[ -z "$mode" || -z "$run_dir" ]] && { echo "Usage: $0 <fast|long> <run_dir>"; exit 1; }

ensure_dir "$run_dir"

have stress-ng || { echo "SKIP" > "${run_dir}/CPU_${mode}.status"; exit 0; }

CPU_FAST_TIMEOUT_S="${cpu_fast_timeout_s:-60}"
CPU_LONG_TIMEOUT_S="${cpu_long_timeout_s:-300}"
CPU_TEMP_MAX_C="${cpu_temp_max_c:-}"   # empty = no temp check

sensors_log_before="${run_dir}/cpu_sensors_before_${mode}.txt"
sensors_log_after="${run_dir}/cpu_sensors_after_${mode}.txt"
metrics_log="${run_dir}/cpu_stress_${mode}.log"

# Capture sensors before
if have sensors; then sensors > "$sensors_log_before" 2>&1 || true; fi

# Run stress
if [[ "$mode" == "fast" ]]; then
  log "CPU fast: stress-ng for ${CPU_FAST_TIMEOUT_S}s"
  timeout "${CPU_FAST_TIMEOUT_S}"s stress-ng --cpu 0 --timeout "${CPU_FAST_TIMEOUT_S}"s --metrics-brief > "$metrics_log" 2>&1 || true
else
  log "CPU long: stress-ng for ${CPU_LONG_TIMEOUT_S}s"
  timeout "${CPU_LONG_TIMEOUT_S}"s stress-ng --cpu 0 --timeout "${CPU_LONG_TIMEOUT_S}"s --metrics-brief > "$metrics_log" 2>&1 || true
fi

ec=$?
# Capture sensors after
if have sensors; then sensors > "$sensors_log_after" 2>&1 || true; fi

status="PASS"
# Exit code 124 (timeout) is considered OK
if [[ $ec -ne 0 && $ec -ne 124 ]]; then
  status="FAIL"
fi

# Temperature check if available
if [[ -n "$CPU_TEMP_MAX_C" && -f "$sensors_log_after" ]]; then
  max_t=$(grep -Eo '[+ ]?[0-9]+(\.[0-9]+)?°C' "$sensors_log_after" | tr -d '+' | sed 's/°C//' | awk 'BEGIN{m=-273}{if($1>m)m=$1}END{print m+0}' 2>/dev/null || echo 0)
  if [[ -n "$max_t" ]]; then
    echo "Max CPU temp observed: ${max_t}C (threshold ${CPU_TEMP_MAX_C}C)" >> "$metrics_log"
    awk -v t="$CPU_TEMP_MAX_C" -v m="$max_t" 'BEGIN{ if(m>t) exit 1; else exit 0 }'
    if [[ $? -ne 0 ]]; then
      status="FAIL"
      echo "Temperature threshold exceeded" >> "$metrics_log"
    fi
  fi
fi

echo "$status" > "${run_dir}/CPU_${mode}.status"
