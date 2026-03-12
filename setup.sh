#!/bin/bash
# ============================================================
# setup_users.sh
# - Legge configurazione da user_config.conf
# - Rinomina utente debian → lzer0
# - Imposta password hashata e chiave SSH
# - Aggiunge lzer0 a tutti i gruppi privilegiati
# - Rimuove utente weston e relativa home
# - Configura SSH: no root login, solo lzer0 con password
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERR]${NC}   $1"; }

if [ "$(id -u)" -ne 0 ]; then
    err "Eseguire come root o con sudo"
    exit 1
fi

# ============================================================
# LETTURA CONFIGURAZIONE
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/user_config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    err "File di configurazione non trovato: ${CONFIG_FILE}"
    exit 1
fi

source "$CONFIG_FILE"

if [ -z "$LZER0_PASSWORD_HASH" ]; then
    err "LZER0_PASSWORD_HASH non impostato in user_config.conf"
    err "Generalo con: openssl passwd -6 'tuapassword'"
    exit 1
fi

if [ -z "$LZER0_SSH_PUBKEY" ]; then
    warn "LZER0_SSH_PUBKEY non impostato — accesso SSH solo con password"
fi

OLD_USER="debian"
NEW_USER="lzer0"

# ============================================================
# VERIFICA PRECONDIZIONI
# ============================================================

if ! id "$OLD_USER" &>/dev/null; then
    err "Utente '${OLD_USER}' non trovato. Uscita."
    exit 1
fi

if id "$NEW_USER" &>/dev/null; then
    err "Utente '${NEW_USER}' esiste già. Uscita."
    exit 1
fi

if who | grep -q "^${OLD_USER} "; then
    err "Utente '${OLD_USER}' risulta loggato. Eseguire solo da root senza sessioni attive."
    exit 1
fi

# ============================================================
# RINOMINA UTENTE debian → lzer0
# ============================================================

log "Rinomina utente '${OLD_USER}' → '${NEW_USER}'..."
usermod -l "$NEW_USER" "$OLD_USER"
groupmod -n "$NEW_USER" "$OLD_USER"
usermod -d "/home/${NEW_USER}" -m "$NEW_USER"
usermod -c "$NEW_USER" "$NEW_USER"
log "Utente rinominato correttamente."

# ============================================================
# IMPOSTA PASSWORD
# ============================================================

log "Impostazione password hashata..."
usermod -p "$LZER0_PASSWORD_HASH" "$NEW_USER"
log "Password impostata."

# ============================================================
# CHIAVE SSH
# ============================================================

if [ -n "$LZER0_SSH_PUBKEY" ]; then
    log "Configurazione chiave SSH pubblica..."
    SSH_DIR="/home/${NEW_USER}/.ssh"
    AUTH_KEYS="${SSH_DIR}/authorized_keys"
    mkdir -p "$SSH_DIR"
    echo "$LZER0_SSH_PUBKEY" > "$AUTH_KEYS"
    chmod 700 "$SSH_DIR"
    chmod 600 "$AUTH_KEYS"
    chown -R "${NEW_USER}:${NEW_USER}" "$SSH_DIR"
    log "Chiave SSH configurata."
fi

# ============================================================
# GRUPPI PRIVILEGIATI
# ============================================================

log "Aggiunta '${NEW_USER}' ai gruppi privilegiati..."

PRIV_GROUPS=(
    sudo adm dialout cdrom audio video plugdev users
    netdev bluetooth i2c gpio spi input tty disk kmem render kvm
)

ADDED=()
SKIPPED=()

for grp in "${PRIV_GROUPS[@]}"; do
    if getent group "$grp" &>/dev/null; then
        usermod -aG "$grp" "$NEW_USER"
        ADDED+=("$grp")
    else
        SKIPPED+=("$grp")
    fi
done

log "Gruppi aggiunti:  ${ADDED[*]}"
warn "Gruppi non presenti (ignorati): ${SKIPPED[*]}"

# ============================================================
# SUDOERS
# ============================================================

log "Configurazione sudoers per '${NEW_USER}'..."
echo "${NEW_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${NEW_USER}
chmod 440 /etc/sudoers.d/${NEW_USER}
rm -f /etc/sudoers.d/${OLD_USER}

# ============================================================
# RIMOZIONE UTENTE weston
# ============================================================

if id "weston" &>/dev/null; then
    log "Rimozione utente 'weston'..."
    pkill -u weston 2>/dev/null || true
    deluser --remove-home weston 2>/dev/null || userdel -r weston 2>/dev/null || true
    getent group weston  &>/dev/null && groupdel weston  2>/dev/null || true
    getent group wayland &>/dev/null && groupdel wayland 2>/dev/null || true
    log "Utente 'weston' rimosso."
