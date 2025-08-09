# CoBot — Inventaire + Tests rapides / longs conditionnels

Objectif : inventorier une machine et exécuter des tests matériels clés en un run structuré :
rapide d’abord, puis long uniquement si le test rapide passe (RAM, disques, CPU, GPU).
Internet est requis uniquement pour l’installation/mise à jour ; l’exécution peut se faire en LAN.

Date : 2025-08-09

---

## Contenu du pack
- install.sh — Installe les prérequis APT + GLPI Agent, initialise les capteurs (best‑effort).
- script.sh — Orchestrateur : saisie inventaire → fast tests → longs si PASS → envoi GLPI → exports → résumé.
- mem.sh — RAM (memtester fast/long).
- smart.sh — Stockage SMART short/long + hdparm -Tt.
- cpu.sh — CPU (stress‑ng fast/long, contrôle thermique optionnel via sensors).
- gpu.sh — GPU (glmark2 off‑screen fast/long, inventaire glxinfo/nvidia‑smi si dispo).
- utils.sh — utilitaires communs.
- main.conf — configuration centrale.
- templates/inventory.dumb — modèle JSON pour GLPI.
- CHANGELOG.md, README.md — docs.

---

## Prérequis
- Debian/Ubuntu (ou dérivées) avec apt-get.
- root requis pour installer et pour les tests matériels.
- Internet requis lors du install.sh (APT + téléchargement GLPI Agent). Exécution ensuite possible sans Internet public si GLPI est en LAN.

---

## Installation
```
sudo bash install.sh
```
- Met à jour les dépôts et installe :
  `curl wget perl ca-certificates lsb-release smartmontools nvme-cli hdparm dmidecode pciutils usbutils memtester nfs-common stress-ng lm-sensors mesa-utils glmark2`
- Télécharge et installe GLPI Agent depuis `glpiagentinstallurl` (vérifie SHA256 si fourni).
- Met à jour `/etc/glpi-agent/agent.cfg` avec `server`/`user`/`password` si définis.
- Lance `sensors-detect --auto` best‑effort pour activer les sondes.

---

## Utilisation (orchestrateur)
```
bash script.sh               # tests rapides puis longs conditionnels
bash script.sh --fast-only   # tests rapides uniquement
bash script.sh --server=https://glpi.intra.local  # override GLPI pour ce run
```
**Orchestration :**
1) saisie du numéro d’inventaire (validation regex),
2) création du dossier `{{logpath}}/{{INVENTAIRE}}/{{YYYYmmdd-HHMMSS}}/`,
3) **FAST** : RAM (memtester), Disques (SMART short + hdparm), CPU (stress‑ng), GPU (glmark2 off‑screen),
4) **LONG** si PASS des tests rapides correspondants,
5) génération `inventory.json` + **envoi GLPI** (log dédié),
6) **exports** NFS/FTP (optionnels),
7) **résumé** (`SUMMARY.txt`).

---

## Paramètres `main.conf`

### GLPI & sources
- `glpiserver` (requis) — ex : `https://glpi.intra.local`
- `httpuser`, `httppassword` — auth basique éventuelle
- `glpiagentinstallurl` (requis) — installeur GLPI Agent (Perl “with snap”)
- `glpiagent_sha256` (optionnel) — vérification d’intégrité
- `downloadsource` (optionnel) — base pour auto‑update manuel (si vous l’ajoutez)

### Journaux / exports
- `logpath` (def. `/var/log/cobot`)
- `nfspath`, `nfsmount` — export NFS optionnel
- `ftphost`, `ftpuser`, `ftppassword`, `ftpdirectory` — export FTP optionnel

### Mémoire (memtester)
- `mem_fast_size_mb` (def. `64`), `mem_fast_passes` (def. `1`)
- `mem_long_size_mb` (def. vide : auto min(512, MemAvailable/4), min 128)
- `mem_long_passes` (def. `2`)

### SMART (disques)
- `smart_short_extra_s` (def. `30`) — marge ajoutée au temps recommandé
- `smart_long_extra_s` (def. `60`) — marge ajoutée
- `smart_nvme` (yes/no, def. `yes`)
- `smart_sata` (yes/no, def. `yes`)
- `hdparm_enabled` (yes/no, def. `yes`) — bench lecture non destructif

### CPU
- `cpu_fast_timeout_s` (def. `60`) — durée du stress rapide
- `cpu_long_timeout_s` (def. `300`) — durée du stress long
- `cpu_temp_max_c` (vide par défaut) — si défini et `sensors` dispo → **FAIL** si température CPU > seuil

### GPU
- `gpu_short_duration_s` (def. `30`) — durée du test court (`glmark2 --off-screen -b build`)
- `gpu_long_timeout_s` (def. `300`) — fenêtre du test long (`--run-forever`, timeout considéré PASS)

### Validation inventaire
- `inventory_regex` (def. `^[A-Za-z0-9._-]{{3,64}}$`) — contrainte de saisie

---

## Exécution directe des modules (avancé)

### RAM
```
bash mem.sh fast <run_dir>
bash mem.sh long <run_dir>
```
→ écrit `MEM_fast.status` / `MEM_long.status` (PASS/FAIL/SKIP) + logs.

### Disques
```
bash smart.sh short <run_dir>
bash smart.sh long  <run_dir>
```
→ détecte NVMe+SATA/SCSI, attend **temps recommandé + marge**, collecte SMART, produit statuts + **hdparm** (en mode short).

### CPU
```
bash cpu.sh fast <run_dir>
bash cpu.sh long <run_dir>
```
→ `stress-ng`, `sensors` avant/après (si dispo), seuil `cpu_temp_max_c` optionnel.

### GPU
```
bash gpu.sh fast <run_dir>
bash gpu.sh long <run_dir>
```
→ `glmark2` off‑screen; collecte `glxinfo -B`/`nvidia-smi -L` si disponibles.

---

## Sorties
Dans `{{logpath}}/{{INVENTAIRE}}/{{YYYYmmdd-HHMMSS}}/` :
`inventory.json`, `system_info.txt`, `memtester_*.log`, `MEM_*.status`, `smart_*`, `SMART_*.status`, `hdparm_*.txt`, `cpu_*`, `CPU_*.status`, `gpu_*`, `GPU_*.status`, `glpi-agent.log`, `SUMMARY.txt`.

---

## Exemple de configuration
Un exemple prêt à l’emploi est fourni : **`main.conf.example`** (à copier/adapter).

_Remarque : si besoin, faites `chmod +x *.sh` après extraction._
