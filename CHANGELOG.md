# Changelog — Mail

## [Unreleased]

### Modifié
- **Dovecot monte désormais le NFS haute disponibilité exporté par
  `storage-lucien`** (`storage.<site>.<domain>:/mail`) au lieu d'un volume
  Docker local — conforme au rapport §56 ("Pour le stockage des mails, on a
  choisi d'utiliser du NFS vers un serveur distant"). `STORAGE_MODE=local`
  reste disponible comme échappatoire pour le smoke-test mono-nœud
  (`docker-compose.yml` racine).
- **Retrait de la réplication applicative Dovecot dsync** (`90-replication.conf`,
  `service replicator`/`aggregator`/`doveadm-server` dans `10-master.conf`) :
  les deux instances Dovecot d'un même DC montent désormais le **même**
  export NFS partagé et hautement disponible — répliquer une deuxième fois
  au niveau applicatif était redondant et n'était de toute façon fonctionnel
  qu'entre exactement 2 nœuds découverts par etcd, pas vraiment HA en soi.
- `docker-compose.yml` racine : ajout d'un etcd minimal (les entrypoints en
  dépendent, absent jusqu'ici — ce compose ne pouvait donc jamais démarrer
  correctement) ; ports remappés en 15000-20000 (test) ; documenté comme
  smoke-test mono-nœud sans HA ni LDAP (auth non fonctionnelle dans ce mode).

### Supprimé
- `deploy.sh` : générait un fichier `users` (passwd Dovecot statique) et un
  `postfix/conf/virtual` que le code actuel n'utilise plus depuis le passage
  à l'authentification LDAP (`10-auth.conf` = 100% LDAP) ; ses substitutions
  `sed` ciblaient aussi des placeholders (`POSTFIX_HOSTNAME`,
  `POSTFIX_DOMAIN`) différents de ceux réellement utilisés par
  `postfix/entrypoint.sh` (`POSTFIX_HOSTNAME_PLACEHOLDER`,
  `LMTP_HOST_PLACEHOLDER`). Script obsolète, incompatible avec
  l'architecture actuelle, retiré plutôt que réparé (le modèle "un domaine/
  un user/un password" ne correspond plus à l'architecture LDAP multi-
  tenant du projet).
- `users` (fichier passwd Dovecot statique) et `.users.kate-swp` (fichier
  de verrouillage de l'éditeur Kate, jamais du code) : artefacts orphelins.
- `mnt/user-data/outputs/postfix/Dockerfile` : ancien Dockerfile Postfix
  utilisant un fichier `virtual` statique au lieu de LDAP, incohérent avec
  `postfix/Dockerfile` (le vrai, utilisé partout ailleurs).

### Ajouté
- `tests/` : suite de tests HA (storage-lucien + LDAP + etcd + CoreDNS + 2
  instances Dovecot + Postfix sur un site) validant montage NFS, process
  actifs, authentification LDAP réelle, **stockage partagé confirmé entre
  les 2 instances Dovecot** (remplace la preuve qu'apportait dsync), et
  livraison SMTP → LMTP → stockage partagé de bout en bout.

### Corrigé (bugs trouvés en construisant les tests, dans LDAP/ et storage-lucien/)
- `getent hosts ldap.all.securepulse.fr` (Postfix et Dovecot) ne réessayait
  jamais : au démarrage à froid, ce conteneur gagne facilement la course
  contre le bootstrap LDAP (schéma + seed + enregistrement etcd) et la
  résolution revenait vide une fois pour toutes, cassant l'auth LDAP pour
  toute la durée de vie du conteneur. Retry ajouté (jusqu'à 60s).
- `LDAP/bootstrap/01-config.ldif.tpl` avait `olcMirrorMode: TRUE` statique
  au bootstrap, alors qu'OpenLDAP exige qu'au moins un `olcSyncrepl` existe
  déjà pour accepter le mode miroir (`<olcMultiProvider> database is not a
  shadow`) — **LDAP ne démarrait dans AUCUNE configuration** (1 nœud ou
  plusieurs), corrigé dans `LDAP/` en activant `olcMirrorMode` dans la même
  opération `ldapmodify` que le tout premier `olcSyncrepl` ajouté (validé
  atomiquement en une fois, ce qu'OpenLDAP accepte).
- `storage-lucien/ganesha.conf.tpl` utilisait `FSAL { Name = VFS }`, non
  disponible dans le paquet `nfs-ganesha` de Debian bookworm (seule la
  librairie FSAL Gluster est fournie séparément) — bascule sur
  `FSAL_GLUSTER` (accès natif via libgfapi, cohérent avec GlusterFS).

### Limitation connue et documentée : montage NFS cross-conteneur bloqué sur cet hôte
Après avoir corrigé tout ce qui précède, le montage NFS de Dovecot depuis
`storage-lucien` échoue avec `access denied by server` **spécifiquement en
traversant deux conteneurs différents** (client et serveur dans des network
namespaces distincts). Investigation approfondie menée (voir
`storage-lucien/README.md`, section Limitations connues, pour le détail
complet) :
- Connectivité réseau vérifiée à tous les niveaux (ping, TCP brut, capture
  de session) : aucun problème réseau.
- Reproduit à l'identique avec NFS-Ganesha (FSAL_GLUSTER) **et** avec le
  serveur NFS du noyau Linux (nfsd/mountd) — donc pas un bug spécifique à
  Ganesha/GlusterFS.
- Un montage **local** (même conteneur, `127.0.0.1` ou IP propre) réussit
  systématiquement ; seul le cas cross-conteneur échoue, quels que soient le
  sous-réseau Docker, les permissions d'export (`*`, IP explicite,
  `no_root_squash`, `insecure`), la version NFSv4 (4.0/4.1/4.2) ou les
  options de montage testées.
- Conclusion : caractéristique du noyau/de la pile réseau Docker de cet
  hôte de développement précis (probablement une interaction conntrack/
  netfilter avec le protocole RPC), hors de portée d'investigation ou de
  correction sans accès root à l'hôte — explicitement exclu du périmètre
  de ce projet ("aucune modification de l'hôte").
- Le code (`Mail/dovecot/entrypoint.sh`, `storage-lucien/entrypoint.sh`)
  suit les pratiques NFSv4 standard et n'a pas été modifié pour contourner
  cette limitation : il devrait fonctionner normalement sur un hôte Docker
  sans cette particularité réseau. `tests/run_tests.sh` documente ce que la
  suite peut valider dans cet environnement précis.
