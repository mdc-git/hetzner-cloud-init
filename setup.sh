#!/bin/bash

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  --hcloud-token)
    TOKEN="$2"
    shift
    shift
  ;;
  --whitelisted-ips)
    WHITELIST_S="$2"
    shift
    shift
  ;;
  --registry)
    REGISTRY_URL="$2"
    shift
    shift
  ;;
  --auth-user)
    AUTH_USER="$2"
    shift
    shift
  ;;
  --auth-password)
    AUTH_PASSWORD="$2"
    shift
    shift
  ;;
  --floating-ips)
    FLOATING_IPS="--floating-ips"
    shift
  ;;
  *)
    shift
  ;;
esac
done

if [[ ! -z $REGISTRY_URL && ! -z $AUTH_USER && ! -z $AUTH_PASSWORD ]]; then
cat <<EOF > /usr/local/bin/find_latest_shas.sh
#!/usr/bin/env bash

REGISTRY_URL=$REGISTRY_URL
AUTH_USER=$AUTH_USER
AUTH_PW=$AUTH_PASSWORD
REPOS=\$(curl -s -u \$AUTH_USER:\$AUTH_PW https://\$REGISTRY_URL/v2/_catalog | jq -r .repositories[])

for REPO in \$REPOS; do

    LATEST_SHA=\$(curl -s -u \$AUTH_USER:\$AUTH_PW https://\$REGISTRY_URL/v2/\$REPO/manifests/latest -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' | jq .config.digest)

    TAGS=\$(curl -s -u \$AUTH_USER:\$AUTH_PW  https://\$REGISTRY_URL/v2/\$REPO/tags/list | jq -r ' .tags | map(select(. != "latest")) | .[]')

    for TAG in \$TAGS ; do
        SHA=\$(curl -s -u \$AUTH_USER:\$AUTH_PW https://\$REGISTRY_URL/v2/\$REPO/manifests/\$TAG -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' | jq .config.digest)
        if [ "\$SHA" == "\$LATEST_SHA" ]; then
            echo "kubectl --insecure-skip-tls-verify set image deployments/\$REPO \$REPO=\$REGISTRY_URL/\$REPO:\$TAG"
            kubectl --insecure-skip-tls-verify set image deployments/\$REPO \$REPO=\$REGISTRY_URL/\$REPO:\$TAG
        fi
    done
done
EOF

chmod +x /usr/local/bin/find_latest_shas.sh
cat <<EOF >> /etc/crontab
* * * * * root /usr/local/bin/find_latest_shas.sh
EOF
fi

FLOATING_IPS=${FLOATING_IPS:-""}


sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

systemctl restart sshd

cat <<EOF >> /etc/sysctl.d/99-custom.conf
vm.overcommit_memory=1
vm.panic_on_oom=0
kernel.panic=10
kernel.panic_on_oops=1
kernel.keys.root_maxbytes=25000000
EOF

sysctl -p /etc/sysctl.d/99-custom.conf



wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
chmod +x jq-linux64
mv jq-linux64 /usr/local/bin/jq

curl -o /usr/local/bin/rke-node-kubeconfig.sh https://raw.githubusercontent.com/mdc-git/hetzner-cloud-init/master/rke-node-kubeconfig.sh

chmod +x /usr/local/bin/rke-node-kubeconfig.sh

curl -o /usr/local/bin/kubectl https://raw.githubusercontent.com/mdc-git/hetzner-cloud-init/master/kubectl

chmod +x /usr/local/bin/kubectl

curl -o /usr/local/bin/update-config.sh https://raw.githubusercontent.com/mdc-git/hetzner-cloud-init/master/update-config.sh

chmod +x /usr/local/bin/update-config.sh

ufw allow proto tcp from any to any port 22,80,443,7234

IFS=', ' read -r -a WHITELIST <<< "$WHITELIST_S"

for IP in "${WHITELIST[@]}"; do
  ufw allow from "$IP"
done

ufw allow from 10.0.0.0/8

ufw -f default deny incoming
ufw -f default allow outgoing

ufw -f enable

cat <<EOF >> /etc/crontab
* * * * * root /usr/local/bin/update-config.sh --hcloud-token ${TOKEN} --whitelisted-ips ${WHITELIST_S} ${FLOATING_IPS}
EOF

cat <<EOF >> /etc/crontab
30 * * * * root docker system prune -a -f
EOF

/usr/local/bin/update-config.sh --hcloud-token ${TOKEN} --whitelisted-ips ${WHITELIST_S} ${FLOATING_IPS}

