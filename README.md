# Mail — Postfix + Dovecot + RoundCube

Serveur mail SecurePulse : Postfix (SMTP/soumission), Dovecot (IMAP/POP3 +
LMTP), RoundCube (webmail). Authentification 100% LDAP (`LDAP/`),
découverte de service via etcd/CoreDNS (`DNS/`), stockage haute
disponibilité via NFS monté depuis `storage-lucien/` (remplace la
réplication applicative Dovecot dsync, retirée — voir `CHANGELOG.md`).

## Deux modes de déploiement

| Mode | Fichier | Usage |
|---|---|---|
| Smoke-test mono-nœud | `docker-compose.yml` (racine) | Vérifie juste que les images démarrent. **Pas de LDAP** (auth non fonctionnelle), **pas de HA** (`STORAGE_MODE=local`, volume Docker local). |
| HA réelle (1 site) | `tests/docker-compose.test.yml` | LDAP + etcd + CoreDNS + storage-lucien (2 nœuds) + 2x Dovecot + Postfix. Authentification LDAP réelle, stockage partagé HA. |

```sh
# Smoke-test rapide
docker compose up -d --build   # ports 15025 (SMTP), 15080 (webmail), 15143 (IMAP)...

# Test HA complet
cd tests && docker compose -f docker-compose.test.yml up -d --build
./run_tests.sh
```

## Variables d'environnement (Dovecot)

| Variable | Défaut | Rôle |
|---|---|---|
| `STORAGE_MODE` | `nfs` | `nfs` = monte `storage.<site>.<domain>:/mail` (HA, requis en usage réel) ; `local` = volume Docker local (smoke-test uniquement, pas de HA) |
| `STORAGE_HOST` | `storage.<SITE>.<DOMAIN>` | Override explicite si besoin |

## Limitation connue : montage NFS cross-conteneur

Sur au moins un hôte de développement testé, le montage NFSv4 **entre deux
conteneurs différents** échoue systématiquement, alors qu'un montage local
(même conteneur) réussit toujours — caractéristique du noyau/réseau Docker
de cet hôte précis (pas un bug de ce repo, investigation exhaustive dans
`CHANGELOG.md` et `storage-lucien/README.md`). `tests/run_tests.sh` détecte
cette situation et saute proprement les tests qui en dépendent plutôt que
de les compter comme des échecs.

## Hors scope (cf. rapport, conclusion)

- DMARC/SPF/DKIM (mail vers domaines externes type Gmail) — non implémenté
  volontairement, bloquant identifié par le rapport lui-même.
- Relais SMTP pour contourner le blocage du port 25 par les box internet.
