#!/bin/bash

# SSH
sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
systemctl restart sshd

# Firewall
ufw allow proto tcp from any to any port 22,80,443
ufw -f default deny incoming
ufw -f default allow outgoing
ufw -f enable
