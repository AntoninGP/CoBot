#!/usr/bin/env bash
# script.sh (orchestrator) with CPU/GPU conditional long tests
set -Eeuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC1091
. ./utils.sh

# Load conf
CONF_LOADED=0
if [[ -f ./main.conf ]]; then . ./main.conf; CONF_LOADED=1; fi
if [[ $CONF_LOADED -eq 0 && -f /etc/cobot/main.conf ]]; then . /etc/cobot/main.conf; CONF_LOADED=1; fi
[[ $CONF_LOADED -eq 1 ]] || die "main.conf introuvable."

ensure_dir "$logpath"

FAST_ONLY=0
SERVEROPT="$glpiserver"
for arg in "$@"; do
  case "$arg" in
    --fast-only) FAST_ONLY=1 ;;
    --server=*)  SERVEROPT="${arg#--server=}" ;;
    *) ;;
  esac
done

ninventaire="$(read_inventory)"
ts="$(date +'%Y%m%d-%H%M%S')"
run_dir="${logpath%/}/${ninventaire}/${ts}"
ensure_dir "$run_dir"

# Inventory JSON
tmpl="./templates/inventory.dumb"
[[ -f "$tmpl" ]] || tmpl="/etc/cobot/inventory.dumb"
if [[ ! -f "$tmpl" ]]; then
  echo '{"Content":[{"name":"dumbname"}]}' > "${run_dir}/inventory.json.tmpl"
  tmpl="${run_dir}/inventory.json.tmpl"
fi
inv_json="${run_dir}/inventory.json"
cp "$tmpl" "$inv_json"
sed -i "s/dumbname/${ninventaire}/g" "$inv_json"

# System info
{
  echo "=== date ==="; date
  echo "=== uname ==="; uname -a || true
  echo "=== lsb_release ==="; lsb_release -a 2>/dev/null || true
  echo "=== lscpu ==="; lscpu 2>/dev/null || true
  echo "=== free -h ==="; free -h || true
  echo "=== lsblk ==="; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,SERIAL || true
} > "${run_dir}/system_info.txt"

# 1) FAST tests: MEM + SMART + CPU + GPU
log "Tests rapides: MEM fast + SMART short + CPU fast + GPU fast (hdparm inclus via smart.sh)…"
bash ./mem.sh fast "${run_dir}" || true
bash ./smart.sh short "${run_dir}" || true
bash ./cpu.sh fast "${run_dir}" || true
bash ./gpu.sh fast "${run_dir}" || true

mem_fast_status="$(cat "${run_dir}/MEM_fast.status" 2>/dev/null || echo SKIP)"
smart_short_status="$(cat "${run_dir}/SMART_short.status" 2>/dev/null || echo SKIP)"
cpu_fast_status="$(cat "${run_dir}/CPU_fast.status" 2>/dev/null || echo SKIP)"
gpu_fast_status="$(cat "${run_dir}/GPU_fast.status" 2>/dev/null || echo SKIP)"

# 2) LONG tests conditionnels
if [[ $FAST_ONLY -eq 0 ]]; then
  if [[ "$mem_fast_status" == "PASS" ]]; then
    log "MEM fast PASS → MEM long…"
    bash ./mem.sh long "${run_dir}" || true
  else
    log "MEM fast non-PASS → skip MEM long."
  fi

  if [[ "$smart_short_status" == "PASS" ]]; then
    log "SMART short PASS → SMART long…"
    bash ./smart.sh long "${run_dir}" || true
  else
    log "SMART short non-PASS → skip SMART long."
  fi

  if [[ "$cpu_fast_status" == "PASS" ]]; then
    log "CPU fast PASS → CPU long…"
    bash ./cpu.sh long "${run_dir}" || true
  else
    log "CPU fast non-PASS → skip CPU long."
  fi

  if [[ "$gpu_fast_status" == "PASS" ]]; then
    log "GPU fast PASS → GPU long…"
    bash ./gpu.sh long "${run_dir}" || true
  else
    log "GPU fast non-PASS → skip GPU long."
  fi
fi

