#!/bin/sh
set -e

ETCD_URL="${ETCD_URL:-http://etcd:2379}"
SITE="${SITE:-local}"
POSTFIX_HOSTNAME="${POSTFIX_HOSTNAME:-mail.securepulse.fr}"

_b64()  { printf '%s' "$1" | base64 | tr -d '\n'; }

wait_etcd() {
    until curl -sf "${ETCD_URL}/health" > /dev/null 2>&1; do sleep 1; done
}

etcd_put() {
    curl -sf -X POST "${ETCD_URL}/v3/kv/put" \
        -H 'Content-Type: application/json' \
        -d "{\"key\":\"$(_b64 "$1")\",\"value\":\"$(_b64 "$2")\"}" > /dev/null
}

etcd_del() {
    curl -sf -X POST "${ETCD_URL}/v3/kv/deleterange" \
        -H 'Content-Type: application/json' \
        -d "{\"key\":\"$(_b64 "$1")\"}" > /dev/null
}

get_my_ip() {
    ip -4 addr show | grep -oE '10\.10\.[1-9][0-9]*\.[0-9]+' | head -1
}

register() {
    MY_IP=$(get_my_ip)
    etcd_put "/skydns/fr/securepulse/${SITE}/postfix/${HOSTNAME}" "{\"host\":\"${MY_IP}\"}"
    etcd_put "/skydns/fr/securepulse/all/postfix/${HOSTNAME}"     "{\"host\":\"${MY_IP}\"}"
    echo "[register] Postfix ${HOSTNAME} ip=${MY_IP} site=${SITE}"
}

deregister() {
    echo "[deregister] Removing ${HOSTNAME}..."
    etcd_del "/skydns/fr/securepulse/${SITE}/postfix/${HOSTNAME}"
    etcd_del "/skydns/fr/securepulse/all/postfix/${HOSTNAME}"
}

cleanup() {
    echo "[shutdown] SIGTERM received"
    deregister
    postfix stop 2>/dev/null || true
    exit 0
}

###############################################################################

wait_etcd

# LMTP host: deliver to any available Dovecot via round-robin DNS
LMTP_HOST="${LMTP_HOST:-lmtp.all.securepulse.fr}"
export LMTP_HOST

# LDAP hosts: prefer round-robin DNS across all LDAP nodes.
# Retried (not a one-shot lookup): at cold start this container easily
# starts before LDAP finishes its own bootstrap + etcd registration.
if [ -z "$LDAP_HOSTS" ]; then
    for i in $(seq 1 30); do
        LDAP_HOSTS=$(getent hosts ldap.all.securepulse.fr 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | xargs)
        [ -n "$LDAP_HOSTS" ] && break
        sleep 2
    done
    LDAP_HOSTS="${LDAP_HOSTS:-ldap.all.securepulse.fr}"
    export LDAP_HOSTS
fi

echo "[init] LMTP_HOST=${LMTP_HOST}"
echo "[init] LDAP_HOSTS=${LDAP_HOSTS}"

sed -i \
    -e "s/POSTFIX_HOSTNAME_PLACEHOLDER/${POSTFIX_HOSTNAME}/g" \
    -e "s/LMTP_HOST_PLACEHOLDER/${LMTP_HOST}/g" \
    /etc/postfix/main.cf

for f in /etc/postfix/ldap-vmailbox.cf /etc/postfix/ldap-aliases.cf; do
    sed -i \
        -e "s/LDAP_HOSTS_PLACEHOLDER/${LDAP_HOSTS}/g" \
        -e "s|LDAP_BASE_DN_PLACEHOLDER|${LDAP_BASE_DN}|g" \
        -e "s|LDAP_BIND_DN_PLACEHOLDER|${LDAP_BIND_DN}|g" \
        -e "s/LDAP_BIND_PW_PLACEHOLDER/${LDAP_BIND_PW}/g" \
        "$f"
done

syslogd 2>/dev/null || true
newaliases 2>/dev/null || true
postfix start

trap cleanup TERM INT

register

touch /var/log/mail.log
tail -F /var/log/mail.log &

while true; do
    sleep 5
    postfix status > /dev/null 2>&1 || \
        { echo "[postfix] restarting..."; postfix start; }
done
