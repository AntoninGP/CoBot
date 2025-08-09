#!/usr/bin/env bash
# gpu.sh - GPU tests using glmark2 (off-screen). Fast/Long.
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

have glmark2 || { echo "SKIP" > "${run_dir}/GPU_${mode}.status"; exit 0; }

# Info if available
if have glxinfo; then glxinfo -B > "${run_dir}/gpu_glxinfo_${mode}.txt" 2>&1 || true; fi
if have nvidia-smi; then nvidia-smi -L > "${run_dir}/gpu_nvidia_${mode}.txt" 2>&1 || true; fi

GPU_SHORT_DURATION_S="${gpu_short_duration_s:-30}"
GPU_LONG_TIMEOUT_S="${gpu_long_timeout_s:-300}"

log_file="${run_dir}/gpu_glmark2_${mode}.log"

if [[ "$mode" == "fast" ]]; then
  # Short: one light scene off-screen
  timeout "${GPU_SHORT_DURATION_S}"s glmark2 --off-screen -b build:duration="${GPU_SHORT_DURATION_S}" > "$log_file" 2>&1 || true
  ec=$?
  status="PASS"
  if [[ $ec -ne 0 && $ec -ne 124 ]]; then status="FAIL"; fi
  echo "$status" > "${run_dir}/GPU_${mode}.status"
  exit 0
else
  # Long: run-forever window, treat timeout as PASS
  timeout "${GPU_LONG_TIMEOUT_S}"s glmark2 --off-screen --run-forever > "$log_file" 2>&1 || true
  ec=$?
  status="PASS"
  if [[ $ec -ne 0 && $ec -ne 124 ]]; then status="FAIL"; fi
  echo "$status" > "${run_dir}/GPU_${mode}.status"
fi
