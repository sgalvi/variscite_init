#!/bin/bash
# ============================================================
# setup_users.sh
# - Legge configurazione da user_config.conf
# - Rinomina utente debian → lzer0 (se non già fatto)
# - Imposta password hashata e chiave SSH
# - Aggiunge lzer0 a tutti i gruppi privilegiati
# - Imposta hostname
# - Rimuove utente weston e relativa home
# - Configura SSH: no root login, solo lzer0 con password
# Idempotente: può essere rieseguito senza danni
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
skip() { echo -e "${CYAN}[SKIP]${NC}  $1"; }
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

DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-LZER0-PRO}"

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
# STEP 1: RINOMINA UTENTE debian → lzer0
# ============================================================

if id "$NEW_USER" &>/dev/null; then
    skip "Utente '${NEW_USER}' esiste già, rinomina saltata."
elif id "$OLD_USER" &>/dev/null; then
    if who | grep -q "^${OLD_USER} "; then
        err "Utente '${OLD_USER}' risulta loggato. Eseguire solo da root senza sessioni attive."
        exit 1
    fi
    log "Rinomina utente '${OLD_USER}' → '${NEW_USER}'..."
    usermod -l "$NEW_USER" "$OLD_USER"
    groupmod -n "$NEW_USER" "$OLD_USER"
    usermod -d "/home/${NEW_USER}" -m "$NEW_USER"
    usermod -c "$NEW_USER" "$NEW_USER"
    log "Utente rinominato."
else
    err "Né '${OLD_USER}' né '${NEW_USER}' trovati. Impossibile procedere."
    exit 1
fi

# ============================================================
# STEP 2: IMPOSTA PASSWORD
# ============================================================

log "Impostazione password hashata..."
usermod -p "$LZER0_PASSWORD_HASH" "$NEW_USER"
log "Password impostata."

# ============================================================
# STEP 3: CHIAVE SSH
# ============================================================

SSH_DIR="/home/${NEW_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

if [ -n "$LZER0_SSH_PUBKEY" ]; then
    if [ -f "$AUTH_KEYS" ] && grep -qF "$LZER0_SSH_PUBKEY" "$AUTH_KEYS"; then
        skip "Chiave SSH già presente in authorized_keys."
    else
        log "Configurazione chiave SSH pubblica..."
        mkdir -p "$SSH_DIR"
        echo "$LZER0_SSH_PUBKEY" >> "$AUTH_KEYS"
        chmod 700 "$SSH_DIR"
        chmod 600 "$AUTH_KEYS"
        chown -R "${NEW_USER}:${NEW_USER}" "$SSH_DIR"
        log "Chiave SSH configurata."
    fi
fi

# ============================================================
# STEP 4: GRUPPI PRIVILEGIATI
# ============================================================

log "Aggiunta '${NEW_USER}' ai gruppi privilegiati..."

PRIV_GROUPS=(
    sudo adm dialout cdrom audio video plugdev users
    netdev bluetooth i2c gpio spi input tty disk kmem render kvm
)

ADDED=()
SKIPPED=()

for grp in "${PRIV_GROUPS[@]}"; do
    if ! getent group "$grp" &>/dev/null; then
        SKIPPED+=("$grp")
    elif id -nG "$NEW_USER" | grep -qw "$grp"; then
        SKIPPED+=("$grp(già membro)")
    else
        usermod -aG "$grp" "$NEW_USER"
        ADDED+=("$grp")
    fi
done

