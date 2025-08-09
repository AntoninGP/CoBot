#!/usr/bin/env bash
# mem.sh
set -Eeuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC1091
. ./utils.sh

# Charge conf
CONF_LOADED=0
if [[ -f ./main.conf ]]; then . ./main.conf; CONF_LOADED=1; fi
if [[ $CONF_LOADED -eq 0 && -f /etc/cobot/main.conf ]]; then . /etc/cobot/main.conf; CONF_LOADED=1; fi
[[ $CONF_LOADED -eq 1 ]] || die "main.conf introuvable."

have memtester || { echo "SKIP" > "${2:-.}/MEM_${1:-fast}.status"; exit 0; }

mode="${1:-}"
run_dir="${2:-}"
[[ -z "$mode" || -z "$run_dir" ]] && { echo "Usage: $0 <fast|long> <run_dir>"; exit 1; }

ensure_dir "$run_dir"

if [[ "$mode" == "fast" ]]; then
  size="${mem_fast_size_mb:-64}"
  passes="${mem_fast_passes:-1}"
else
  if [[ -n "${mem_long_size_mb:-}" ]]; then
    size="${mem_long_size_mb}"
  else
    # Auto: 1/4 de MemAvailable, max 512 MiB, min 128 MiB
    avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    avail_mb=$(( avail_kb / 1024  ))
    calc=$(( avail_mb / 4  ))
    size=$(( calc < 512 ? calc : 512  ))
    [[ $size -lt 128 ]] && size=128
  fi
  passes="${mem_long_passes:-2}"
fi

log "memtester ${mode}: ${size}M x ${passes} passe(s)"
if memtester "${size}M" "${passes}" > "${run_dir}/memtester_${mode}.log" 2>&1; then
  echo "PASS" > "${run_dir}/MEM_${mode}.status"
else
  echo "FAIL" > "${run_dir}/MEM_${mode}.status"
fi
