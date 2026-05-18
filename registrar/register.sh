#!/bin/sh
# Registers this container as a SkyDNS entry in etcd v3.
# Required env vars:
#   ETCD_URL       e.g. http://etcd:2379
#   SERVICE_NAME   e.g. dovecot, ldap, postfix
#   SERVICE_PORT   e.g. 24
#   SITE           e.g. grenoble
#   HOSTNAME       auto (container hostname)

set -e

ETCD_URL="${ETCD_URL:-http://etcd:2379}"
SITE="${SITE:-local}"
SERVICE_NAME="${SERVICE_NAME:-unknown}"
SERVICE_PORT="${SERVICE_PORT:-0}"
HOST="${HOSTNAME}"

KEY="/skydns/fr/securepulse/${SITE}/${SERVICE_NAME}/${HOST}"
VALUE="{\"host\":\"${HOST}\",\"port\":${SERVICE_PORT}}"

b64_key=$(printf '%s' "$KEY"   | base64 | tr -d '\n')
b64_val=$(printf '%s' "$VALUE" | base64 | tr -d '\n')

echo "[registrar] Waiting for etcd at ${ETCD_URL} ..."
until curl -sf "${ETCD_URL}/health" > /dev/null 2>&1; do
    sleep 1
done

echo "[registrar] Registering: ${KEY} -> ${VALUE}"
curl -sf -X POST "${ETCD_URL}/v3/kv/put" \
    -H "Content-Type: application/json" \
    -d "{\"key\":\"${b64_key}\",\"value\":\"${b64_val}\"}" > /dev/null

# Also register a cross-site SRV (service-level, no site prefix)
KEY_GLOBAL="/skydns/fr/securepulse/all/${SERVICE_NAME}/${HOST}"
b64_key_g=$(printf '%s' "$KEY_GLOBAL" | base64 | tr -d '\n')
curl -sf -X POST "${ETCD_URL}/v3/kv/put" \
    -H "Content-Type: application/json" \
    -d "{\"key\":\"${b64_key_g}\",\"value\":\"${b64_val}\"}" > /dev/null

echo "[registrar] Registered."

# Deregister on exit
cleanup() {
    echo "[registrar] Deregistering ${KEY} ..."
    curl -sf -X POST "${ETCD_URL}/v3/kv/deleterange" \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"${b64_key}\"}" > /dev/null || true
    curl -sf -X POST "${ETCD_URL}/v3/kv/deleterange" \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"${b64_key_g}\"}" > /dev/null || true
}
trap cleanup EXIT INT TERM