[ ${#ADDED[@]}   -gt 0 ] && log  "Gruppi aggiunti:  ${ADDED[*]}"
[ ${#SKIPPED[@]} -gt 0 ] && skip "Gruppi saltati:   ${SKIPPED[*]}"

# ============================================================
# STEP 5: SUDOERS
# ============================================================

if [ -f "/etc/sudoers.d/${NEW_USER}" ]; then
    skip "Sudoers per '${NEW_USER}' già configurato."
else
    log "Configurazione sudoers per '${NEW_USER}'..."
    echo "${NEW_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${NEW_USER}
    chmod 440 /etc/sudoers.d/${NEW_USER}
    log "Sudoers configurato."
fi
rm -f /etc/sudoers.d/${OLD_USER}

# ============================================================
# STEP 6: HOSTNAME
# ============================================================

CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" = "$DEVICE_HOSTNAME" ] && [ "$(cat /etc/hostname)" = "$DEVICE_HOSTNAME" ]; then
    skip "Hostname già impostato: ${DEVICE_HOSTNAME}"
else
    log "Impostazione hostname '${DEVICE_HOSTNAME}'..."
    echo "$DEVICE_HOSTNAME" > /etc/hostname
    # Aggiorna o aggiunge riga 127.0.1.1
    if grep -q "127\.0\.1\.1" /etc/hosts; then
        sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${DEVICE_HOSTNAME}/" /etc/hosts
    else
        echo -e "127.0.1.1\t${DEVICE_HOSTNAME}" >> /etc/hosts
    fi
    hostname "$DEVICE_HOSTNAME"
    log "Hostname impostato: $(hostname)"
fi

# ============================================================
# STEP 7: RIMOZIONE UTENTE weston
# ============================================================

if id "weston" &>/dev/null; then
    log "Rimozione utente 'weston'..."
    pkill -u weston 2>/dev/null || true
    deluser --remove-home weston 2>/dev/null || userdel -r weston 2>/dev/null || true
    getent group weston  &>/dev/null && groupdel weston  2>/dev/null || true
    getent group wayland &>/dev/null && groupdel wayland 2>/dev/null || true
    log "Utente 'weston' rimosso."
else
    skip "Utente 'weston' non presente, nulla da rimuovere."
fi

# ============================================================
# STEP 8: CONFIGURAZIONE SSH
# ============================================================

SSHD_CONF="/etc/ssh/sshd_config"

set_sshd() {
    local key="$1"
    local val="$2"
    if grep -qE "^#?${key}\s" "$SSHD_CONF"; then
        sed -i "s|^#\?${key}\s.*|${key} ${val}|" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

SSHD_NEEDS_UPDATE=false
grep -q "^PermitRootLogin no"           "$SSHD_CONF" || SSHD_NEEDS_UPDATE=true
grep -q "^AllowUsers ${NEW_USER}"       "$SSHD_CONF" || SSHD_NEEDS_UPDATE=true
grep -q "^PasswordAuthentication yes"   "$SSHD_CONF" || SSHD_NEEDS_UPDATE=true

if [ "$SSHD_NEEDS_UPDATE" = false ]; then
    skip "Configurazione sshd già aggiornata."
else
    log "Configurazione sshd..."
    cp "$SSHD_CONF" "${SSHD_CONF}.bak_$(date +%Y%m%d_%H%M%S)"
    set_sshd "PermitRootLogin"          "no"
    set_sshd "PasswordAuthentication"   "yes"
    set_sshd "PubkeyAuthentication"     "yes"
    set_sshd "PermitEmptyPasswords"     "no"
    set_sshd "AllowUsers"               "$NEW_USER"

    if sshd -t 2>/dev/null; then
        log "Configurazione sshd valida."
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
        log "Servizio SSH riavviato."
    else
        err "Errore nella configurazione sshd! Ripristino backup..."
        cp "$(ls -t ${SSHD_CONF}.bak_* | head -1)" "$SSHD_CONF"
        exit 1
    fi
fi

# ============================================================
# VERIFICA FINALE
# ============================================================

echo ""
log "======= VERIFICA FINALE ======="

check() {
    local label="$1"
    local result="$2"  # "ok" o qualsiasi altro valore = ko
    local detail="$3"
    if [ "$result" = "ok" ]; then
        echo -e "  ${GREEN}OK${NC}  ${label}${detail:+: $detail}"
    else
        echo -e "  ${RED}KO${NC}  ${label}${detail:+: $detail}"
    fi
}

echo ""
# Utente
id "$NEW_USER" &>/dev/null \
    && check "Utente '${NEW_USER}' esiste" ok "UID=$(id -u $NEW_USER) | Gruppi: $(groups $NEW_USER | cut -d: -f2)" \
    || check "Utente '${NEW_USER}' esiste" ko

# Home
[ -d "/home/${NEW_USER}" ] \
    && check "Home /home/${NEW_USER}" ok "owner=$(stat -c '%U' /home/${NEW_USER})" \
    || check "Home /home/${NEW_USER}" ko

# Password
getent shadow "$NEW_USER" | cut -d: -f2 | grep -qv '^\*\|^!\|^$' \
    && check "Password impostata" ok \
    || check "Password impostata" ko

# Chiave SSH
[ -f "$AUTH_KEYS" ] \
    && check "Chiave SSH authorized_keys" ok \
    || check "Chiave SSH authorized_keys" -- "nessuna chiave configurata"

# Sudo
sudo -u "$NEW_USER" sudo -n true 2>/dev/null \
    && check "Sudo NOPASSWD" ok \
    || check "Sudo NOPASSWD" ko

# Hostname
[ "$(hostname)" = "$DEVICE_HOSTNAME" ] \
    && check "Hostname" ok "$(hostname)" \
    || check "Hostname" ko "atteso=${DEVICE_HOSTNAME} trovato=$(hostname)"

# SSH PermitRootLogin
grep -q "^PermitRootLogin no" "$SSHD_CONF" \
    && check "SSH PermitRootLogin no" ok \
    || check "SSH PermitRootLogin no" ko

# SSH AllowUsers
grep -q "^AllowUsers ${NEW_USER}" "$SSHD_CONF" \
    && check "SSH AllowUsers ${NEW_USER}" ok \
    || check "SSH AllowUsers ${NEW_USER}" ko

# Weston rimosso
! id "weston" &>/dev/null \
    && check "Utente 'weston' rimosso" ok \
    || check "Utente 'weston' rimosso" ko

echo ""
log "Setup completato."
warn "Testa il login SSH come '${NEW_USER}' prima di chiudere questa sessione!"
