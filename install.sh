#!/usr/bin/env bash
# install.sh
set -Eeuo pipefail
IFS=$'\n\t'

# shellcheck disable=SC1091
. ./utils.sh

# Charge conf
CONF_LOADED=0
if [[ -f ./main.conf ]]; then . ./main.conf; CONF_LOADED=1; fi
if [[ $CONF_LOADED -eq 0 && -f /etc/cobot/main.conf ]]; then . /etc/cobot/main.conf; CONF_LOADED=1; fi
[[ $CONF_LOADED -eq 1 ]] || die "main.conf introuvable."

[[ $EUID -eq 0 ]] || die "Exécutez en root (sudo)."

ensure_dir "$logpath"
exec > >(tee -a "${logpath}/install.log") 2>&1

# Internet requis ici (APT + GLPI Agent)
if ! (have curl && curl -fsS --max-time 5 https://1.1.1.1 >/dev/null); then
  die "Internet indisponible: requis pour l'installation."
fi

have apt-get || die "APT requis."
export DEBIAN_FRONTEND=noninteractive
log "Mise à jour des dépôts…"
apt-get update -y
log "Installation des prérequis…"
apt-get install -y -f curl wget perl ca-certificates lsb-release smartmontools nvme-cli hdparm dmidecode pciutils usbutils memtester nfs-common stress-ng lm-sensors mesa-utils glmark2

# Installer GLPI Agent si absent
if ! have glpi-agent; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  agent="${tmp}/glpi-agent-installer.pl"
  log "Téléchargement GLPI Agent: ${glpiagentinstallurl}"
  curl -fsSL "$glpiagentinstallurl" -o "$agent" || die "Téléchargement installeur GLPI échoué."
  if [[ -n "${glpiagent_sha256:-}" ]]; then
    sha256sum "$agent" | awk '{print $1}' | grep -xq "$glpiagent_sha256" || die "Checksum SHA256 invalide pour l'installeur GLPI."
  fi
  log "Installation GLPI Agent…"
  perl "$agent" || die "Installation GLPI Agent échouée."
else
  log "GLPI Agent déjà présent."
fi

# Configurer agent.cfg minimalement
AGENTCFG="/etc/glpi-agent/agent.cfg"
if [[ -f "$AGENTCFG" ]]; then
  set_kv() {
    local key="$1" val="$2"
    if grep -qE "^\s*${key}\s*=" "$AGENTCFG"; then
      sed -i -E "s|^\s*${key}\s*=.*$|${key} = ${val}|g" "$AGENTCFG"
    else
      printf "%s = %s\n" "$key" "$val" >> "$AGENTCFG"
    fi
  }
  [[ -n "${glpiserver:-}" ]]   && set_kv "server" "$glpiserver"
  [[ -n "${httpuser:-}" ]]     && set_kv "user" "$httpuser"
  [[ -n "${httppassword:-}" ]] && set_kv "password" "$httppassword"
fi

# Initialisation capteurs (non bloquant)
if command -v sensors-detect >/dev/null 2>&1; then
  yes YES | sensors-detect --auto >/dev/null 2>&1 || true
fi

log "Installation terminée."
