#!/usr/bin/env bash

set -euo pipefail

# === Configuration ===
readonly REPO="https://github.com/borcean/ansible-coreos.git"
readonly BRANCH="bluefin"
readonly VAULT_FILE="/root/.ansible_vault_key"
readonly INVENTORY_URL="https://raw.githubusercontent.com/borcean/ansible-coreos/${BRANCH}/hosts"

# === Functions ===

log() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

confirm() {
    local prompt="$1"
    local response
    while true; do
        read -rp "$prompt [y/n]: " response
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please enter y or n." ;;
        esac
    done
}

check_hostname() {
    local current_hostname
    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    if [[ -z "$current_hostname" ]]; then
        warn "Hostname is unset or empty."
        if confirm "Set hostname now?"; then
            read -rp "New hostname: " new_hostname
            if [[ -z "$new_hostname" ]]; then
                error "New hostname cannot be empty."
            fi
            sudo hostnamectl set-hostname "$new_hostname"
            check_hostname
        else
            error "Cannot proceed without a valid hostname."
        fi
        return
    fi

    if curl -fsSL "$INVENTORY_URL" | grep -qx "$current_hostname"; then
        log "Host '$current_hostname' found in inventory."
    else
        warn "Host '$current_hostname' not found in inventory."
        if confirm "Change hostname now?"; then
            read -rp "New hostname: " new_hostname
            if [[ -z "$new_hostname" ]]; then
                error "New hostname cannot be empty."
            fi
            sudo hostnamectl set-hostname "$new_hostname"
            check_hostname
        else
            error "Hostname not recognized and user declined to change it."
        fi
    fi
}

set_vault_password() {
    local pass1 pass2

    prompt_password() {
        echo -e "\nEnter vault password:"
        read -sr -p "Password: " pass1; echo
        read -sr -p "Confirm:  " pass2; echo
    }

    prompt_password

    if [[ "$pass1" == "$pass2" ]]; then
        echo "$pass1" | sudo tee "$VAULT_FILE" >/dev/null
        sudo chmod 0600 "$VAULT_FILE"
        log "Vault password saved at $VAULT_FILE"
    else
        warn "Passwords do not match. Try again."
        set_vault_password
    fi
}

install_ansible_if_needed() {
    if ! command -v ansible &>/dev/null; then
        log "Ansible not found. Installing via Homebrew..."
        brew install ansible
        log "Ansible installed successfully."
    else
        log "Ansible is already installed."
    fi
}

# === Main Script ===

# Ensure Ansible is available
install_ansible_if_needed

# Check hostname in inventory
check_hostname

# Set vault password if missing
if sudo test -f "$VAULT_FILE"; then
    log "Vault key already exists at $VAULT_FILE"
else
    set_vault_password
fi

# Clean Ansible cache (as root)
log "Cleaning Ansible cache..."
sudo rm -rf /root/.ansible/

# Run ansible-pull (as root)
log "Running Ansible pull..."
sudo /home/linuxbrew/.linuxbrew/bin/ansible-pull --vault-password-file="$VAULT_FILE" -U "$REPO" -C "$BRANCH"

# Reboot if confirmed
if confirm "Reboot system now?"; then
    log "Rebooting..."
    sudo systemctl reboot -i
fi
