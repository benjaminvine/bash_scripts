#!/bin/bash

set -euo pipefail

# Normalize variables and files for clean comparison
normalize() {
    { grep -vE '^[[:space:]]*(#|$)' || [[ $? -eq 1 ]]; } | sed 's/[[:blank:]]\+/ /g' | sort
}

# Returns true if file exists, is non-empty, and has valid ssh key(s)
has_valid_key() {
    local file=$1
    [[ -s "$file" ]] && ssh-keygen -l -f "$file" &>/dev/null
}

configure_ssh() {

    # Create sshd config template and path variables
    local user
    user=$(id -un)
    local user_home=""
    local ssh_dir=""
    local auth_keys=""
    local current=""
    local desired=""
    local backup=""
    local sshd_path="/etc/ssh/sshd_config.d/00-provision.conf"
    local sshd_config
    sshd_config=$(cat <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
PermitEmptyPasswords no
LoginGraceTime 30
MaxAuthTries 3
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
PermitUserEnvironment no
HostbasedAuthentication no
IgnoreRhosts yes
EOF
)
    # VALIDATE AUTH_KEYS
    # Get User Home Dir and authorized_keys path
    user_home=$(getent passwd "$user" | cut -d: -f6)
    ssh_dir="$user_home/.ssh"
    auth_keys="$user_home/.ssh/authorized_keys"

    # Verify permissions on .ssh
    if [[ -d "$ssh_dir" && $(stat -c '%a' "$ssh_dir") != 700 ]]; then
        chmod 700 "$ssh_dir"
    fi

    # Verify permission on authorized_keys
    if [[ -f "$auth_keys" && $(stat -c '%a' "$auth_keys") != 600 ]]; then
        chmod 600 "$auth_keys"
    fi

    # If file doesn't exist, is empty, or has invalid ssh key, remove PassAuth no from template var
    if ! has_valid_key "$auth_keys"; then
        echo "warn: no valid ssh key, leaving PasswordAuthentication unmanaged" >&2
        sshd_config=$(grep -v '^PasswordAuthentication' <<< "$sshd_config")
    fi

    # VALIDATE OR UPDATE SSHD_CONFIG
    # Normalize current config if file exists
    if [[ -f "$sshd_path" ]]; then
        current=$(normalize < "$sshd_path")
    fi

    # Normalize desired config variable
    desired=$(printf '%s\n' "$sshd_config" | normalize)

    # If file doesn't exist or is not correct, then update
    if [[ ! -f "$sshd_path" || "$current" != "$desired" ]]; then

        # Create backup of config file if exists
        if [[ -f "$sshd_path" ]]; then
            backup="/etc/ssh/sshd_config.d/00-provision.backup.$(date +%F-%H%M%S)"
            if ! sudo cp -p -- "$sshd_path" "$backup"; then
                echo "ERROR: backup failed, aborting before modifying sshd config" >&2
                return 1
            fi
        fi

        # Copy desired config to sshd config
        printf '%s\n' "$sshd_config" | sudo tee "$sshd_path" >/dev/null

        # Validate sshd config & restart sshd if valid
        if sudo sshd -t; then
            if ! sudo systemctl restart sshd; then
                echo "ERROR: sshd restart failed"
                return 1
            fi
        else
            echo "ERROR: sshd configuration validation failed"

            # Rollback sshd config file if exists, otherwise remove sshd_path
            if [[ -n "$backup" && -f "$backup" ]]; then
                sudo cp "$backup" "$sshd_path"
                if ! sudo sshd -t; then
                    echo "ERROR: restored sshd configuration is also invalid"
                fi
            else
                sudo rm -f "$sshd_path"
            fi

            return 1
        fi
    fi
}

configure_fail2ban() {

    # Create jail config template and path variables
    local config_changed=0
    local jail_path="/etc/fail2ban/jail.d/sshd.local"
    local jail_config
    jail_config=$(cat <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 3600
findtime = 600
EOF
)

    # Install fail2ban if not already installed
    if [[ $(dpkg-query -W -f='${Status}' fail2ban 2>/dev/null) != 'install ok installed' ]]; then
        sudo apt-get install -y fail2ban
    fi

    # Check if jail file is present and correct, if not update
    if [[ ! -f "$jail_path" ]] || [[ "$(<"$jail_path")" != "$jail_config" ]]; then
        printf '%s\n' "$jail_config" | sudo tee "$jail_path" >/dev/null
        config_changed=1
    fi

    # Check if fail2ban is enabled, if not enable
    if ! systemctl is-enabled --quiet fail2ban; then
        sudo systemctl enable fail2ban
    fi

    # Check if fail2ban is running, if not start
    if ! systemctl is-active --quiet fail2ban; then
        sudo systemctl start fail2ban
    elif [[ "$config_changed" == 1 ]]; then
        sudo systemctl restart fail2ban
    fi

}

  main() { configure_fail2ban; configure_ssh; }
  if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi