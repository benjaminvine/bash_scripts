!#/bin/bash

function configure_fail2ban() {

    # Create jail config template and path variables
    config_changed=false
    jail_path="/etc/fail2ban/jail.d/sshd.local"
    jail_config=$(cat <<EOF
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
    if ! dpkg -s fail2ban 2> /dev/null | grep -q '^Status: install ok installed'; then
        sudo apt install -y fail2ban
    fi

    # Check if jail file is present and correct, if not update
    if [[ ! -f "$jail_path" ]] || [[ "$(<"$jail_path")" != "$jail_config" ]]; then
        printf '%s\n' "$jail_config" | sudo tee "$jail_path" >/dev/null
        config_changed=true
    fi

    # Check if fail2ban is enabled, if not enable
    if ! systemctl is-enabled --quiet fail2ban; then
        sudo systemctl enable fail2ban
    fi

    # Check if fail2ban is running, if not start
    if ! systemctl is-active --quiet fail2ban; then
        sudo systemctl start fail2ban
    elif config_changed; then
        sudo systemctl restart fail2ban
    fi

}