#!/bin/sh
set -e

ETCD_URL="${ETCD_URL:-http://etcd:2379}"
SITE="${SITE:-local}"
DOVEADM_PASSWORD="${DOVEADM_PASSWORD:-doveadm_secret}"

_b64()  { printf '%s' "$1" | base64 | tr -d '\n'; }
_b64d() { printf '%s' "$1" | base64 -d 2>/dev/null; }

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

etcd_list() {
    local prefix="$1"
    local end
    end=$(printf '%s' "$prefix" | sed 's|/$|0|')
    curl -sf -X POST "${ETCD_URL}/v3/kv/range" \
        -H 'Content-Type: application/json' \
        -d "{\"key\":\"$(_b64 "$prefix")\",\"range_end\":\"$(_b64 "$end")\"}" | \
        jq -r '.kvs[]?.value // empty' | \
        while read -r b64; do _b64d "$b64"; printf '\n'; done
}

get_my_ip() {
    ip -4 addr show | grep -oE '10\.10\.[1-9][0-9]*\.[0-9]+' | head -1
}

register() {
    MY_IP=$(get_my_ip)
    etcd_put "/skydns/fr/securepulse/${SITE}/dovecot/${HOSTNAME}" "{\"host\":\"${MY_IP}\"}"
    etcd_put "/skydns/fr/securepulse/all/dovecot/${HOSTNAME}"     "{\"host\":\"${MY_IP}\"}"
    etcd_put "/skydns/fr/securepulse/${SITE}/lmtp/${HOSTNAME}"    "{\"host\":\"${MY_IP}\"}"
    etcd_put "/skydns/fr/securepulse/all/lmtp/${HOSTNAME}"        "{\"host\":\"${MY_IP}\"}"
    echo "[register] Dovecot ${HOSTNAME} ip=${MY_IP} site=${SITE}"
}

deregister() {
    echo "[deregister] Removing ${HOSTNAME}..."
    etcd_del "/skydns/fr/securepulse/${SITE}/dovecot/${HOSTNAME}"
    etcd_del "/skydns/fr/securepulse/all/dovecot/${HOSTNAME}"
    etcd_del "/skydns/fr/securepulse/${SITE}/lmtp/${HOSTNAME}"
    etcd_del "/skydns/fr/securepulse/all/lmtp/${HOSTNAME}"
}

# Find first other Dovecot node IP from etcd
find_replica() {
    local my_ip
    my_ip=$(get_my_ip)
    etcd_list "/skydns/fr/securepulse/all/dovecot/" | while read -r val; do
        [ -z "$val" ] && continue
        ip=$(printf '%s' "$val" | jq -r '.host // empty' 2>/dev/null) || continue
        [ "$ip" != "$my_ip" ] && [ -n "$ip" ] && echo "$ip" && return
    done
}

cleanup() {
    echo "[shutdown] SIGTERM received"
    deregister
    kill "$DOVECOT_PID" 2>/dev/null || true
    wait "$DOVECOT_PID" 2>/dev/null || true
    exit 0
}

###############################################################################

wait_etcd

# Resolve LDAP hosts — prefer all.ldap.securepulse.fr round-robin
if [ -z "$LDAP_HOSTS" ]; then
    LDAP_HOSTS=$(getent hosts ldap.all.securepulse.fr 2>/dev/null | \
        awk '{print $1}' | tr '\n' ' ' | xargs || echo "ldap.all.securepulse.fr")
    export LDAP_HOSTS
fi
echo "[init] LDAP_HOSTS=${LDAP_HOSTS}"

# Substitute LDAP placeholders
sed -i \
    -e "s/LDAP_HOSTS_PLACEHOLDER/${LDAP_HOSTS}/g" \
    -e "s|LDAP_BIND_DN_PLACEHOLDER|${LDAP_BIND_DN}|g" \
    -e "s/LDAP_BIND_PW_PLACEHOLDER/${LDAP_BIND_PW}/g" \
    -e "s|LDAP_BASE_DN_PLACEHOLDER|${LDAP_BASE_DN}|g" \
    /etc/dovecot/dovecot-ldap.conf

# Find a replication peer — disable replication if we're alone
REPLICA_IP=$(find_replica)
if [ -n "$REPLICA_IP" ]; then
    echo "[init] Replication peer: ${REPLICA_IP}"
    sed -i \
        -e "s/DOVEADM_PASSWORD_PLACEHOLDER/${DOVEADM_PASSWORD}/g" \
        -e "s/REPLICA_HOST_PLACEHOLDER/${REPLICA_IP}/g" \
        /etc/dovecot/conf.d/90-replication.conf
else
    echo "[init] No replica found — replication disabled for now"
    rm -f /etc/dovecot/conf.d/90-replication.conf
fi

chown -R vmail:vmail /var/mail 2>/dev/null || true

trap cleanup TERM INT

register

echo "[start] Starting dovecot..."
dovecot -F &
DOVECOT_PID=$!

wait "$DOVECOT_PID"