else
    warn "Utente 'weston' non trovato, nulla da rimuovere."
fi

# ============================================================
# CONFIGURAZIONE SSH
# ============================================================

log "Configurazione sshd..."

SSHD_CONF="/etc/ssh/sshd_config"

# Backup
cp "$SSHD_CONF" "${SSHD_CONF}.bak_$(date +%Y%m%d_%H%M%S)"

# Funzione per impostare o aggiungere una direttiva sshd
set_sshd() {
    local key="$1"
    local val="$2"
    if grep -qE "^#?${key}\s" "$SSHD_CONF"; then
        sed -i "s|^#\?${key}\s.*|${key} ${val}|" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

set_sshd "PermitRootLogin"      "no"
set_sshd "PasswordAuthentication" "yes"
set_sshd "PubkeyAuthentication" "yes"
set_sshd "PermitEmptyPasswords" "no"
set_sshd "AllowUsers"           "$NEW_USER"

# Verifica sintassi sshd
if sshd -t 2>/dev/null; then
    log "Configurazione sshd valida."
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    log "Servizio SSH riavviato."
else
    err "Errore nella configurazione sshd! Ripristino backup..."
    cp "${SSHD_CONF}.bak_"* "$SSHD_CONF"
    exit 1
fi

# ============================================================
# VERIFICA FINALE
# ============================================================

echo ""
log "Verifica configurazione finale:"

echo ""
echo -e "  Utente ${NEW_USER}:"
if id "$NEW_USER" &>/dev/null; then
    echo -e "  ${GREEN}OK${NC}  utente esiste"
    echo      "      UID:    $(id -u ${NEW_USER})"
    echo      "      GID:    $(id -g ${NEW_USER})"
    echo      "      Gruppi: $(groups ${NEW_USER} | cut -d: -f2)"
    echo      "      Home:   $(getent passwd ${NEW_USER} | cut -d: -f6)"
    echo      "      Shell:  $(getent passwd ${NEW_USER} | cut -d: -f7)"
else
    echo -e "  ${RED}KO${NC}  utente non trovato!"
fi

echo ""
echo -e "  Password:"
if getent shadow "$NEW_USER" | cut -d: -f2 | grep -qv '^\*\|^!\|^$'; then
    echo -e "  ${GREEN}OK${NC}  password impostata"
else
    echo -e "  ${RED}KO${NC}  password non impostata"
fi

echo ""
echo -e "  Chiave SSH:"
if [ -f "/home/${NEW_USER}/.ssh/authorized_keys" ]; then
    echo -e "  ${GREEN}OK${NC}  authorized_keys presente"
else
    echo -e "  ${YELLOW}--${NC}  nessuna chiave SSH configurata"
fi

echo ""
echo -e "  Home /home/${NEW_USER}:"
if [ -d "/home/${NEW_USER}" ]; then
    OWNER=$(stat -c '%U' /home/${NEW_USER})
    echo -e "  ${GREEN}OK${NC}  directory esiste (owner: ${OWNER})"
else
    echo -e "  ${RED}KO${NC}  directory non trovata!"
fi

echo ""
echo -e "  Sudo NOPASSWD:"
if sudo -u "$NEW_USER" sudo -n true 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC}  funzionante"
else
    echo -e "  ${RED}KO${NC}  non funziona"
fi

echo ""
echo -e "  SSH - PermitRootLogin:"
if grep -q "^PermitRootLogin no" "$SSHD_CONF"; then
    echo -e "  ${GREEN}OK${NC}  root login disabilitato"
else
    echo -e "  ${RED}KO${NC}  verificare manualmente sshd_config"
fi

echo ""
echo -e "  SSH - AllowUsers:"
if grep -q "^AllowUsers ${NEW_USER}" "$SSHD_CONF"; then
    echo -e "  ${GREEN}OK${NC}  solo '${NEW_USER}' autorizzato"
else
    echo -e "  ${RED}KO${NC}  verificare manualmente sshd_config"
fi

echo ""
echo -e "  Utente weston:"
if id "weston" &>/dev/null; then
    echo -e "  ${RED}KO${NC}  utente ancora presente!"
else
    echo -e "  ${GREEN}OK${NC}  rimosso correttamente"
fi

echo ""
log "Setup completato."
warn "Testa il login SSH come '${NEW_USER}' prima di chiudere questa sessione!"
