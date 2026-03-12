#!/bin/bash
# ============================================================
# install.sh
# Installazione pacchetti su sistema headless Variscite
# ============================================================

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERR]${NC}   $1"; }

# Verifica root
if [ "$(id -u)" -ne 0 ]; then
    err "Eseguire come root o con sudo"
    exit 1
fi

log "Inizio installazione pacchetti..."
echo ""

# ============================================================
# PACCHETTI DA INSTALLARE
# ============================================================

PACKAGES=(
    dbus                  # Comunicazione inter-processo
    gawk                  # Elaborazione testi/dati
    gensio-bin            # Gestione connessioni seriali/rete
    gfortran              # Compilatore Fortran
    git-core              # Controllo versione Git
    iftop                 # Monitor traffico di rete
    iotop                 # Monitor I/O su disco
    libcap-dev            # Linux capabilities
    lm-sensors            # Lettura sensori hardware
    libatlas-base-dev     # Algebra lineare ottimizzata (NumPy/SciPy)
    mlocate               # Ricerca file indicizzata
    nginx                 # Web server / reverse proxy
    proj-bin              # Proiezioni cartografiche
    python3-pip           # Gestore pacchetti Python
    python3-venv          # Ambienti virtuali Python
    screen                # Multiplexer terminale
    ser2net               # Bridge seriale/rete
    socat                 # Relay connessioni dati
)

# ============================================================
# INSTALLAZIONE PACCHETTI STANDARD
# ============================================================

log "Aggiornamento lista pacchetti..."
apt-get update

echo ""
log "Pacchetti da installare:"
for pkg in "${PACKAGES[@]}"; do
    echo "  - $pkg"
done
echo ""

warn "Procedere con l'installazione? [s/N]"
read -r confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
    log "Operazione annullata."
    exit 0
fi

echo ""
log "Installazione in corso..."
apt-get install -y "${PACKAGES[@]}"

# ============================================================
# OPENVPN3 (repo ufficiale OpenVPN - ARM64/Variscite)
# ============================================================

log "Configurazione repository OpenVPN3..."

apt-get install -y curl ca-certificates gnupg

ARCH=$(dpkg --print-architecture)
DISTRO=$(lsb_release -cs 2>/dev/null || echo "bookworm")
KEY_ID="551180AB92C319F8"
KEYRING="/etc/apt/keyrings/openvpn.gpg"
SOURCELIST="/etc/apt/sources.list.d/openvpn3.list"

log "Arch: ${ARCH} | Distro: ${DISTRO}"

# Rimuove eventuali file residui da tentativi precedenti
rm -f "$KEYRING" "$SOURCELIST"
mkdir -p /etc/apt/keyrings

# Import chiave GPG via keyserver Ubuntu
log "Import chiave GPG OpenVPN (${KEY_ID})..."
gpg --no-default-keyring \
    --keyring "gnupg-ring:${KEYRING}" \
    --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys "$KEY_ID"
chmod 644 "$KEYRING"

# Aggiunta repo
echo "deb [arch=${ARCH} signed-by=${KEYRING}] \
https://packages.openvpn.net/openvpn3/debian ${DISTRO} main" \
    > "$SOURCELIST"

log "Installazione openvpn3..."
apt-get update
apt-get install -y openvpn3

# ============================================================
# VERIFICA FINALE
# ============================================================

echo ""
log "Verifica pacchetti installati:"
ALL_OK=true
for pkg in "${PACKAGES[@]}" openvpn3; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        echo -e "  ${GREEN}OK${NC}  $pkg"
    else
        echo -e "  ${RED}KO${NC}  $pkg"
        ALL_OK=false
    fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    log "Tutti i pacchetti installati correttamente."
else
    warn "Alcuni pacchetti non risultano installati. Verificare manualmente."
fi

echo ""
log "Spazio disco dopo installazione:"
df -h /

echo ""
log "Installazione completata."
