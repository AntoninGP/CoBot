#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

log()  { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
die()  { log "ERREUR: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_dir() { mkdir -p "$1"; }

read_inventory() {
  local regex="${inventory_regex:-^[A-Za-z0-9._-]{3,64}$}"
  local inv=""
  while :; do
    read -r -p "Numéro d'inventaire (3–64, lettres/chiffres/._-): " inv
    if [[ "$inv" =~ $regex ]]; then
      echo "$inv"
      return 0
    fi
    echo "Format invalide. Réessaie."
  done
}
