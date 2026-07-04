#!/bin/bash
# Mail/deploy/generate-config.sh — .env d'un nœud mail (Postfix+Dovecot+
# RoundCube) pour un déploiement réel (un serveur = un nœud du DC ; un DC
# peut avoir 1..N nœuds mail, cf. integration/ où Nice/Tokyo en ont 2 et
# Grenoble/Paris 1 — pas de nombre fixe imposé).
#
# Usage:
#   ./generate-config.sh --site grenoble --node-id 1 --etcd-url http://10.10.1.5:2379 \
#       --dns-resolver-ip 10.10.1.100 [--domain securepulse.fr] \
#       [--ldap-bind-pw ...] [--doveadm-password ...]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SITE=""; NODE_ID="1"; ETCD_URL=""; DNS_RESOLVER_IP=""; DOMAIN="securepulse.fr"
LDAP_BIND_PW="admin"; DOVEADM_PASSWORD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --site) SITE="$2"; shift 2 ;;
        --node-id) NODE_ID="$2"; shift 2 ;;
        --etcd-url) ETCD_URL="$2"; shift 2 ;;
        --dns-resolver-ip) DNS_RESOLVER_IP="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --ldap-bind-pw) LDAP_BIND_PW="$2"; shift 2 ;;
        --doveadm-password) DOVEADM_PASSWORD="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

[ -n "$SITE" ] || { echo "--site is required" >&2; exit 1; }
[ -n "$ETCD_URL" ] || { echo "--etcd-url is required" >&2; exit 1; }
[ -n "$DNS_RESOLVER_IP" ] || { echo "--dns-resolver-ip is required (IP du CoreDNS de ce site — résolution ldap.all./storage.<site>.)" >&2; exit 1; }
if [ -z "$DOVEADM_PASSWORD" ]; then
    DOVEADM_PASSWORD=$(head -c18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c24)
    echo "[generate-config] --doveadm-password non fourni, valeur générée aléatoirement (voir ${SITE}-${NODE_ID}/.env)."
fi

OUT_DIR="sites/${SITE}-${NODE_ID}"
mkdir -p "$OUT_DIR"

cat > "${OUT_DIR}/.env" <<EOF
SITE=${SITE}
NODE_ID=${NODE_ID}
DOMAIN=${DOMAIN}
ETCD_URL=${ETCD_URL}
DNS_RESOLVER_IP=${DNS_RESOLVER_IP}
LDAP_BASE_DN=dc=securepulse,dc=fr
LDAP_BIND_DN=cn=admin,dc=securepulse,dc=fr
LDAP_BIND_PW=${LDAP_BIND_PW}
DOVEADM_PASSWORD=${DOVEADM_PASSWORD}
STORAGE_MODE=nfs
POSTFIX_HOSTNAME=mail.${DOMAIN}
EOF
chmod 600 "${OUT_DIR}/.env"

echo "[generate-config] écrit ${OUT_DIR}/.env (permissions 600 : contient des secrets de test)"
echo "[generate-config] déploiement : ./deploy.sh ${SITE}-${NODE_ID}"
