#!/bin/bash
# ============================================================
# cleanup.sh
# Rimozione pacchetti inutili su sistema headless Variscite
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

log "Inizio pulizia sistema headless..."
echo ""

# ============================================================
# PACCHETTI DA RIMUOVERE
# ============================================================

PACKAGES=(
    # Mesa / GPU / OpenGL / Vulkan
    mesa-vdpau-drivers
    mesa-va-drivers
    mesa-vulkan-drivers
    libgl1-mesa-dri
    libvulkan-dev
    libvulkan1

    # Multimedia / GStreamer / FFmpeg
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-plugins-good
    libavfilter8
    libavcodec59
    libavformat59
    libavutil57
    libswscale6
    libswresample4

    # Audio / Voce
    libcodec2-1.0
    libflite1
    pocketsphinx-en-us
    pulseaudio
    pipewire

    # GTK / GNOME / Icone / Temi
    adwaita-icon-theme
    libgtk-3-common
    libgtk-3-0
    libgtk-3-bin

    # Stampa / PDF / Font
    libgs10
    ghostscript
    poppler-data
    libpoppler126
    fonts-urw-base35
    cups
    cups-common
    cups-core-drivers

    # Grafica / ImageMagick
    libmagickcore-6.q16-6
    imagemagick
    imagemagick-6-common

    # Editor (opzionale in produzione)
    vim-runtime
    vim-common
    vim-tiny

    # Localizzazione / Metadati inutili
    iso-codes

    # Solver / tool di nicchia
    libz3-4

    # Qt5 (tutti i pacchetti)
    libqt5*
    qtwayland5
    qt5-gtk-platformtheme
    qt5ct

    # Wayland
    wayland-protocols
    libwayland-client0
    libwayland-cursor0
    libwayland-egl1
    libwayland-server0
    libwayland-dev
    weston
    xwayland
)

# ============================================================
# RIMOZIONE
# ============================================================

log "Pacchetti da rimuovere:"
for pkg in "${PACKAGES[@]}"; do
    echo "  - $pkg"
done
echo ""

warn "Procedere con la rimozione? [s/N]"
read -r confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
    log "Operazione annullata."
    exit 0
fi

echo ""
log "Rimozione pacchetti in corso..."

# Usa apt per gestire correttamente i glob (es. libqt5*)
apt-get remove --purge -y "${PACKAGES[@]}" 2>/dev/null || true

# Rimozione esplicita glob Qt5 e Wayland tramite dpkg list
log "Rimozione forzata pacchetti Qt5/Wayland residui..."
dpkg -l 'libqt5*' 2>/dev/null | grep '^ii' | awk '{print $2}' | xargs -r apt-get remove --purge -y
dpkg -l 'qt5*'    2>/dev/null | grep '^ii' | awk '{print $2}' | xargs -r apt-get remove --purge -y
dpkg -l '*wayland*' 2>/dev/null | grep '^ii' | awk '{print $2}' | xargs -r apt-get remove --purge -y

echo ""
log "Pulizia dipendenze orfane..."
apt-get autoremove --purge -y

log "Pulizia cache apt..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
log "Spazio disco dopo pulizia:"
df -h /

echo ""
log "Pulizia completata."
