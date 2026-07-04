#!/bin/bash
# Mail/deploy/deploy.sh <SITE>-<NODE_ID> — lance ce nœud mail sur ce serveur.
# Suppose generate-config.sh déjà exécuté pour ce site/nœud.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

KEY="${1:?usage: ./deploy.sh <site>-<node-id>  (ex: grenoble-1)}"
[ -f "sites/${KEY}/.env" ] || { echo "sites/${KEY}/.env introuvable — lancez d'abord generate-config.sh ..." >&2; exit 1; }

docker compose -f docker-compose.prod.yml --env-file "sites/${KEY}/.env" up -d --build
echo "[deploy] mail (dovecot/postfix/roundcube) pour ${KEY} démarré."
