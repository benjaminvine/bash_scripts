!#/bin/bash

function configure_fail2ban() {

    jail_config = $(cat <<EOF[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 3
bantime = 3600
findtime = 600
EOF)

    # Install fail2ban if not installed
    if((!apt list fail2ban)); then
        apt install fail2ban
    fi


}