#!/bin/sh
set -e

ETCD_URL="${ETCD_URL:-http://etcd:2379}"
SITE="${SITE:-local}"
DOMAIN="${DOMAIN:-securepulse.fr}"
STORAGE_HOST="${STORAGE_HOST:-storage.${SITE}.${DOMAIN}}"

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

# Monte le NFS haute dispo exporté par storage-lucien (VIP Pacemaker du DC).
# Les 2 instances Dovecot d'un même DC montent le MÊME export -> plus besoin
# de réplication applicative (dsync) entre elles, cf. Dockerfile/10-master.conf.
mount_storage() {
    echo "[mount] Waiting for ${STORAGE_HOST}:/mail..."
    for i in $(seq 1 60); do
        if mount -t nfs4 -o vers=4.2,proto=tcp "${STORAGE_HOST}:/mail" /var/mail 2>/tmp/mount.err; then
            echo "[mount] /var/mail mounted from ${STORAGE_HOST}:/mail"
            return 0
        fi
        sleep 2
    done
    echo "[mount] FAILED after retries:"
    cat /tmp/mount.err 2>/dev/null
    return 1
}

cleanup() {
    echo "[shutdown] SIGTERM received"
    deregister
    kill "$DOVECOT_PID" 2>/dev/null || true
    wait "$DOVECOT_PID" 2>/dev/null || true
    umount /var/mail 2>/dev/null || true
    exit 0
}

###############################################################################

wait_etcd

# Resolve LDAP hosts — prefer all.ldap.securepulse.fr round-robin.
# Retries: at cold start, this container can easily win the race against
# LDAP's own bootstrap (schema load + seed data + etcd registration), so a
# single getent attempt can come back empty and silently break LDAP auth
# for the rest of this container's life.
if [ -z "$LDAP_HOSTS" ]; then
    for i in $(seq 1 30); do
        LDAP_HOSTS=$(getent hosts ldap.all.securepulse.fr 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | xargs)
        [ -n "$LDAP_HOSTS" ] && break
        sleep 2
    done
    LDAP_HOSTS="${LDAP_HOSTS:-ldap.all.securepulse.fr}"
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

# STORAGE_MODE=local : échappatoire pour le smoke-test mono-nœud sans HA
# (Mail/docker-compose.yml, pas de storage-lucien) — le volume Docker local
# ./mail sert alors de /var/mail directement. Comportement par défaut
# (STORAGE_MODE=nfs, tout déploiement réel/testé en intégration) : montage
# NFS haute dispo obligatoire, on ne démarre pas sans lui.
if [ "${STORAGE_MODE:-nfs}" = "nfs" ]; then
    mount_storage || { echo "[FATAL] Could not mount storage, aborting"; exit 1; }
else
    echo "[mount] STORAGE_MODE=local — volume local /var/mail (pas de HA, smoke-test uniquement)"
fi

chown -R vmail:vmail /var/mail 2>/dev/null || true

trap cleanup TERM INT

register

echo "[start] Starting dovecot..."
dovecot -F &
DOVECOT_PID=$!

wait "$DOVECOT_PID"