mem_long_status="$(cat "${run_dir}/MEM_long.status" 2>/dev/null || echo SKIP)"
smart_long_status="$(cat "${run_dir}/SMART_long.status" 2>/dev/null || echo SKIP)"
cpu_long_status="$(cat "${run_dir}/CPU_long.status" 2>/dev/null || echo SKIP)"
gpu_long_status="$(cat "${run_dir}/GPU_long.status" 2>/dev/null || echo SKIP)"

# 3) glpi-agent
glpi_status="SKIP"
if have glpi-agent; then
  log "Exécution glpi-agent vers ${SERVEROPT}…"
  if glpi-agent \
      --server "$SERVEROPT" \
      --get-wsdl \
      --debug \
      --logger file \
      --logfile "${run_dir}/glpi-agent.log" \
      --additional-content "$inv_json"; then
    glpi_status="PASS"
  else
    glpi_status="FAIL"
  fi
else
  log "glpi-agent manquant (exécutez install.sh)."
fi

# 4) Exports optionnels
if [[ -n "${nfspath:-}" ]]; then
  mkdir -p "${nfsmount}"
  if ! mountpoint -q "${nfsmount}"; then
    mount -t nfs -o vers=3,proto=tcp,soft,timeo=60,retrans=2 "${nfspath}" "${nfsmount}" || true
  fi
  if mountpoint -q "${nfsmount}"; then
    dest="${nfsmount%/}/${ninventaire}/${ts}"
    mkdir -p "$dest"
    cp -a "${run_dir}/." "$dest/"
    log "Logs copiés vers NFS: ${dest}"
  fi
fi

if [[ -n "${ftphost:-}" && -n "${ftpuser:-}" && -n "${ftppassword:-}" && -n "${ftpdirectory:-}" ]]; then
  tar_path="${run_dir}.tar.gz"
  tar -czf "$tar_path" -C "${run_dir}" .
  curl -T "$tar_path" "ftp://${ftphost}/${ftpdirectory}/" --user "${ftpuser}:${ftppassword}" || true
  log "Archive envoyée en FTP (si crédentials valides)."
fi

# 5) Résumé
mem_overall="$mem_fast_status"
if [[ "$mem_long_status" == "PASS" ]]; then mem_overall="PASS(long)"; fi
if [[ "$mem_fast_status" == "FAIL" || "$mem_long_status" == "FAIL" ]]; then mem_overall="FAIL"; fi

smart_overall="$smart_short_status"
if [[ "$smart_long_status" == "PASS" ]]; then smart_overall="PASS(long)"; fi
if [[ "$smart_short_status" == "FAIL" || "$smart_long_status" == "FAIL" ]]; then smart_overall="FAIL"; fi

cpu_overall="$cpu_fast_status"
if [[ "$cpu_long_status" == "PASS" ]]; then cpu_overall="PASS(long)"; fi
if [[ "$cpu_fast_status" == "FAIL" || "$cpu_long_status" == "FAIL" ]]; then cpu_overall="FAIL"; fi

gpu_overall="$gpu_fast_status"
if [[ "$gpu_long_status" == "PASS" ]]; then gpu_overall="PASS(long)"; fi
if [[ "$gpu_fast_status" == "FAIL" || "$gpu_long_status" == "FAIL" ]]; then gpu_overall="FAIL"; fi

overall="PASS"
for s in "$mem_overall" "$smart_overall" "$cpu_overall" "$gpu_overall" "$glpi_status"; do
  [[ "$s" == "FAIL" ]] && overall="FAIL"
done

cat > "${run_dir}/SUMMARY.txt" <<EOF
Inventory : ${ninventaire}
Run dir   : ${run_dir}
GLPI      : ${SERVEROPT}

RESULTATS
- MEM     : fast=${mem_fast_status} long=${mem_long_status} → ${mem_overall}
- SMART   : short=${smart_short_status} long=${smart_long_status} → ${smart_overall}
- CPU     : fast=${cpu_fast_status} long=${cpu_long_status} → ${cpu_overall}
- GPU     : fast=${gpu_fast_status} long=${gpu_long_status} → ${gpu_overall}
- GLPI    : ${glpi_status}

Overall  : ${overall}
EOF

log "Terminé. Résumé: ${run_dir}/SUMMARY.txt"
