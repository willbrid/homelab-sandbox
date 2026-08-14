# Homelab DevSecOps « willbrid » — Documentation d'architecture & Plan d'action

> **Statut** : Documentation de conception (aucune implémentation à ce stade).
> **Cible** : Proxmox VE 9.1.1 — bi-Xeon E5-2640 v3, **16 cœurs physiques / 32 threads**, 128 Go RAM, 2 nœuds NUMA. **29 vCPU / 86 Go alloués** (§2).
> **Stockage hôte** : **SSD 1 To** réservé à Proxmox et à ses données (`local` : ISO, templates, snippets) ; **HDD 4 To** portant `local-lvm`, où vivent **tous** les disques de VM — §2.6.
> **OS des VMs** : Rocky Linux 10 — template `9002` construit par la stack `proxmox-infra/templates`.
> **Poste d'administration (bastion)** : machine client Ubuntu 24.04 (OpenTofu + Ansible), hors Proxmox.
> **Domaine interne** : `willbrid.lan`.
> **Réseau** : 2 interfaces par VM — LAN `192.168.1.0/24` + interne isolé `172.16.1.0/24` (§3).
> **IaC** : stacks OpenTofu dans `devsecops-homelab/vms/`, bâties sur les modules de `proxmox-infra/` (§4.3).

---

## 1. Vue d'ensemble

Ce homelab met en place une chaîne DevSecOps complète et auto-suffisante, construite couche par couche depuis l'infrastructure jusqu'aux applications, avec une identité centralisée (LDAP), une PKI interne, une gestion des secrets (OpenBao), du GitOps (ArgoCD), une observabilité unifiée des trois signaux (§11) et un volet IA (§16).

### 1.1 Décisions d'architecture actées

| Sujet | Décision |
|---|---|
| Secrets manager | **OpenBao** (fork LF de Vault, licence MPL, compatible API/CLI Vault) |
| GitLab & Harbor | **1 VM dédiée**, conteneurs **Podman Quadlet**, partageant **un seul PostgreSQL** (2 bases distinctes) |
| Cluster K8s | **kubeadm** + **Cilium** (CNI, eBPF, sans kube-proxy) |
| Entrée du lab (L4) | **1 VM HAProxy dédiée**, en amont des control-planes (pas de MetalLB ; keepalived reporté) |
| Exposition des applications | **Gateway API** (`gateway.networking.k8s.io/v1`) implémentée par **Cilium**, en *host network mode* — **pas d'Ingress, pas d'ingress-nginx** |
| Sortie cluster (egress) | **Cilium Egress Gateway** — IP de sortie unique |
| Authn utilisateurs K8s | **OIDC via Dex adossé à LLDAP** (voir §8.7) |
| Annuaire | **LLDAP**, `uid` = **CUID v2** généré par script **Go** |
| DNS interne | **CoreDNS** autonome sur la VM `dns` (≠ CoreDNS du cluster) |
| Serveur mail | **Mini-serveur mail conteneurisé** sur la VM `dns` |
| Réseau des VMs | **2 interfaces** : `eth0` LAN `192.168.1.0/24` (route par défaut, admin/exposition) + `eth1` interne `172.16.1.0/24` (est-ouest, sans passerelle) — §3 |
| Collecte d'observabilité | **OpenTelemetry Collector** partout (agent DaemonSet K8s + agent VM + gateway), point de collecte unique des 3 signaux |
| Métriques | **Prometheus** (ingestion OTLP native, rétention locale courte) + **Thanos** (long terme sur stockage objet) |
| Logs | **OpenSearch** — backend unique : logs des VMs *et* des applications K8s |
| Traces | **Tempo** (mode monolithique, backend objet) |
| Visualisation | **Grafana** (datasources Thanos, Tempo, OpenSearch) |
| Stockage objet | **RustFS** (Apache 2.0, S3-compatible) — buckets `thanos`, `tempo`, `velero` |
| Stockage bloc K8s | **OpenEBS** — deux moteurs complémentaires : **Replicated PV Mayastor** (NVMe-oF/TCP, SPDK, `repl: 2`) pour ce qui doit survivre à la perte d'un nœud, **Local PV hostpath** pour l'état chaud et reconstructible — §8.8 |
| Disques des workers | **2 disques** : `scsi0` racine 80 Go + **`scsi1` 100 Go brut**, non partitionné, non monté, non formaté — dédié au `DiskPool` Mayastor (§2.7, §4.5, §8.8) |
| Stockage Proxmox | **Un seul datastore pour les VMs** : `local-lvm` (thin, adossé au HDD 4 To). Le SSD 1 To est réservé à Proxmox et à son stockage `local` — §2.6 |
| IaC | **OpenTofu** (`bpg/proxmox`) + **Ansible** depuis le bastion Ubuntu |
| PKI | **Root CA offline** (bastion) → **Intermediate CA** dans OpenBao |
| Workers K8s | **4 vCPU / 12 Go** chacun (pile d'observabilité **+ 2 Go de HugePages réservées à Mayastor**, §2.6) |

### 1.2 Principe directeur

L'ordre d'implémentation suit les dépendances : rien qui ait besoin de certificats ne se déploie avant la PKI ; rien qui ait besoin d'identité ne se déploie avant LDAP ; rien qui ait besoin de secrets ne se déploie avant OpenBao.

---

## 2. Dimensionnement & répartition des VMs

**La machine, vérifiée et non supposée** (`lscpu -e`, `dmidecode -t processor`, `/sys/devices/system/cpu/*`) :

| Caractéristique | Valeur |
|---|---|
| Processeurs | 2 × Intel Xeon **E5-2640 v3** (Haswell-EP, 2,6 GHz, turbo 3,4 GHz) |
| **Cœurs physiques** | **16** (2 sockets × 8), tous activés au BIOS (`Core Count` = `Core Enabled`) |
| **Threads logiques** | **32** — Hyper-Threading actif ; les CPU `N` et `N+16` partagent un cœur |
| NUMA | 2 nœuds : `node0` = CPU 0-7,16-23 · `node1` = CPU 8-15,24-31 — 64 Go chacun |
| RAM | 128 Go |
| Ligne de base CPU | **x86-64-v3** confirmée (`avx2`, `bmi2`, `fma`, `f16c`, `movbe`, `abm`) — requise par Rocky Linux 10 |
| Prérequis Mayastor | `sse4_2` présent (§8.8.1) |

Le budget est donc contraint — **16 cœurs physiques et 128 Go** — et la liste d'outils s'est allongée (HAProxy dédié, stockage objet, pile d'observabilité complète, stockage répliqué). Le dimensionnement est **optimisé pour un homelab** : chaque service est calibré au plus juste, les rôles compatibles sont mutualisés dans une même VM sous forme de conteneurs, et l'élasticité est reportée sur les réglages de rétention plutôt que sur la RAM.

**Plafond fixé à 29 vCPU sur 32 threads**, soit 3 threads laissés à l'hyperviseur. Ce n'est pas de la prudence de principe : Proxmox a besoin de CPU pour ses propres tâches — un *iothread* QEMU par disque (`iothread = true` dans le module), `ksmd` qui scanne 128 Go en continu (§2.3), les bridges réseau et les sauvegardes PBS. Allouer les 32 threads ne laisserait rien à ce travail-là.

La cible **HA (3 control-planes + 3 workers) est la configuration de départ**, pas une phase ultérieure.

| VM | Rôle | vCPU | RAM | Disque | Notes |
|---|---|---:|---:|---:|---|
| `dns` | CoreDNS + mini-serveur mail (Quadlet) | 1 | 2 Go | 20 Go | deux daemons très légers |
| `ldap` | LLDAP (binaire Rust, ~50 Mo RSS) | 1 | 1 Go | 15 Go | Dex déporté dans K8s |
| `openbao` | OpenBao (secrets + Intermediate CA) | 1 | 2 Go | 20 Go | Raft = quelques Mo de données |
| `haproxy` | HAProxy L4 en amont des control-planes | 1 | 1 Go | 15 Go | passthrough TLS, pas de terminaison |
| `platform` | GitLab CE + Harbor + **1× PostgreSQL** (Quadlet) | **4** | **16 Go** | 300 Go | poste le plus lourd du lab — RAM privilégiée sur le CPU (§2.4) |
| `data` | **OpenSearch + Dashboards** (heap 4 Go) + **RustFS** (S3) | 3 | 10 Go | 500 Go | logs centraux + buckets objet |
| `k8s-cp-1` | Control plane | 2 | 6 Go | 40 Go | membre etcd |
| `k8s-cp-2` | Control plane | 2 | 6 Go | 40 Go | membre etcd |
| `k8s-cp-3` | Control plane | 2 | 6 Go | 40 Go | membre etcd |
| `k8s-worker-1` | Worker | 4 | 12 Go | 80 Go **+ 100 Go** | pile d'observabilité ; 2ᵉ disque brut → DiskPool Mayastor |
| `k8s-worker-2` | Worker | 4 | 12 Go | 80 Go **+ 100 Go** | idem |
| `k8s-worker-3` | Worker | 4 | 12 Go | 80 Go **+ 100 Go** | idem |
| **Total** | | **29** | **86 Go** | **~1,53 To** | |

### 2.1 Bilan ressources

- **29 vCPU sur 32 threads — mais seulement 16 cœurs physiques.** C'est le chiffre à garder en tête : le ratio est de **0,9:1 sur les threads** et de **1,8:1 sur les cœurs réels**. L'Hyper-Threading n'ajoute pas de puissance de calcul, il améliore le taux d'occupation des unités d'exécution ; deux threads d'un même cœur ne valent pas deux cœurs. Le surengagement reste sain tant que les VMs sont majoritairement au repos — ce qui est le régime normal d'un homelab.
- **L'exception qui coûte cher : le `io-engine` Mayastor.** C'est un poller SPDK qui boucle sans jamais dormir ni bloquer : son thread est consommé à 100 % en charge **comme à vide**. Trois workers = **3 threads jamais disponibles**, soit potentiellement 3 cœurs physiques sur 16 — **près de 19 % de la puissance réelle de la machine, immobilisés en permanence** (§2.7, §17). C'est la contrepartie assumée du stockage répliqué, et c'est le poste de coût le plus important du plan après la RAM d'OpenSearch.
- **Le CPU est la ressource rare de ce lab, pas la RAM.** 86 Go alloués sur 128 laissent 42 Go de marge confortable, tandis que le CPU est engagé à près de 90 % des threads. Toute extension future doit donc être arbitrée en vCPU d'abord — c'est l'inverse de l'intuition habituelle.
- **86 Go sur 128 Go** : ~42 Go libres. C'est la marge délibérée qui absorbera les pics (`platform` en pleine CI, compaction Thanos) et servira de budget aux expérimentations IA (§16). Les **12 Go** des workers se lisent ainsi : **2 Go de HugePages réservées à Mayastor** (invisibles pour les pods ordinaires) + 10 Go réellement allouables, ce qui est le budget dont a besoin la pile d'observabilité (§11.7).
- **~1,53 To provisionné sur les 4 To de `local-lvm`** : le disque est **provisionné, pas consommé** — avec `discard=on` et l'émulation SSD (déjà activés dans le module OpenTofu), l'usage réel démarre autour de 15 % du provisionné sur un thin pool. La marge est donc large, et c'est elle qui rend le second disque des workers indolore (§2.6). **Le 2ᵉ disque échappe toutefois partiellement à cette règle** : Mayastor écrit ses métadonnées de pool dès la création, et un volume répliqué alloué en *thin* côté Mayastor se matérialise sur le thin pool LVM au fil des écritures.

### 2.2 Éteindre des VMs sans casser le cluster

Les VMs ne tournent pas toutes en permanence : le stack OpenTofu `vms/` permet l'extinction gracieuse d'une VM sans la détruire (`started = false`, ou `stopped_vms` pour une extinction ponctuelle). Toutes les VMs ne se valent pas pour autant.

| VM | Extinction | Conséquence |
|---|---|---|
| `k8s-cp-2`, `k8s-cp-3` | **Une seule des deux à la fois** | ⚠️ etcd à 3 membres tolère **1 panne**. En éteindre **2** fait perdre le quorum : l'API server passe en lecture seule, plus aucun déploiement n'est possible |
| `k8s-cp-1` | Comme les autres | Aucun rôle particulier une fois le cluster initialisé (le `--control-plane-endpoint` pointe sur HAProxy, pas sur cp-1) |
| `k8s-worker-3` | Libre | ⚠️ Éteindre un worker rend son **DiskPool Mayastor indisponible** : les volumes qui y ont une réplique passent en `Degraded`. Avec `repl: 2` sur 3 nœuds, on tolère **1 worker éteint** — pas deux. Vérifier `kubectl mayastor get volumes` (état `Online`) avant d'en éteindre un autre (§8.8) |
| `platform` | Libre | Plus de CI, plus de pull d'images depuis Harbor (les images déjà présentes sur les nœuds continuent de tourner) |
| `data` | Libre | Perte de la collecte de logs et des écritures Thanos/Tempo pendant l'arrêt — les métriques restent tamponnées côté Prometheus |
| `dns` | **À garder allumée** | SPOF : PKI, exposition des applications, résolution des FQDN de toutes les VMs |
| `openbao` | **À garder allumée** | Plus d'émission ni de renouvellement de certificats, injection de secrets K8s bloquée |
| `haproxy` | **À garder allumée** | Sans elle, plus d'accès à l'API K8s ni aux applications depuis le LAN |

> **Profil économe** (~21 vCPU / 58 Go) : `dns`, `ldap`, `openbao`, `haproxy`, `data`, les 3 control-planes et **2 workers**. On éteint `platform` et **un seul** worker — c'est le meilleur ratio, car ce sont les VMs les plus grosses et les moins critiques au repos.
>
> **Le plancher est de 2 workers allumés**, et c'est le stockage qui le fixe : avec `repl: 2`, un volume dont les deux répliques vivent sur les workers 2 et 3 devient totalement inaccessible si les deux sont éteints, et le pod qui le monte reste bloqué en `ContainerCreating`. Pour descendre réellement à 1 worker, il faudrait une `StorageClass` `repl: 1` réservée aux charges sacrifiables — ce n'est pas la configuration par défaut du lab.

### 2.3 Leviers d'optimisation retenus

| Levier | Gain | Détail |
|---|---|---|
| **Mutualisation de la VM `data`** | −1 VM (~2 vCPU / 2 Go) | OpenSearch et RustFS sont tous deux orientés stockage, sans concurrence CPU ; RustFS consomme ~200 Mo de RSS |
| **Heap OpenSearch à 4 Go** | −4 Go vs. dimensionnement standard | Volume de logs d'un homelab ≪ celui d'une prod ; nœud unique, `number_of_replicas: 0` |
| **Rétention Prometheus 24 h** | −2 à 3 Go RAM, −20 Go disque | Le long terme est délégué à Thanos sur objet (§11) : Prometheus ne garde que les blocs chauds |
| **Tempo en mode monolithique** | 1 pod au lieu de ~7 | Le mode distribué n'a d'intérêt qu'au-delà de plusieurs milliers de spans/s |
| **HAProxy sur VM minimale** | 1 vCPU / 1 Go | En L4 passthrough, HAProxy ne déchiffre rien : coût CPU quasi nul |
| **KSM sur l'hôte Proxmox** | 5 à 15 % de RAM | Les 12 VMs sortent du **même template Rocky 10** : les pages identiques (noyau, glibc, systemd) sont dédupliquées |
| **Ballooning Proxmox** | récupération dynamique | À activer sur `dns`, `ldap`, `openbao`, `haproxy` ; **à laisser désactivé** sur `platform`, `data` et les nœuds K8s (JVM, etcd et kubelet supportent mal une RAM qui bouge) |
| **Un seul agent de collecte** | −1 daemon par VM | L'OTel Collector remplace à lui seul Fluent Bit/Filebeat *et* node-exporter (§11) |

### 2.4 Note sur la VM `platform`

Avec **4 vCPU / 16 Go**, la VM héberge GitLab CE, Harbor et un PostgreSQL unique. C'est le poste qui absorbe l'essentiel de la réduction à 29 vCPU, et l'arbitrage est explicite : **on lui garde sa RAM et on lui prend du CPU**. GitLab tolère bien mieux un pic de latence qu'un OOM kill de Sidekiq ou de Gitaly, et les 16 Go restent le facteur dimensionnant.

Le dimensionnement est **serré mais viable** à condition de :
- **déporter les runners CI dans K8s** (ne pas les faire tourner ici) — avec 4 vCPU, ce n'est plus une préconisation mais une obligation ;
- surveiller la mémoire (GitLab Puma/Sidekiq + Gitaly + Harbor core/jobservice/trivy + PostgreSQL partagent 16 Go) ;
- réduire les workers Puma de GitLab (`puma['worker_processes'] = 2`) et désactiver son Prometheus embarqué — les métriques remontent déjà en OTLP (§11) ;
- **planifier les scans Trivy de Harbor hors des heures de CI** : c'est la tâche la plus gourmande en CPU de la VM, et la seule qui soit décalable sans conséquence ;
- activer le `housekeeping` Gitaly, qui sert autant le CPU que le disque (voir plus bas).

> **Le chemin d'upgrade a changé de nature.** Passer à 24 Go de RAM reste possible — la marge du §2.1 le permet largement. En revanche, **reprendre des vCPU est devenu le point dur** : il n'en reste que 3 non alloués, et ils sont la réserve de l'hyperviseur. Si la CI devient réellement pénible, l'arbitrage honnête sera de récupérer du CPU sur les workers K8s — donc de reconsidérer le coût du réacteur Mayastor (§2.7) — et non d'entamer la réserve.

Le disque de 300 Go porte les dépôts Gitaly et les blobs du registry. Comme tous les disques de VM, il vit sur `local-lvm`, donc sur le HDD (§2.6) : c'est le poste le plus sensible à ce choix, les dépôts Git étant faits d'une multitude de petits fichiers. Deux réglages compensent l'essentiel — **`housekeeping` Gitaly activé** (le `git gc` regroupe les objets en packfiles, transformant des accès aléatoires en accès séquentiels) et **cache de page généreux**, la VM ayant 16 Go.

### 2.5 Note sur la VM `data`

Elle porte deux rôles de stockage, volontairement regroupés :
- **OpenSearch + Dashboards** : nœud unique, `-Xms4g -Xmx4g`, swap désactivé, `bootstrap.memory_lock: true`.
- **RustFS** : service S3-compatible (Apache 2.0), conteneur Quadlet, données sur un volume dédié.

**Ses 3 vCPU** tiennent au même raisonnement que pour `platform` : OpenSearch est dimensionné par sa heap, pas par son CPU, et RustFS consomme ~200 Mo de RSS pour un travail essentiellement séquentiel. Le point de vigilance est la **compaction des index** — la mutualiser avec les fenêtres de compaction Thanos produirait deux charges CPU simultanées sur une VM qui n'a plus de marge.

C'est un **point de concentration assumé** : perdre cette VM, c'est perdre en même temps les logs, les blocs Thanos/Tempo et les sauvegardes Velero. Elle est donc la **première** du plan de sauvegarde Proxmox Backup Server (§13), et les snapshots OpenSearch ne doivent **pas** être écrits sur son propre RustFS.

### 2.6 Plan de stockage physique : SSD système, HDD données

L'hôte Proxmox dispose de deux supports, et leur répartition est **volontairement simple** :

| Support | Rôle | Ce qui y vit |
|---|---|---|
| **SSD 1 To** | Système de l'hyperviseur | Proxmox VE lui-même et son stockage `local` : images ISO, **template `9002`**, **snippets cloud-init** (`user-data`, `network-data` du module OpenTofu) |
| **HDD 4 To** | **`local-lvm`** — thin pool des disques de VM | **Tous** les disques de VM sans exception : racines, disque 300 Go de `platform`, disque 500 Go de `data`, et les **3 disques OpenEBS de 100 Go** des workers |

**Un seul datastore pour les VMs, et c'est un choix qui simplifie tout.** Le module `proxmox-vm` n'expose qu'un `disk_storage_id`, réutilisé pour le disque cloné et pour le drive cloud-init ; les disques supplémentaires (§4.5) en héritent par défaut. Aucune stack n'a donc à raisonner sur le placement : `disk_storage_id = "local-lvm"` dans les quatre `terraform.tfvars`, et c'est fini.

**Bilan de capacité** : ~1,53 To provisionné sur 4 To, soit **38 % du pool en provisionné** et bien moins en consommé réel grâce au thin provisioning. La marge est confortable, et elle est ce qui permet d'ajouter 300 Go de disques OpenEBS sans arbitrage. Deux règles pour qu'elle le reste :

- **Surveiller le taux de remplissage du thin pool** (`lvs -o lv_name,data_percent,metadata_percent`) et poser une alerte à 75 %. Un thin pool saturé met en erreur d'écriture **toutes** les VMs simultanément, y compris celles qui n'écrivaient rien — c'est le seul incident de stockage capable de tout arrêter d'un coup.
- **Ne pas laisser le datastore Proxmox Backup Server sur ce même HDD** (§13). Il n'est pas question de place mais de support : une panne du HDD emporterait à la fois les VMs et leurs sauvegardes.

> ⚠️ **Ce que la réplication protège — et ce qu'elle ne protège pas.** Les 3 `DiskPool` Mayastor sont portés par 3 VMs différentes, mais ces 3 VMs vivent sur **le même disque physique**. `repl: 2` protège donc contre la perte d'un *nœud* (VM éteinte, worker planté, drain pour mise à jour) — ce pour quoi elle est conçue et ce dont le lab a besoin. Elle ne protège **pas** contre la panne du HDD, qui reste le point de défaillance unique du stockage. La protection contre cette panne-là ne vient pas de Mayastor mais du plan de sauvegarde (§13) : PBS sur support distinct, et Velero pour les volumes du cluster.

> **Note sur l'émulation SSD.** Le module active `ssd = true` sur les disques, ce qui présente le périphérique à l'OS invité comme non rotatif. C'est nécessaire pour le `discard`/TRIM qui fait vivre le thin provisioning, mais l'invité en déduit aussi un ordonnanceur d'E/S sans réordonnancement (`none`). Sur un HDD réel, l'ordonnanceur `mq-deadline` rend de meilleurs services en fusionnant les E/S. À poser par Ansible via une règle udev sur les VMs les plus sollicitées en écriture (`data`, `platform`, workers), et à mesurer avant/après plutôt qu'à appliquer par principe.

### 2.7 Note sur les workers : le second disque et le coût de Mayastor

Chaque worker porte **deux disques**, et cette séparation n'est pas cosmétique — c'est une exigence du moteur Replicated PV Mayastor (§8.8).

| Disque | Interface | Taille | État attendu dans l'OS |
|---|---|---:|---|
| Racine | `scsi0` | 80 Go | Partitionné, monté sur `/` — cloné depuis le template `9002` |
| **Pool OpenEBS** | `scsi1` | **100 Go** | **Brut** : jamais partitionné, jamais formaté, jamais monté, absent de `/etc/fstab` |

> **Pourquoi un disque entier et pas un répertoire.** Mayastor ne consomme pas un système de fichiers : son `io-engine` prend le **contrôle exclusif d'un périphérique bloc** et y écrit sa propre structure de pool via SPDK, en contournant la pile de blocs du noyau. La documentation OpenEBS est explicite : une fois le pool créé, le périphérique ne doit être ni partitionné, ni formaté, ni partagé — et **toute donnée préexistante est détruite**. Un `DiskPool` posé par erreur sur le disque racine effacerait le système.

**Le dimensionnement à 100 Go.** Avec 3 pools de 100 Go et `repl: 2`, la capacité utile est de **~150 Go de PV**, chaque octet écrit l'étant deux fois. C'est largement au-dessus des besoins réels de la pile déployée (Prometheus 24 h, Tempo en cache, etcd des composants, PVC applicatifs), et la marge est délibérée : elle absorbe les **rebuilds**. Quand un worker revient après extinction, Mayastor reconstruit les répliques manquantes en copiant les données à pleine vitesse sur `vmbr1` — il faut de la place libre dans le pool pour que la reconstruction aboutisse.

**Ce que Mayastor coûte réellement sur chaque worker**, et c'est le vrai arbitrage de ce choix :

| Ressource | Coût par worker | Nature |
|---|---|---|
| **HugePages** | **2 Go** (1024 pages de 2 Mo) | **Réservation ferme** : ces 2 Go sortent définitivement de la mémoire allouable aux pods, que Mayastor s'en serve ou non. D'où les 12 Go de RAM (§2.1) |
| **CPU du `io-engine`** | **1 cœur à 100 %** | SPDK tourne en *poll mode* : le réacteur boucle sans dormir ni bloquer. Le cœur est **réellement** consommé, en charge comme à vide |
| **RAM du `io-engine`** | ~1 Go hors HugePages | Processus, métadonnées de pool, buffers |
| **Disque** | 100 Go provisionnés | Thin sur `local-lvm`, mais matérialisé au fil des écritures |

> ⚠️ **Le cœur qui tourne à 100 % est la contrepartie à assumer**, et elle est structurante sur cette machine : 3 workers × 1 thread = **3 threads jamais disponibles sur les 32**, adossés à **16 cœurs physiques seulement** (§2). Dans le pire cas — trois réacteurs sur trois cœurs distincts — c'est **près de 19 % de la puissance réelle immobilisée en permanence**. Trois conséquences pratiques :
> - **Limiter le réacteur à un seul cœur** (`io_engine.coreList: [3]`, soit le 4ᵉ vCPU du worker) — jamais deux, le défaut du chart n'étant pas adapté à un worker de 4 vCPU. Chaque worker n'offre donc plus que **~3 vCPU utiles** aux charges applicatives.
> - **Ne jamais laisser deux réacteurs se retrouver sur un même cœur physique.** Sur cette machine, les threads `N` et `N+16` partagent un cœur : deux boucles d'attente active sur une même paire se disputeraient les mêmes unités d'exécution. Sans épinglage, c'est l'ordonnanceur qui décide — d'où l'intérêt de vérifier la répartition réelle sous charge (`top -H -p $(pgrep -d, kvm)`) avant de conclure que tout va bien.
> - Le **mode interruption** est en cours d'implémentation en amont ; c'est le chemin de sortie naturel de cette contrainte, à surveiller lors des montées de version.

**Ce que le HDD change, et comment le plan en tient compte.** SPDK et NVMe-oF sont conçus pour du NVMe : ici le pool est adossé au thin pool `local-lvm` du HDD (§2.6), et c'est le disque mécanique — non le chemin de données — qui fixe le plafond. Concrètement, les écritures aléatoires d'un PV répliqué frappent **deux fois le même axe** (deux répliques, un seul disque physique), en concurrence avec toutes les autres VMs. Trois décisions en découlent, et elles sont ce qui rend ce choix tenable :

| Décision | Effet |
|---|---|
| Utiliser le schéma d'URI **`aio://`** et non `uring://` pour les `DiskPool` (§8.8) | C'est le schéma recommandé pour un périphérique non-PCI ; `io_uring` n'apporte rien sur un backend qui n'est pas NVMe |
| Réserver la `StorageClass` répliquée à ce qui **doit survivre à la perte d'un nœud** | Grafana, ArgoCD, applications métier — des volumes petits et peu écrits |
| Router l'**état chaud et reconstructible** vers **OpenEBS Local PV hostpath** (§8.8) | Prometheus (24 h, le long terme est sur Thanos), caches Tempo, espaces de travail des runners CI : une seule écriture au lieu de deux, et pas de traversée réseau. C'est le levier de performance le plus efficace du plan |

> **Corollaire pour le placement** : ne pas mettre les charges les plus gourmandes en CPU (compactor Thanos, runners GitLab CI) sur le même worker que celui qui porte l'egress gateway (§8.6) — les deux fonctions cumulées avec le réacteur Mayastor saturent un worker de 4 vCPU.

---

## 3. Topologie réseau & nommage

### 3.1 Conception à deux interfaces

Chaque VM porte **deux cartes réseau**, sur deux bridges Proxmox distincts. La question de conception n'est pas « combien d'interfaces » mais **laquelle porte la route par défaut** et **quel trafic passe par laquelle**.

| Interface | Bridge | Réseau | Passerelle | Rôle |
|---|---|---|---|---|
| `eth0` | `vmbr0` (ponté sur la NIC physique) | `192.168.1.0/24` — LAN du routeur wifi | **`192.168.1.1` (route par défaut)** | **Nord-sud** : accès depuis le poste d'admin, exposition des services, sortie Internet (mises à jour, pull d'images publiques) |
| `eth1` | `vmbr1` (bridge **isolé**, sans port physique) | `172.16.1.0/24` | **aucune** | **Est-ouest** : tout le trafic entre VMs — etcd, API K8s, PostgreSQL, LDAP, OpenBao, OTLP, S3, **réplication NVMe-oF/TCP d'OpenEBS** |

> Le LAN est bien un **`/24`** (`192.168.1.0/24`, 254 adresses), pas un `/32` — un `/32` ne désignerait qu'une seule adresse et ne permettrait aucune communication.

**Les trois règles qui font tenir la conception :**

1. **Une seule route par défaut, et elle est sur `eth0`.** Deux passerelles sur une même VM produisent un routage asymétrique et des connexions qui tombent au hasard. `vmbr1` n'a donc **aucune passerelle** : la seule route qu'il installe est celle, implicite, de son propre `/24`.
2. **`vmbr1` est un réseau plat, en un seul sous-réseau.** Un bridge isolé n'a pas de routeur : deux sous-réseaux différents sur `vmbr1` ne pourraient pas se joindre. D'où **un seul `172.16.1.0/24`**, découpé par plages d'adresses et non par sous-réseaux.
3. **Chaque service écoute sur l'interface qui correspond à son rôle.** PostgreSQL, etcd, LLDAP et l'API OpenBao ne se lient qu'à l'IP `172.16.1.x` ; seul ce qui doit être joint depuis le LAN (HAProxy, Dashboards, consoles web) écoute sur `192.168.1.x`. C'est cette discipline qui donne sa valeur au second bridge : **il n'est pas routable depuis le LAN, donc rien n'y est exposé par accident**.

```
                Internet
                   │
            Routeur wifi 192.168.1.1
                   │
      ┌────────────┴──────────── vmbr0 (192.168.1.0/24) ───────────┐
      │              route par défaut de chaque VM                 │
   ┌──┴───┐   ┌──────┐   ┌────────┐   ┌──────┐   ┌────┐   ┌────────┐
   │haprox│   │ dns  │   │platform│   │ data │   │ cp │   │ worker │
   │  y   │   │ ldap │   │        │   │      │   │1-3 │   │  1-3   │
   └──┬───┘   └──┬───┘   └───┬────┘   └──┬───┘   └─┬──┘   └───┬────┘
      │          │           │           │         │          │
      └──────────┴───────────┴───────────┴─────────┴──────────┘
                   vmbr1 (172.16.1.0/24, isolé, sans passerelle)
                 etcd · API K8s · PostgreSQL · LDAP · OTLP · S3
```

### 3.2 Plan d'adressage

**LAN — `192.168.1.0/24`, passerelle `192.168.1.1`** (réserver la plage dans le DHCP du routeur pour éviter les collisions)

| Plage | Usage |
|---|---|
| `192.168.1.200` | `haproxy` — point d'entrée unique : API K8s (`:6443`) et applications (`:80/:443`) |
| `192.168.1.201-.209` | VMs de services : `dns`, `ldap`, `openbao`, `platform`, `data` |
| `192.168.1.210-.219` | Control-planes (accès admin/SSH uniquement) |
| `192.168.1.220-.229` | Workers (accès admin/SSH + IP d'egress) |
| `192.168.1.230` | **IP d'egress unique des pods** (§8.5) — IP secondaire portée par le nœud gateway |

**Interne — `172.16.1.0/24`, aucune passerelle**

| Plage | Usage |
|---|---|
| `172.16.1.10-.19` | VMs de services (mêmes rôles, dernier octet aligné sur le LAN pour la lisibilité) |
| `172.16.1.20-.29` | Control-planes — **`--node-ip` de kubelet, adresses de pairs etcd** |
| `172.16.1.30-.39` | Workers — `--node-ip` de kubelet |

**Réseaux internes au cluster** (ni l'un ni l'autre bridge, gérés par Cilium/K8s)

| Segment | CIDR |
|---|---|
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/12` |

### 3.3 Conséquences pour Kubernetes

C'est le point où une conception multi-homée se paie si elle est laissée implicite : **kubelet choisit par défaut l'IP portant la route par défaut**, donc `192.168.1.x`. Il faut l'épingler explicitement, sinon le trafic inter-nœuds repartira sur le LAN.

| Composant | Réglage | Pourquoi |
|---|---|---|
| kubelet | `--node-ip=172.16.1.2x` (via `KUBELET_EXTRA_ARGS`) | Fixe l'`InternalIP` du nœud sur le réseau interne |
| kubeadm | `localAPIEndpoint.advertiseAddress = 172.16.1.2x` | L'API server s'annonce sur l'interne |
| kubeadm | `controlPlaneEndpoint = k8s-api.willbrid.lan:6443` → `192.168.1.200` | Le point d'entrée reste HAProxy, joignable depuis le LAN |
| kubeadm | `apiServer.certSANs` = **les deux IP + le FQDN** (`172.16.1.2x`, `192.168.1.200`, `k8s-api.willbrid.lan`) | Sans quoi `kubectl` depuis le poste d'admin échoue en erreur de certificat |
| etcd | `listen-peer-urls` / `initial-advertise-peer-urls` sur `172.16.1.2x` | Le trafic de consensus ne doit jamais transiter par le LAN |
| Cilium | `devices=eth1`, `k8s.nodeIP` interne, `ipv4NativeRoutingCIDR=172.16.1.0/24` | Sans `devices`, Cilium tente d'attacher ses programmes eBPF aux deux interfaces |
| sysctl | `net.ipv4.conf.all.rp_filter=0` (et `eth1`, `eth0`) | Le filtrage de chemin inverse **strict** casse le routage eBPF de Cilium sur une machine multi-homée. À poser par Ansible dans `/etc/sysctl.d/` |
| OpenEBS / Mayastor | Rien à régler — **hérité de `--node-ip`** | Les cibles NVMe-oF s'annoncent sur l'`InternalIP` du nœud, donc sur `172.16.1.3x`. C'est le bénéfice direct d'avoir épinglé `--node-ip` : la réplication de volumes — plus gros consommateur de bande passante est-ouest — reste sur `vmbr1` sans configuration supplémentaire. À vérifier après installation : `kubectl -n openebs get pods -o wide` et l'adresse des cibles dans `kubectl mayastor get volumes` |

> **Ce que ça donne concrètement** : un `kubectl` depuis le poste d'admin sort sur `192.168.1.200` (HAProxy), qui relaie vers `172.16.1.20-22:6443`. Tout le trafic de consensus, de stockage et d'observabilité reste sur `vmbr1`, invisible et inatteignable depuis le LAN.

### 3.4 Traduction dans le module OpenTofu

Le module `proxmox-vm` du dépôt `proxmox-infra/` implémente déjà exactement cette conception — aucune adaptation n'est nécessaire :

| Variable du module | Valeur | Correspondance |
|---|---|---|
| `network_bridge_primary` | `vmbr0` | `eth0`, LAN |
| `ip_address_primary` | `192.168.1.2xx/24` | IP LAN |
| `ip_gateway_primary` | `192.168.1.1` | **seule** passerelle déclarée |
| `network_bridge_secondary` | `vmbr1` | `eth1`, interne |
| `ip_address_secondary` | `172.16.1.xx/24` | IP interne, **sans passerelle** — le module n'en expose volontairement pas |
| `dns_servers` | `["172.16.1.10", "192.168.1.1"]` | CoreDNS interne en premier, routeur en secours |

Côté Proxmox, `vmbr1` se crée sans port physique ni adresse sur l'hôte :

```
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Aucune IP sur l'hôte : bridge purement L2 entre VMs.
```

> **Pas de DHCP sur `vmbr1`** : les adresses internes sont donc **toujours statiques**, injectées par cloud-init. C'est aussi pour cette raison que le module ne configure la seconde interface **que** si une IP est explicitement fournie — laisser un `dhcp` sur un bridge sans serveur DHCP bloque cloud-init plusieurs minutes au démarrage.

### 3.5 DNS interne — CoreDNS autonome (VM `dns`)

> **Important** : ce CoreDNS est un **serveur DNS d'infrastructure** installé sur la VM `dns`. Il ne faut **pas le confondre** avec le CoreDNS interne de Kubernetes (résolution intra-cluster `*.svc.cluster.local`), qui reste géré par le cluster. Les deux coexistent et n'ont pas le même rôle.

Rôle du CoreDNS de la VM `dns` :
- Autorité sur la zone interne **`willbrid.lan`**.
- Résolution des FQDN des VMs et services exposés.
- Forward des requêtes externes vers un résolveur upstream (ex. `1.1.1.1`/`8.8.8.8`).

Zone `willbrid.lan` — enregistrements types. **Chaque nom est résolu vers l'IP de l'interface qui correspond à son usage** (§3.1) :

| Nom | Cible | Interface |
|---|---|---|
| `k8s-api.willbrid.lan` | `192.168.1.200` (HAProxy) | LAN — joignable depuis le poste d'admin |
| `argocd.willbrid.lan`, `grafana.willbrid.lan`, `*.apps.willbrid.lan` | `192.168.1.200` (HAProxy → Gateway) | LAN — exposition des applications |
| `gitlab.willbrid.lan`, `harbor.willbrid.lan` | `192.168.1.204` | LAN — accès humain + push d'images |
| `dashboards.willbrid.lan` | `192.168.1.205` | LAN — OpenSearch Dashboards |
| `ldap.willbrid.lan`, `bao.willbrid.lan` | `172.16.1.11`, `172.16.1.12` | **Interne** — consommés uniquement par les services |
| `pg.willbrid.lan`, `s3.willbrid.lan`, `opensearch.willbrid.lan` | `172.16.1.14`, `172.16.1.15` | **Interne** — PostgreSQL, RustFS, API OpenSearch |
| `mail.willbrid.lan` (+ `MX` de la zone) | `172.16.1.10` | Interne — notifications entre services |

> Faire pointer un nom vers l'IP interne est ce qui **rend opérante la règle 3 du §3.1** : même si un service écoutait par erreur sur ses deux interfaces, ses clients passeraient par `vmbr1`. Prévoir une vue « split » quand un même service doit être joint des deux côtés — c'est le cas de `harbor` : LAN pour les humains, interne pour le kubelet qui tire les images.

Déploiement : CoreDNS en conteneur (Podman Quadlet) sur la VM `dns`, avec `Corefile` versionné et fichiers de zone montés en volume. Il écoute sur les **deux** interfaces — c'est l'exception assumée à la règle : les VMs l'interrogent par l'interne, le poste d'admin par le LAN. Prévoir une **résilience** (résolveur secondaire ou snapshot/restore rapide) car le DNS est un SPOF pour la PKI et l'exposition des applications.

---

## 4. Infrastructure as Code (depuis le bastion Ubuntu 24.04)

### 4.1 Outillage du bastion

| Outil | Rôle |
|---|---|
| OpenTofu | Provisioning des VMs Proxmox |
| Provider `bpg/proxmox` | Interface OpenTofu ↔ API Proxmox |
| Ansible | Configuration post-provisioning |
| `kubectl`, `helm`, `cmctl`, `bao`, `cosign`, `kubelogin` | Administration des couches hautes |
| `openssl` / `cfssl` | Root CA offline |
| Go (toolchain) | Compilation du générateur de CUID (§5.3) |

### 4.2 Préparation Proxmox

1. Template **cloud-init Rocky Linux 10** (image cloud, `qemu-guest-agent`, clé SSH bastion, durcissement minimal).
2. **Token API Proxmox** dédié à OpenTofu, rôle restreint (pas root).
3. Définir datastore(s) et bridge(s) réseau.

### 4.3 Structure OpenTofu

Presque rien n'est réécrit : ce projet **consomme les modules et le template déjà construits dans `proxmox-infra/`**. Les stacks propres au homelab DevSecOps vivent dans `devsecops-homelab/vms/`, bâties exactement sur le modèle de `proxmox-infra/vms/` — une stack = un répertoire = un état OpenTofu = un `module "vm"` en `for_each` sur une `map(object)`.

**Une seule évolution du socle est nécessaire** : le module `proxmox-vm` ne sait aujourd'hui créer qu'un disque (`scsi0`, cloné du template). Les disques OpenEBS des workers imposent de lui ajouter des disques supplémentaires — c'est l'objet du §4.5, et c'est une extension rétrocompatible (liste vide par défaut, aucune stack existante impactée).

```
homelab-sandbox/
├── proxmox-infra/                      # SOCLE — existant
│   ├── modules/
│   │   ├── proxmox-vm-template/        # image cloud → template
│   │   └── proxmox-vm/                 # template → VM (2 NIC, cloud-init, extinction gracieuse)
│   │                                   # ← extension : var.extra_disks (§4.5)
│   ├── templates/                      # stack qui construit rocky-linux-10-template (vm_id 9002)
│   └── vms/{rocky-linux-10,rocky-linux-9,ubuntu-2404}/
│
└── devsecops-homelab/                  # CE PROJET
    ├── README.md
    └── vms/
        ├── core/                       # dns, ldap, openbao, haproxy
        │   ├── main.tf                 # module "vm" { for_each = var.vms }
        │   ├── variables.tf            # map(object) vms + défauts de la stack
        │   ├── outputs.tf  versions.tf
        │   ├── terraform.tfvars.example
        │   └── tests/vm.tftest.hcl
        ├── platform/                   # gitlab + harbor + postgresql
        ├── data/                       # opensearch + rustfs
        └── k8s/                        # k8s-cp-1..3, k8s-worker-1..3
```

Chaque stack pointe vers le module partagé et vers le template Rocky 10 déjà construit :

```hcl
module "vm" {
  source   = "../../../proxmox-infra/modules/proxmox-vm"
  for_each = var.vms

  template_vm_id = var.template_vm_id   # 9002 — rocky-linux-10-template
  vm_name        = each.key             # devient le hostname cloud-init
  # …
}
```

**Pourquoi ce découpage en 4 stacks plutôt qu'une seule**

| Stack | Contenu | Raison de l'isoler |
|---|---|---|
| `core` | `dns`, `ldap`, `openbao`, `haproxy` | Socle quasi immuable dont tout le reste dépend. On veut pouvoir replanifier le cluster sans jamais toucher à OpenBao |
| `platform` | `platform` | Seule VM au cycle de vie « applicatif » (montée en RAM prévue au §2.4) |
| `data` | `data` | Porte les données les plus difficiles à reconstruire : `prevent_destroy` s'y justifie |
| `k8s` | 3 CP + 3 workers | La stack la plus volatile — recréation de nœuds lors d'une montée de version. C'est aussi celle qui pilote l'extinction sélective du §2.2 |

Le rayon d'action d'une erreur est ainsi borné : un `tofu destroy` malheureux dans `k8s` ne peut pas emporter l'annuaire ni les secrets.

**Ce que la structure apporte concrètement**

| Choix hérité de `proxmox-infra/vms` | Effet ici |
|---|---|
| `for_each` sur `map(object)` | Ajouter un worker = une entrée dans `terraform.tfvars`, jamais un fichier `.tf` de plus |
| La clé de la map = nom de la VM | `k8s-cp-1` devient le `hostname` **et** le FQDN `k8s-cp-1.willbrid.lan` injectés par cloud-init |
| `stopped_vms` | Extinction gracieuse sans édition des tfvars : `tofu apply -var='stopped_vms=["platform","k8s-worker-3"]'` (§2.2) |
| `tests/*.tftest.hcl` + `mock_provider` | `tofu test` valide le câblage et les validations de variables **sans toucher à Proxmox** |
| `terraform.tfvars.example` versionné | Les identifiants Proxmox restent hors du dépôt |

Extrait de `vms/k8s/terraform.tfvars` :

```hcl
template_vm_id  = 9002                   # rocky-linux-10-template (proxmox-infra/templates)
disk_storage_id = "local-lvm"            # thin pool sur le HDD 4 To (§2.6)

network_bridge_primary   = "vmbr0"       # LAN
network_bridge_secondary = "vmbr1"       # interne, isolé
dns_servers              = ["172.16.1.10", "192.168.1.1"]
dns_domain               = "willbrid.lan"

vms = {
  "k8s-cp-1" = {
    vm_id                = 211
    cpu_cores            = 2
    memory               = 6144
    disk_size            = 40
    tags                 = ["k8s", "control-plane"]
    ip_address_primary   = "192.168.1.210/24"
    ip_gateway_primary   = "192.168.1.1"
    ip_address_secondary = "172.16.1.20/24"   # aucune passerelle : cf. §3.1
    # pas d'extra_disks : aucun io-engine sur les control-planes (§8.8)
  }
  "k8s-worker-1" = {
    vm_id                = 221
    cpu_cores            = 4
    memory               = 12288                    # 10 Go utiles + 2 Go de HugePages (§2.7)
    disk_size            = 80                       # scsi0 — racine
    tags                 = ["k8s", "worker", "openebs"]
    ip_address_primary   = "192.168.1.220/24"
    ip_gateway_primary   = "192.168.1.1"
    ip_address_secondary = "172.16.1.30/24"

    # scsi1 — disque brut dédié au DiskPool Mayastor (§4.5, §8.8).
    # Ni partitionné, ni formaté, ni monté : ni cloud-init ni Ansible n'y touchent.
    extra_disks = [{
      interface = "scsi1"
      size      = 100
      serial    = "openebs0"                        # → /dev/disk/by-id/…_openebs0
      backup    = false                             # données répliquées + Velero (§13)
    }]
  }
  # k8s-cp-2/3 (sans extra_disks) ; k8s-worker-2/3 : mêmes extra_disks
}
```

> **Les control-planes n'ont volontairement pas de second disque** : ils ne porteront pas le label `openebs.io/engine=mayastor` et n'exécuteront aucun `io-engine` (§8.8). Leur en donner un immobiliserait 100 Go qu'aucun `DiskPool` ne consommerait — et exposerait surtout au risque de créer un pool sur un nœud etcd, dont les fsync ne doivent partager le disque avec rien d'autre.

> **Ordre d'application** : `core` → `data` → `platform` → `k8s`. Les stacks étant indépendantes, la dépendance n'est pas exprimée par OpenTofu mais par cet ordre — les IP étant statiques et planifiées au §3.2, aucune stack n'a besoin de lire l'état d'une autre. C'est délibéré : pas de `terraform_remote_state`, donc pas de couplage entre états.

- **Backend d'état** : local chiffré au départ, migration vers GitLab une fois disponible (bootstrap poule/œuf).

### 4.4 Ansible

- Inventaire dynamique Proxmox ou statique généré par `output` OpenTofu.
- Rôles : `common`, `harden`, puis `coredns_host`, `podman_host`, `k8s_node`, `opensearch_node`, **`openebs_node`** (§8.8), etc.

### 4.5 Évolution du module `proxmox-vm` — disques supplémentaires

Le module ne déclare aujourd'hui qu'un seul bloc `disk`, en dur sur `scsi0`. Les workers ayant besoin d'un second disque brut, il faut lui apprendre à en attacher d'autres. L'extension est conçue pour être **rétrocompatible** : liste vide par défaut, donc aucun `plan` non désiré sur les stacks `proxmox-infra/vms/*` existantes.

> **Statut : implémenté.** `var.extra_disks` existe dans `proxmox-infra/modules/proxmox-vm` **et** dans `proxmox-infra/modules/proxmox-vm-template`, et est câblé dans les trois stacks `proxmox-infra/vms/*`. Ce qui suit décrit le résultat ; les validations font foi dans `variables.tf`.

**`variables.tf`** — une liste d'objets plutôt qu'un simple nombre, parce que le besoin porte autant sur les *attributs* du disque que sur sa taille :

```hcl
variable "extra_disks" {
  type = list(object({
    interface    = string
    size         = number
    serial       = optional(string)
    datastore_id = optional(string)      # null = var.disk_storage_id
    file_format  = optional(string)      # null = choix du stockage Proxmox
    discard      = optional(string, "on")
    ssd          = optional(bool, true)
    iothread     = optional(bool, true)
    backup       = optional(bool, true)
    replicate    = optional(bool, true)
  }))
  default  = []
  nullable = false
  # Validations : interface ∈ scsi1…scsi30 (scsi0 réservé, message dédié),
  # interfaces uniques, size > 0, serial ≤ 20 caractères [A-Za-z0-9._-] et unique
  # au sein de la VM, discard ∈ {on, ignore}, file_format ∈ {raw, qcow2, vmdk, null}.
}
```

Deux écarts assumés par rapport au premier jet de cette section :

- **`file_format` n'est pas figé à `raw`.** L'attribut est `Optional+Computed` côté provider : laissé à `null`, le format est celui qu'impose le stockage cible — `raw` sur LVM/ZFS, `qcow2` sur un stockage répertoire. Le figer ferait perdre le thin-provisioning et les snapshots sur un stockage répertoire, sans rien apporter sur `local-lvm`.
- **Le bus est restreint à `scsi`.** Le provider relit les disques **triés par interface** (`utils.OrderedListFromMap`) alors que le bloc `disk` est une *liste* en état. Un `ide0` ou un `sata0`, qui trient avant `scsi0`, décaleraient la liste et produiraient un diff permanent au plan. Toutes les interfaces acceptées trient après `scsi0` : ordre de la config et ordre de l'état coïncident.

**`main.tf`** — un bloc `dynamic` ajouté après le `disk` existant :

```hcl
  # Disques supplémentaires. La clé de la map étant l'interface, l'ordre des blocs
  # générés est déterministe (tri lexicographique) : pas de diff parasite au plan.
  dynamic "disk" {
    for_each = { for d in var.extra_disks : d.interface => d }
    content {
      datastore_id = coalesce(disk.value.datastore_id, var.disk_storage_id)
      interface    = disk.key
      size         = disk.value.size
      file_format  = disk.value.file_format   # null = choix du stockage
      serial       = disk.value.serial
      discard      = disk.value.discard
      ssd          = disk.value.ssd
      iothread     = disk.value.iothread
      backup       = disk.value.backup
      replicate    = disk.value.replicate
    }
  }
```

L'absence de `file_id` est ce qui rend le disque vierge : Proxmox alloue un volume neuf au lieu de copier une image.

**Le `boot_order` n'a pas à changer.** Il vaut déjà `["scsi0"]` : le disque OpenEBS, vierge et sans table de partition, n'est de toute façon pas amorçable, mais l'expliciter évite qu'un BIOS tente de le sonder au démarrage.

**Côté stack**, le champ est ajouté à la `map(object)` des `vms` (mêmes attributs que le module, les validations restant portées par ce dernier) et transmis tel quel :

```hcl
# main.tf de la stack
module "vm" {
  # …
  extra_disks = each.value.extra_disks
}
```

**Le chemin stable est exposé en output**, plutôt que reconstruit à la main côté Ansible :

```hcl
# module proxmox-vm
output "extra_disk_device_paths" {   # { "scsi1" = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_openebs0" }
  value = { for d in var.extra_disks : d.interface =>
            "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_${d.serial}" if d.serial != null }
}
```

Il remonte dans l'output `vms` de chaque stack : c'est lui que consommera le rôle `openebs_node` pour déclarer ses `DiskPool` (§8.8), sans jamais nommer un `/dev/sdX`.

**Côté template** (`proxmox-vm-template`), la même variable existe, avec deux différences : `file_format` retombe sur `var.disk_format` plutôt que sur le choix du stockage, et l'output `extra_disk_interfaces` liste les interfaces héritées. La stack `proxmox-infra/templates` l'expose par template — `ubuntu_2404_extra_disks`, `rocky_9_extra_disks`, `rocky_10_extra_disks` — sur le modèle des variables `*_disk_size` existantes. **À n'utiliser que si TOUTES les VMs issues du template doivent porter le disque** — un disque déclaré sur le template doit être redéclaré à l'identique dans `var.extra_disks` du module `proxmox-vm`, sinon le provider planifie sa suppression sur le clone. Pour le besoin OpenEBS, qui ne concerne que les workers, c'est bien la variable du module `proxmox-vm` qu'il faut utiliser.

**Points de vigilance de cette extension** — les trois vraies difficultés :

| Point | Détail |
|---|---|
| **Ajout d'un disque sur une VM clonée** | Le provider `bpg/proxmox` (v0.108.0) apparie les disques par interface. Un `scsi1` absent du template est donc créé, mais c'est le chemin le moins éprouvé du provider. Les `tofu test` (`mock_provider`) sont écrits et passent — modules et stacks ; **il reste à confirmer par un `tofu plan` réel** avant de l'appliquer aux trois workers |
| **La taille n'est réductible que par recréation** | Comme pour `disk_size`, agrandir se fait en place ; réduire impose de détruire la VM. Fixer 100 Go dès le départ, et prévoir plutôt `maxExpansion` côté `DiskPool` (§8.8) |
| **Nom de périphérique instable** | `/dev/sdb` peut devenir `/dev/sdc` après un redémarrage. C'est exactement ce que le champ `serial` évite : le `DiskPool` référencera `/dev/disk/by-id/…`, jamais `/dev/sdX` (§8.8) |

> **Vérification après le premier `apply`**, avant toute création de pool : `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT` doit montrer un `sdb` de 100 Go **sans `FSTYPE` ni `MOUNTPOINT`**, et `ls -l /dev/disk/by-id/` doit exposer le lien portant le `serial`. Si `FSTYPE` est renseigné, quelque chose a formaté le disque — ne pas créer le `DiskPool` avant d'avoir compris quoi.

---

## 5. Identité : LLDAP & génération des CUID (script Go)

### 5.1 Pourquoi LLDAP

Annuaire léger avec UI web, interface LDAP standard consommable par OpenBao, GitLab, Harbor, ArgoCD/Dex.

### 5.2 Organisation (base DN `dc=willbrid,dc=lan`)

```
dc=willbrid,dc=lan
├── ou=people          # comptes humains, uid=<cuid>
└── groups (natif LLDAP)
    ├── lldap_admin
    ├── willbrid_admins
    ├── k8s_admins
    ├── k8s_developers
    ├── gitlab_users
    └── harbor_users
```

### 5.3 Génération des identifiants CUID — script Go (CUID v2)

**Objectif** : identifiant opaque, collision-résistant, utilisé comme `uid` LDAP. CUID **v2** (v1 déprécié).

**Bibliothèque Go recommandée** : `github.com/nrednav/cuid2` (implémentation Go de CUID2).

Squelette illustratif :

```go
package main

import (
	"fmt"

	"github.com/nrednav/cuid2"
)

func main() {
	// Générateur avec longueur personnalisée (24 par défaut)
	generate, err := cuid2.Init(cuid2.WithLength(24))
	if err != nil {
		panic(err)
	}
	uid := "usr_" + generate()
	fmt.Println(uid) // ex: usr_tz4a98xxat96iws9zmbrgj3a
}
```

**Workflow d'onboarding** (piloté depuis le bastion) :
1. Le binaire Go génère le `uid` = `usr_<cuid2>`.
2. Le script crée le compte via l'**API GraphQL de LLDAP** (ou LDIF), avec `displayName`, `mail`, `givenName`, `sn` pour la lisibilité humaine.
3. Ajout aux groupes cibles.
4. Enregistrement dans un **registre chiffré versionné** `personne ↔ CUID` pour l'audit.

> **Règle** : le CUID est l'identifiant technique stable ; toutes les UIs affichent `displayName`/`mail`.

---

## 6. PKI : Root CA offline → Intermediate CA (OpenBao)

### 6.1 Modèle à deux niveaux

```
Root CA  (offline, bastion, jamais en ligne)
   │  signe une seule fois
   ▼
Intermediate CA  (moteur PKI d'OpenBao)
   │  émet à la demande
   ▼
Certificats de service  (ldap, gitlab, harbor, argocd, Gateway, mail, mTLS…)
```

### 6.2 Étapes

1. **Root CA (bastion, offline)** : `openssl`/`cfssl`, clé protégée par passphrase, stockée chiffrée hors-ligne, validité longue (10 ans).
2. **Intermediate dans OpenBao** : activer `pki`, générer la CSR d'intermédiaire, la **signer avec la Root offline**, réimporter le certificat signé.
3. **Rôles d'émission** : domaines `*.willbrid.lan`, TTL max, usages.
4. **Distribution** : cert **public** de la Root dans le trust store de toutes les VMs + cert-manager côté K8s.

### 6.3 cert-manager

`ClusterIssuer` de type Vault (compatible OpenBao) → délivrance/renouvellement automatiques des certificats du `Gateway` (§8.4) et des services internes.

---

## 7. OpenBao (secrets manager)

| Aspect | Choix |
|---|---|
| Stockage | **Raft intégré** |
| Scellement | Auto-unseal si possible ; sinon Shamir manuel au début |
| Auth humaine | **LDAP** (LLDAP) → groupes → policies |
| Auth machines K8s | Méthode **Kubernetes** (ServiceAccount → policies) |
| Injection K8s | **OpenBao Secrets Operator** |
| PKI | Intermediate CA (§6) |

Policies au moindre privilège : une par consommateur (gitlab, harbor, PostgreSQL, chaque namespace K8s, mail, opensearch).

---

## 8. Kubernetes (kubeadm + Cilium)

### 8.1 Bootstrap kubeadm

1. Pré-requis nœuds (Ansible) : swap off, modules `br_netfilter`/`overlay`, sysctl (dont `rp_filter=0`, §3.3), **containerd**, SELinux compatible, `--node-ip` sur l'IP interne.
2. `kubeadm init` sur `k8s-cp-1`, piloté par un fichier `ClusterConfiguration` plutôt que par des flags — c'est plus lisible et versionnable :
   - `controlPlaneEndpoint: k8s-api.willbrid.lan:6443` → HAProxy `192.168.1.200`,
   - `localAPIEndpoint.advertiseAddress: 172.16.1.20` (interne),
   - `apiServer.certSANs` : `172.16.1.20`, `192.168.1.200`, `k8s-api.willbrid.lan`,
   - `networking.podSubnet: 10.244.0.0/16`, `serviceSubnet: 10.96.0.0/12`,
   - `--skip-phases=addon/kube-proxy` (Cilium le remplace),
   - paramètres OIDC (§8.7).
3. Installer les **CRD Gateway API** (§8.4) **avant** Cilium.
4. Joindre `k8s-cp-2/3` (`--control-plane`) puis les workers.

> **HA dès le départ** (§2) : les 3 membres etcd sont posés immédiatement. Le cluster tolère la perte d'**un** control-plane — pas deux (§2.2).

### 8.2 Cilium (CNI)

- `kubeProxyReplacement=true`, mode eBPF, `devices=eth1` et `ipv4NativeRoutingCIDR=172.16.1.0/24` (§3.3).
- `l7Proxy=true` + `gatewayAPI.enabled=true` en *host network mode* (§8.4).
- **Hubble** (observabilité réseau) + NetworkPolicies Cilium ; les flux Hubble sont exportables vers l'OTel Collector (§11).
- `egressGateway.enabled=true` (§8.6).
- Option chiffrement pod-à-pod (WireGuard) — inutile ici puisque `vmbr1` est un bridge isolé sans port physique, mais activable si un second nœud Proxmox rejoint le lab.

### 8.3 Entrée du cluster — VM HAProxy dédiée, en amont des control-planes

**Rôle** : une **VM HAProxy unique** (`192.168.1.200`) fait du **load-balancing L4 (nord→sud entrant)** en amont du cluster. Elle est le **point d'entrée unique du lab** depuis le LAN, pour deux flux distincts :

1. **API server** : `:6443` réparti sur les 3 control-planes (`172.16.1.20-22`). C'est ce qui donne son sens au `--control-plane-endpoint` : l'adresse ne bouge pas quand un master tombe ou est éteint (§2.2).
2. **Applications** : `:80/:443` répartis vers les workers, où la **Gateway Cilium** écoute en *host network mode* (§8.4). C'est ce qui remplace MetalLB : plutôt qu'une IP `LoadBalancer` gérée dans le cluster, HAProxy expose une IP stable et route vers les nœuds.

```
              Poste d'admin / navigateur (LAN 192.168.1.0/24)
                                │
                       192.168.1.200  ── VM haproxy (1 vCPU / 1 Go)
                                │      L4 passthrough, aucune terminaison TLS
         ┌──────────────────────┴──────────────────────┐
         │ :6443                                       │ :80 / :443
         ▼                                             ▼
  172.16.1.20-22:6443                          172.16.1.30-32:8080/8443
  kube-apiserver (cp-1/2/3)                    Gateway Cilium (host network)
         └──────────────── vmbr1, réseau interne ──────┘
```

**Configuration** — les deux frontends sont en `mode tcp` : HAProxy ne déchiffre rien, les certificats restent gérés par l'API server et par cert-manager côté Gateway.

```
frontend k8s-api
    bind 192.168.1.200:6443
    mode tcp
    default_backend k8s-api

backend k8s-api
    mode tcp
    balance roundrobin
    option tcp-check
    server cp-1 172.16.1.20:6443 check
    server cp-2 172.16.1.21:6443 check
    server cp-3 172.16.1.22:6443 check

frontend apps-https
    bind 192.168.1.200:443
    mode tcp
    default_backend apps-https

backend apps-https
    mode tcp
    balance roundrobin
    server w1 172.16.1.30:8443 check
    server w2 172.16.1.31:8443 check
    server w3 172.16.1.32:8443 check
```

> **Pas de keepalived pour l'instant** — décision assumée. Cette VM est donc un **SPOF** : sans elle, plus d'accès à l'API ni aux applications depuis le LAN (le cluster, lui, continue de tourner : les nœuds se parlent par `vmbr1`). Le coût de cette simplicité est faible et le chemin de sortie est balisé : ajouter une seconde VM `haproxy-2` avec la même configuration, keepalived pour faire flotter `192.168.1.200` entre les deux, et **rien d'autre ne change** — ni le DNS, ni `--control-plane-endpoint`, ni les certificats, puisque tout référence déjà cette IP et non un nœud.

> **Restauration rapide** : la VM ne porte aucun état. Sa reconstruction complète = `tofu apply` sur la stack `core` + le rôle Ansible `haproxy`. C'est la mitigation retenue à la place de keepalived en phase 1.

### 8.4 Exposition des applications — Gateway API implémentée par Cilium

L'**Ingress** est figé depuis des années : toute fonctionnalité un peu fine (réécriture, en-têtes, split de trafic, gRPC) passe par des annotations propriétaires au contrôleur. La **Gateway API** (`gateway.networking.k8s.io/v1`) est son successeur officiel et modélise nativement ce qui était jusque-là hors standard. C'est elle qui est retenue ici — **il n'y a pas d'`Ingress` ni d'ingress-nginx dans ce homelab**.

**Implémentation : Cilium.** Décision structurante, et c'est aussi une optimisation : Cilium est déjà le CNI, il embarque Envoy, et il est conforme Gateway API. Il n'y a donc **aucun contrôleur supplémentaire à déployer, ni pod, ni RAM en plus** — là où ingress-nginx aurait coûté un DaemonSet et ~500 Mo.

Pré-requis (tous déjà satisfaits ou triviaux) :

| Pré-requis | État |
|---|---|
| `kubeProxyReplacement=true` | ✅ déjà la décision du §8.2 |
| `l7Proxy=true` (Envoy) | ✅ activé par défaut |
| CRD Gateway API installées avant Cilium | À faire — `kubectl apply` du *standard channel* (GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, TLSRoute…) |
| `GatewayClass` nommée `cilium` | Créée par le contrôleur Cilium |

**Mode d'exposition : *host network mode*** (Cilium ≥ 1.16). Par défaut, Cilium crée un `Service` de type `LoadBalancer` par `Gateway` — inutilisable ici puisqu'il n'y a pas de MetalLB. Le *host network mode* fait écouter les listeners **directement sur les interfaces des nœuds**, ce qui est exactement ce dont HAProxy a besoin en backend :

```yaml
# valeurs Helm Cilium
gatewayAPI:
  enabled: true
  hostNetwork:
    enabled: true
    nodes:
      matchLabels:
        node-role.kubernetes.io/worker: ""   # Gateway uniquement sur les workers
```

Les ports privilégiés (<1024) n'étant pas liables dans ce mode, les listeners écoutent en **8080/8443** et HAProxy fait la translation 80/443 → 8080/8443 (§8.3).

**Le modèle de rôles**, qui est le vrai apport de la Gateway API sur ce projet :

| Ressource | Qui la possède | Où elle vit |
|---|---|---|
| `GatewayClass` (`cilium`) | Fournisseur d'infrastructure | Fournie par Cilium |
| `Gateway` | **Opérateur du cluster** — c'est vous | Namespace `gateway`, géré par ArgoCD (§12), avec les certificats cert-manager |
| `HTTPRoute` / `GRPCRoute` | **Développeur applicatif** | Namespace de l'application, livré avec elle |

Une équipe applicative attache une route sans jamais toucher au `Gateway` ni à ses certificats ; le `Gateway` contrôle en retour qui a le droit de s'y attacher via `allowedRoutes`. C'est la séparation que l'`Ingress` ne permettait pas.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: apps
  namespace: gateway
  annotations:
    cert-manager.io/cluster-issuer: openbao-issuer     # §6.3
spec:
  gatewayClassName: cilium
  listeners:
    - name: https
      protocol: HTTPS
      port: 8443
      hostname: "*.apps.willbrid.lan"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: apps-willbrid-lan-tls               # émis par cert-manager
      allowedRoutes:
        namespaces:
          from: Selector                              # pas "All" : on choisit
          selector:
            matchLabels:
              gateway-access: "true"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  parentRefs:
    - name: apps
      namespace: gateway
  hostnames: ["argocd.apps.willbrid.lan"]
  rules:
    - backendRefs:
        - name: argocd-server
          port: 80
```

> **Attacher une route depuis un autre namespace** exige un `ReferenceGrant` côté ressource cible — c'est explicite, contrairement à l'`Ingress` où la frontière n'existait pas. Bonne nouvelle pour le volet sécurité du lab : la surface d'exposition devient elle-même déclarative et auditable, donc contrôlable par Kyverno (§8.7).

### 8.5 Autres composants de plateforme K8s

| Composant | Rôle | Choix |
|---|---|---|
| Exposition | HTTP(S), gRPC | **Gateway API via Cilium** (host network, derrière HAProxy) — §8.4 |
| Stockage | PV dynamiques | **OpenEBS** — Replicated PV Mayastor (`repl: 2`, NVMe-oF/TCP sur `eth1`) + Local PV hostpath pour l'état chaud — §8.8 |
| Certificats | TLS auto | cert-manager + `ClusterIssuer` OpenBao |
| Secrets | Injection | OpenBao Secrets Operator |
| Policies | Admission | Kyverno (images signées Harbor uniquement) |
| Observabilité | Métriques, logs, traces | **OpenTelemetry Collector** → Prometheus/Thanos, OpenSearch, Tempo (§11) |

### 8.6 Sortie du cluster — Cilium Egress Gateway (IP unique)

**Objectif** : tout le trafic sortant des pods vers l'extérieur apparaît avec **une seule IP source**, utile pour du filtrage/allowlisting côté services externes.

**Point de conception lié au §3** : l'IP d'egress doit être portée par l'interface **qui fait face à l'extérieur**, donc `eth0` (LAN). C'est `192.168.1.230`, une IP secondaire posée sur l'interface LAN du nœud gateway — et non une adresse du réseau interne, qui ne sait rien router vers Internet.

**Mise en œuvre (dans Cilium, pas sur la VM HAProxy)** :
- Activer `enable-ipv4-egress-gateway=true` dans Cilium.
- Désigner un **nœud gateway** (un worker) et lui poser le label `egress-node=true`.
- Définir une `CiliumEgressGatewayPolicy` : sélecteur de pods → egress via ce nœud → **SNAT vers `192.168.1.230`**.

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-all
spec:
  selectors:
    - podSelector: {}                 # tous les pods (affiner par namespace au besoin)
  destinationCIDRs:
    - 0.0.0.0/0
  excludedCIDRs:
    - 172.16.1.0/24                   # le trafic est-ouest ne doit pas être SNATé
    - 192.168.1.0/24
  egressGateway:
    nodeSelector:
      matchLabels:
        egress-node: "true"
    egressIP: 192.168.1.230
```

> Les `excludedCIDRs` sont essentiels dans cette topologie : sans eux, un pod joignant PostgreSQL ou OpenSearch sur `172.16.1.x` verrait son trafic détourné vers le nœud gateway puis SNATé — un détour inutile qui casserait au passage toute règle de filtrage basée sur l'IP source.

**Entrée et sortie ne se mélangent pas** : HAProxy (entrant) et l'egress gateway (sortant) sont deux rôles opposés. L'egress est géré **par Cilium, à l'intérieur du cluster** : le point de sortie est un **nœud K8s** (celui portant `egress-node`), **pas la VM HAProxy**. Un point de sortie *hors cluster* supposerait de router la route par défaut des pods vers une VM NAT dédiée — possible, mais plus fragile, et écarté ici.

> **Conséquence sur l'extinction sélective (§2.2)** : éteindre le nœud gateway coupe l'accès Internet de tous les pods. Poser le label `egress-node` sur un worker qui reste allumé, ou le déplacer avant d'éteindre.

### 8.7 Authentification des utilisateurs du cluster via LDAP

K8s délègue l'authn à un **fournisseur OIDC**. Pont OIDC ↔ LDAP via **Dex adossé à LLDAP**.

```
Utilisateur ──(login LDAP)──► Dex (OIDC provider)
                                │  ID token (JWT)
                                ▼
kubectl (kubelogin) ──► kube-apiserver (--oidc-issuer-url=Dex)
                                          │  valide le JWT
                                          ▼
                                RBAC (groupes LDAP → ClusterRoleBindings)
```

1. **Dex** avec connecteur LDAP vers LLDAP (`userSearch` sur `ou=people`, `groupSearch` sur les groupes ; claims `email`, `groups`).
2. **kube-apiserver** (flags kubeadm) :
   - `--oidc-issuer-url=https://dex.willbrid.lan`
   - `--oidc-client-id=kubernetes`
   - `--oidc-username-claim=email`
   - `--oidc-groups-claim=groups`
   - `--oidc-ca-file=<Root CA>`
3. **Client** : `kubectl` + `kubelogin` (oidc-login).
4. **RBAC** : `k8s_admins` → `cluster-admin` ; `k8s_developers` → rôles restreints par namespace.

> Utiliser `email` comme username (lisible dans l'audit), `groups` pour l'autorisation ; le CUID reste l'ancrage LDAP.

### 8.8 Stockage persistant — OpenEBS (Replicated PV Mayastor + Local PV)

**Le choix.** OpenEBS est installé une fois et fournit **deux moteurs** qui répondent à deux besoins qu'il serait coûteux de confondre :

| Moteur | `StorageClass` | Pour quoi | Ce que ça coûte |
|---|---|---|---|
| **Replicated PV Mayastor** | `openebs-replicated` | Ce qui **doit survivre à la perte d'un nœud** : Grafana, ArgoCD, applications métier | 2 écritures + un aller-retour NVMe-oF/TCP sur `vmbr1` |
| **Local PV hostpath** | `openebs-hostpath` | Ce qui est **chaud, volumineux et reconstructible** : TSDB Prometheus (24 h — le long terme vit sur Thanos), caches Tempo, espaces de travail des runners CI | Rien, mais le volume disparaît avec le nœud |

Ce couple est le levier de performance central du plan (§2.7) : sur un backend HDD, éviter la double écriture là où elle n'apporte rien vaut mieux que n'importe quel réglage. La règle de décision est simple — **« si ce volume est perdu, dois-je le reconstruire à la main ? »** Si la réponse est non (Prometheus se re-remplit, Thanos a l'historique), c'est du Local PV.

#### 8.8.1 Prérequis à poser par Ansible (rôle `openebs_node`)

Ce sont les prérequis officiels d'OpenEBS pour Mayastor, confrontés à ce lab :

| Prérequis | Cible du lab | Statut |
|---|---|---|
| Kubernetes ≥ 1.23 | kubeadm, version courante (§8.1) | ✅ |
| Noyau Linux ≥ 5.15 | Rocky Linux 10 (noyau 6.x) | ✅ |
| CPU x86-64 avec **SSE4.2** | `cpu_type = "x86-64-v3"` imposé par Rocky 10 — v3 inclut SSE4.2 | ✅ acquis |
| Modules noyau **`nvme-tcp`**, `ext4` (et `xfs`) | À charger et à rendre persistants | **À faire** |
| **HugePages** : ≥ 2 Go en pages de 2 Mo (**1024 pages**) | 12 Go de RAM par worker (§2.1) | **À faire** |
| **2 cœurs CPU** par pod `io-engine` | Contrainte relâchée à **1 cœur** via `io_engine.coreList` (§2.7) | **Écart assumé** |
| ≥ 3 nœuds de stockage | 3 workers, HA dès le départ (§2) | ✅ |
| Label **`openebs.io/engine=mayastor`** sur les nœuds de stockage | Workers uniquement, jamais les control-planes | **À faire** |
| Helm ≥ v3.7 | Bastion Ubuntu 24.04 (§4.1) | ✅ |
| Ports **10124** (gRPC) et **8420/4421** (cibles NVMf) | Sur `vmbr1` entre workers | **À ouvrir** (firewalld) |
| Paramètre noyau `nvme_core.multipath=Y` | Recommandé pour la HA du chemin de données | **À faire** (grubby + reboot) |

Traduction en tâches Ansible :

```yaml
# HugePages — 1024 pages de 2 Mo = 2 Go, persistant
- copy:
    dest: /etc/sysctl.d/99-openebs-hugepages.conf
    content: "vm.nr_hugepages = 1024\n"
  notify: reload sysctl

# Modules noyau, persistants au boot
- copy:
    dest: /etc/modules-load.d/openebs.conf
    content: "nvme_tcp\next4\nxfs\n"
- community.general.modprobe: { name: nvme_tcp, state: present }

# Multipath NVMe (HA du chemin de données)
- command: grubby --update-kernel=ALL --args="nvme_core.multipath=Y"

# Ports du plan de données, sur la zone interne uniquement (§3.1)
- firewalld: { port: "{{ item }}", zone: internal, permanent: true, state: enabled }
  loop: ["10124/tcp", "8420/tcp", "4421/tcp"]
```

> ⚠️ **Deux pièges d'ordonnancement, et ils coûtent cher en temps de diagnostic :**
> 1. **Les HugePages doivent être en place avant que kubelet ne démarre**, sinon le nœud ne publie pas la ressource `hugepages-2Mi` et les pods `io-engine` restent indéfiniment en `Pending` — sans message explicite. Après avoir modifié `vm.nr_hugepages`, **redémarrer kubelet** (le reboot du `nvme_core.multipath` s'en charge : enchaîner les deux tâches dans le même rôle, puis rebooter une fois).
> 2. **Vérifier l'allocation réelle**, pas la demande : `grep HugePages_Total /proc/meminfo` doit renvoyer 1024. Sur une VM déjà chargée, la mémoire peut être trop fragmentée pour réserver 2 Go de pages contiguës — d'où l'intérêt de poser ce rôle **avant** de déployer quoi que ce soit sur le cluster (§15, phase 4).

#### 8.8.2 Installation

Le chart `openebs/openebs` installe les moteurs par toggles. On ne garde que le nécessaire :

```yaml
# valeurs Helm — namespace openebs
engines:
  local:
    lvm:    { enabled: false }    # inutile : pas de VG dédié dans les VMs
    zfs:    { enabled: false }    # inutile : pas de zpool
  replicated:
    mayastor: { enabled: true }

mayastor:
  io_engine:
    # Un seul réacteur, épinglé sur le 4e vCPU du worker (§2.7).
    coreList: [3]
  etcd:
    # etcd interne à OpenEBS (métadonnées des volumes) — sans rapport avec
    # l'etcd du cluster (§8.1). 3 réplicas, un par worker.
    replicaCount: 3
```

> **L'etcd d'OpenEBS n'est pas celui de Kubernetes.** Il stocke la configuration des volumes répliqués et il est **critique** : le perdre, c'est perdre la carte des répliques, pas les données elles-mêmes. Ses PVC doivent aller sur du **Local PV hostpath** — pas sur Mayastor, qui en dépend (dépendance circulaire au démarrage).

Puis le label des nœuds de stockage :

```bash
kubectl label node k8s-worker-1 k8s-worker-2 k8s-worker-3 openebs.io/engine=mayastor
```

#### 8.8.3 Les `DiskPool` — un par worker

C'est ici que le disque `scsi1` du §2.7 entre en jeu. **Une règle domine toutes les autres : ne jamais référencer `/dev/sdX`.** Les noms de périphériques dépendent de l'ordre de découverte au démarrage ; un `scsi1` devenu `/dev/sdc` après un reboot ferait pointer le pool sur un autre disque — et Mayastor **détruit toute donnée préexistante** sur le périphérique qu'on lui confie. Le champ `serial` posé dans OpenTofu (§4.5) existe exactement pour cela.

```yaml
apiVersion: "openebs.io/v1beta3"
kind: DiskPool
metadata:
  name: pool-worker-1
  namespace: openebs
spec:
  node: k8s-worker-1                                        # = hostname du nœud
  disks: ["aio:///dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_openebs0"]
  maxExpansion: "2x"
```

| Choix | Raison |
|---|---|
| **`aio://`** et non `uring://` | Schéma recommandé pour un périphérique non-PCI ; `io_uring` n'apporte rien sur un backend HDD (§2.7) |
| **`/dev/disk/by-id/…`** | Lien stable au reboot, adossé au `serial` défini dans OpenTofu. `by-path` est l'alternative acceptable |
| **`maxExpansion: "2x"`** | **Non modifiable après création** — le défaut `1x` interdirait toute croissance. Avec `2x`, agrandir le disque Proxmox de 100 à 200 Go suffira à étendre le pool sans rien recréer |
| `spec.node` = hostname | Le module cloud-init pose `vm_name` comme hostname (§4.3) : `k8s-worker-1` est donc à la fois la clé de la map OpenTofu, le nom du nœud K8s et la valeur attendue ici |

> Le nom exact du lien `by-id` **doit être relevé sur la VM** (`ls -l /dev/disk/by-id/`) avant d'écrire le manifeste : la forme `scsi-0QEMU_QEMU_HARDDISK_<serial>` est celle produite par un disque SCSI QEMU, mais le préfixe varie selon le contrôleur. C'est la dernière vérification du §4.5.

#### 8.8.4 Les `StorageClass`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-replicated
provisioner: io.openebs.csi-mayastor
parameters:
  protocol: nvmf
  repl: "2"
  fsType: ext4
volumeBindingMode: Immediate
allowVolumeExpansion: true
reclaimPolicy: Delete
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-hostpath
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: openebs.io/local
parameters:
  StorageType: hostpath
  BasePath: /var/openebs/local
# Obligatoire pour un volume local : le PV n'existe qu'une fois le pod placé.
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

**Aucune des deux n'est déclarée classe par défaut**, et c'est délibéré : sur ce lab, choisir entre « répliqué » et « local » est une décision de conception qui doit rester explicite dans chaque `PersistentVolumeClaim`. Un PVC sans `storageClassName` échouera visiblement plutôt que d'atterrir en silence sur le mauvais moteur — Kyverno (§8.7) peut d'ailleurs refuser les PVC qui n'en précisent pas.

`repl: "2"` sur 3 nœuds est le point d'équilibre du lab : il tolère la perte d'un worker (§2.2) sans payer la triple écriture d'un `repl: 3` sur un backend HDD partagé (§2.6).

#### 8.8.5 Exploitation

- **Le plugin `kubectl mayastor`** est l'outil de diagnostic à installer sur le bastion (§4.1) : `kubectl mayastor get pools`, `get volumes` (états `Online` / `Degraded` / `Faulted`), `get replicas`.
- **Métriques** : Mayastor expose un exporter Prometheus ; il est scrapé par le `ServiceMonitor` de kube-prometheus-stack (§11.3) et rejoint donc Thanos comme le reste. Les alertes utiles sont peu nombreuses mais indispensables — **pool à plus de 80 %**, **volume en `Degraded` depuis plus de 15 minutes**, **`io-engine` non prêt**.
- **Rebuild** : au retour d'un worker éteint, la reconstruction des répliques est automatique et sature `vmbr1` le temps qu'elle dure. C'est attendu ; c'est aussi la raison pour laquelle on n'éteint pas deux workers de suite sans vérifier le retour à `Online` (§2.2).
- **Snapshots et clones** sont disponibles côté Mayastor, mais la sauvegarde de référence reste **Velero** (§13), qui capture le PVC *et* l'objet Kubernetes qui le décrit.

---

## 9. Couche plateforme : VM `platform` (GitLab + Harbor, PostgreSQL unique, Podman Quadlet)

### 9.1 Principe

Une VM Rocky Linux 10, Podman + Quadlet :
- **Un seul PostgreSQL** conteneurisé, hébergeant **deux bases** (`gitlabhq_production`, `harbor`) avec deux rôles/utilisateurs distincts.
- **GitLab CE** (conteneur).
- **Harbor** (core, jobservice, registry, portal, trivy) — conteneurs.
- Réseaux Podman séparés, mais **tous deux autorisés à joindre le conteneur PostgreSQL**.

### 9.2 Organisation Quadlet suggérée

```
/etc/containers/systemd/
├── data.network              # réseau partagé DB
├── postgres.container        # PostgreSQL UNIQUE (bases gitlab + harbor)
├── gitlab.network
├── gitlab.container          # GitLab CE (After=postgres)
├── harbor.network
├── harbor-core.container
├── harbor-registry.container
├── harbor-jobservice.container
├── harbor-portal.container
└── harbor-trivy.container    # (After=postgres)
```

Points d'attention :
- **PostgreSQL unique** : provisionner à l'init deux bases + deux users (script d'init monté dans `/docker-entrypoint-initdb.d`). Séparer les droits pour que GitLab et Harbor ne voient que leur base.
- **Ordonnancement** : `After=`/`Requires=` pour démarrer PostgreSQL avant GitLab et Harbor.
- **Réseau** : le conteneur `postgres` est attaché au réseau `data`, lui-même joint par les conteneurs GitLab et Harbor (ou un réseau partagé unique). Ne pas exposer PostgreSQL hors de la VM.
- **Volumes persistants** : dépôts Git (Gitaly), blobs registry, données PG — sauvegardés séparément.
- **TLS/reverse proxy** : frontal présentant `gitlab.willbrid.lan` et `harbor.willbrid.lan` avec certs OpenBao.
- **Ports** : arbitrer 443 (Harbor), 80/443 + Git-SSH (GitLab) pour éviter les collisions.

> **Vigilance Harbor + Quadlet** : Harbor est officiellement livré en docker-compose → **traduction manuelle** en unités `.container`/`.network`. Le fait de pointer Harbor vers un PostgreSQL **externe** (le conteneur partagé) au lieu de son PG embarqué est justement une des adaptations à faire dans sa config (`harbor.yml` → `external_database`). Point d'intégration le plus délicat : prévoir du test.

### 9.3 Intégrations

| Service | Auth | TLS | Secrets |
|---|---|---|---|
| GitLab | LDAP (LLDAP) | cert OpenBao | mdp PG depuis OpenBao |
| Harbor | LDAP (LLDAP) | cert OpenBao | idem |

- Harbor : Trivy (scan) + signature Cosign ; projets, quotas, rétention.
- GitLab : runners **dans K8s** (runner Kubernetes), pas sur cette VM.

---

## 10. VM `dns` : CoreDNS + mini-serveur mail

### 10.1 CoreDNS (voir §3.5)

Conteneur Quadlet, autorité `willbrid.lan`, forward upstream.

### 10.2 Mini-serveur mail conteneurisé

**Besoin** : un serveur mail interne léger pour les notifications du homelab (GitLab, Harbor, Alertmanager, ArgoCD, alertes OpenSearch).

**Choix recommandé** : une image « all-in-one » légère type **docker-mailserver** (Postfix + Dovecot) ou, si seul l'envoi sortant suffit, un **relais SMTP** minimal. Pour un homelab, deux profils :

| Profil | Ce qu'il fait | Quand |
|---|---|---|
| **Relais SMTP sortant** (léger) | Reçoit les mails des services et les envoie/relaie | Si tu veux juste des notifications |
| **Serveur mail complet** (docker-mailserver) | SMTP + IMAP + boîtes | Si tu veux aussi *recevoir* et consulter |

Mise en œuvre (Quadlet sur la VM `dns`) :
- Conteneur mail, volumes pour données/boîtes, cert TLS émis par OpenBao (`mail.willbrid.lan`).
- **DNS** : enregistrement `MX` de `willbrid.lan` → `mail.willbrid.lan` dans CoreDNS ; enregistrement `A` du host mail.
- **Comptes de service** : adresses type `noreply@willbrid.lan`, `alerts@willbrid.lan`.
- Les services (GitLab/Harbor/Alertmanager/ArgoCD) pointent leur config SMTP vers `mail.willbrid.lan:587` (creds dans OpenBao).

> **Note** : la remise vers l'extérieur (Internet) est souvent bloquée par les fournisseurs (réputation IP, SPF/DKIM/DMARC). Pour un homelab, réserver ce serveur au **trafic interne** ; pour de l'envoi externe fiable, configurer un relais via un service SMTP tiers.

---

## 11. Observabilité : OpenTelemetry Collector → Prometheus/Thanos, OpenSearch, Tempo, Grafana

### 11.1 Principe directeur : une seule collecte, trois backends

Le piège classique d'un homelab d'observabilité est d'empiler un agent par signal : un exporter pour les métriques, un shipper pour les logs, un SDK pour les traces — chacun avec sa configuration, son format et son cycle de vie. La conception retenue inverse ce rapport : **un seul agent, l'OpenTelemetry Collector, collecte les trois signaux**, les enrichit d'attributs communs, puis les route vers le backend spécialisé de chacun.

L'intérêt n'est pas seulement d'économiser des daemons (§2.3). C'est que **l'enrichissement se fait une fois, au même endroit, pour les trois signaux** : un log, une métrique et une trace issus du même pod portent exactement les mêmes `k8s.namespace.name`, `k8s.pod.name`, `service.name`. C'est précisément ce qui rend possible de sauter d'une trace Tempo vers les logs OpenSearch correspondants dans Grafana — corrélation impossible à obtenir de façon fiable quand trois agents étiquettent chacun à sa manière.

| Signal | Backend | Rétention | Stockage |
|---|---|---|---|
| **Métriques** | Prometheus (chaud) → **Thanos** (long terme) | 24 h local / 1 an sur objet | RustFS, bucket `thanos` |
| **Logs** | **OpenSearch** — VMs *et* applications K8s | 14 j chaud, puis suppression (ISM) | VM `data` |
| **Traces** | **Tempo** (mode monolithique) | 7 j | RustFS, bucket `tempo` |
| **Visualisation** | **Grafana** — les trois en datasources | — | — |

### 11.2 Architecture de collecte

Trois niveaux de Collector, chacun avec un rôle distinct. C'est la répartition recommandée par la documentation OpenTelemetry pour Kubernetes : les composants qui lisent l'état **local d'un nœud** vont en DaemonSet, ceux qui interrogent **l'API du cluster** vont en instance unique.

```
  VMs hors K8s (dns, ldap, openbao, haproxy, platform, data)
  ┌──────────────────────────────────────────┐
  │ OTel Collector (systemd / Quadlet)       │
  │  journald · filelog · hostmetrics        │──────┐
  └──────────────────────────────────────────┘      │
                                                    │ OTLP/gRPC
  Cluster K8s                                       │ 172.16.1.x:4317
  ┌──────────────────────────────────────────┐      │
  │ AGENT — DaemonSet (1 par nœud)           │      │
  │  kubeletstats · hostmetrics · filelog    │──────┤
  │  otlp (SDK des applications)             │      │
  └──────────────────────────────────────────┘      │
  ┌──────────────────────────────────────────┐      │
  │ CLUSTER — Deployment, 1 réplica STRICT   │──────┤
  │  k8s_cluster · k8sobjects (événements)   │      │
  └──────────────────────────────────────────┘      │
                                                    ▼
                        ┌───────────────────────────────────────┐
                        │ GATEWAY — Deployment, 2 réplicas      │
                        │  k8sattributes · resourcedetection    │
                        │  memory_limiter · transform · batch   │
                        │  tail_sampling (traces)               │
                        └───────┬──────────┬────────────┬───────┘
                                │          │            │
                  otlphttp      │          │ opensearch │ otlp
                                ▼          ▼            ▼
                         Prometheus    OpenSearch     Tempo
                              │        (VM data)        │
                        Thanos sidecar                  │
                                └──── RustFS (S3) ──────┘
                                       thanos / tempo
```

**Composants par niveau**

| Niveau | Receivers | Rôle |
|---|---|---|
| **Agent** (DaemonSet) | `kubeletstats` (métriques nœud/pod/conteneur/volume), `hostmetrics` (CPU, mémoire, disque, réseau — via `hostfs`), `filelog` (`/var/log/pods`, parser `container`), `otlp` (SDK applicatifs, endpoint local) | Tout ce qui est **local au nœud** |
| **Cluster** (Deployment, **1 réplica**) | `k8s_cluster` (état global : phases de pods, conditions de nœuds), `k8sobjects` (événements Kubernetes) | Tout ce qui interroge l'**API server** |
| **Gateway** (Deployment, 2 réplicas) | `otlp` uniquement | Traitement, échantillonnage, export |
| **VM** (systemd/Quadlet) | `journald`, `filelog`, `hostmetrics` | Remplace à lui seul Fluent Bit **et** node-exporter |

> ⚠️ **`k8s_cluster` et `k8sobjects` doivent tourner en un seul exemplaire.** Deux réplicas produiraient chacun le jeu complet de métriques et d'événements du cluster : doublons silencieux, compteurs faux. C'est le piège n° 1 de ce type de déploiement — d'où l'instance « cluster » séparée du gateway, qui lui peut être scalé librement.

**Processors du gateway**, dans cet ordre (l'ordre compte) :

| Processor | Rôle |
|---|---|
| `memory_limiter` | **Toujours en premier** : rejette proprement sous pression plutôt que de se faire tuer par l'OOM killer |
| `k8sattributes` | Le composant central en environnement K8s : associe chaque donnée à son pod et y injecte namespace, nom, labels, node |
| `resourcedetection` | Ajoute `host.name`, `os.type` — indispensable pour les signaux venant des VMs hors cluster |
| `transform` / `redaction` | Filtre les attributs sensibles **avant** export (tokens, en-têtes `Authorization`, e-mails) — cf. §16.8 |
| `tail_sampling` | Sur les traces uniquement : garde 100 % des erreurs et des requêtes lentes, échantillonne le reste. Principal levier de volume |
| `batch` | **Toujours en dernier**, juste avant les exporters |

**Déploiement** : via l'**OpenTelemetry Operator** (CRD `OpenTelemetryCollector`, `mode: daemonset|deployment`), livré par ArgoCD. L'Operator apporte aussi l'auto-instrumentation par annotation, utile pour les applications qui n'embarquent pas de SDK.

### 11.3 Métriques — Prometheus + Thanos

**Ingestion OTLP native.** Prometheus expose depuis la v3 un endpoint `/api/v1/otlp/v1/metrics` : le gateway y pousse directement via l'exporter `otlphttp`, sans passer par `remote_write` ni par un scrape inversé.

```
--web.enable-otlp-receiver
--storage.tsdb.retention.time=24h        # le long terme, c'est Thanos
--storage.tsdb.min-block-duration=2h
--storage.tsdb.max-block-duration=2h     # obligatoire avec le sidecar Thanos
```

**Ce que fait le scrape Prometheus classique, et ce que fait OTLP.** Les deux coexistent volontairement : le `ServiceMonitor` de kube-prometheus-stack continue de scraper les cibles qui exposent déjà `/metrics` (kubelet, etcd, apiserver, Cilium), tandis qu'OTLP porte les métriques applicatives et celles des VMs. Il serait contre-productif de tout faire passer par le Collector : `prometheusreceiver` est un composant à état dont le scaling est délicat.

**Thanos** — composants retenus, réduits au strict nécessaire :

| Composant | Rôle | Coût |
|---|---|---|
| **Sidecar** | Téléverse les blocs de 2 h vers RustFS, expose Prometheus au Query | conteneur additionnel dans le pod Prometheus |
| **Store Gateway** | Rend les blocs historiques du bucket interrogeables | ~500 Mo |
| **Query** | Point d'entrée unique : fusionne Prometheus (chaud) et Store (froid) — **c'est la datasource de Grafana** | ~256 Mo |
| **Compactor** | Compaction, déduplication, **downsampling 5 m / 1 h**, application de la rétention | ~512 Mo, s'exécute par à-coups |

Le **Ruler n'est pas déployé** : les règles d'alerte restent dans Prometheus, ce qui évite un composant de plus pour un bénéfice nul à cette échelle. Alertmanager (kube-prometheus-stack) notifie vers `mail.willbrid.lan` (§10.2).

> Le **downsampling du Compactor** est ce qui rend un an de rétention soutenable : au-delà de 40 jours les séries passent à un point toutes les 5 min, au-delà de 90 jours à un point par heure. Le bucket `thanos` reste de l'ordre de quelques dizaines de Go.

### 11.4 Logs — OpenSearch, backend unique

**Tous** les logs vont dans OpenSearch : ceux des VMs comme ceux des applications du cluster. Un seul moteur de recherche, une seule syntaxe de requête, un seul plan de rétention.

**Chemin d'ingestion** — deux options, à trancher au moment de l'implémentation :

| Option | Fonctionnement | Compromis |
|---|---|---|
| **`opensearch` exporter** (contrib) | Le gateway écrit directement dans OpenSearch | Le plus simple : aucun composant en plus. Statut *alpha* en amont — à valider sur volume réel |
| **Data Prepper** | Le gateway envoie en OTLP à Data Prepper (outil du projet OpenSearch), qui indexe | Chemin le plus supporté, pipelines de transformation riches — mais un service de plus à héberger |

Recommandation : **démarrer avec l'exporter `opensearch`** (cohérent avec l'objectif d'un seul agent et d'un minimum de pièces mobiles) et basculer sur Data Prepper si l'indexation devient le goulot d'étranglement.

**Organisation des index** — un pattern par périmètre, pour que les politiques de rétention diffèrent :

| Pattern | Contenu | ISM |
|---|---|---|
| `logs-vm-*` | journald + fichiers des 6 VMs hors cluster | 14 j |
| `logs-k8s-*` | `/var/log/pods` de tous les nœuds | 14 j |
| `logs-audit-*` | audit K8s, accès OpenBao, connexions LDAP | **90 j** — c'est la traçabilité sécurité |
| `events-k8s-*` | événements récupérés par `k8sobjects` | 7 j |

**Réglages VM `data`** (§2.5) : nœud unique, `-Xms4g -Xmx4g`, `number_of_replicas: 0` (un seul nœud ne peut pas répliquer : laisser 1 laisserait tous les index en état `yellow` en permanence), swap désactivé, `bootstrap.memory_lock: true`. Politique ISM pour le cycle de vie, snapshots vers un stockage **externe** à la VM. Plugin *security* activé, authentification adossée à LLDAP.

### 11.5 Traces — Tempo

- **Mode monolithique** (`SingleBinary`) : un pod au lieu des ~7 du mode distribué. Suffisant très largement à l'échelle du lab.
- **Backend objet** : bucket `tempo` sur RustFS. Tempo n'indexe pas le contenu des traces — le stockage reste compact et le coût mémoire faible.
- **Ingestion** : OTLP depuis le gateway, après `tail_sampling`.
- **Réception** : les applications instrumentées (SDK OTel, ou auto-instrumentation par l'Operator) envoient à l'agent DaemonSet local, jamais directement au backend.

### 11.6 Grafana — visualisation et corrélation

Trois datasources, et surtout les liens entre elles — c'est là que la conception paie :

| Datasource | Pointe vers |
|---|---|
| **Thanos Query** | Métriques chaudes + historiques, vue unifiée |
| **Tempo** | Traces |
| **OpenSearch** | Logs (plugin datasource officiel) |

**Chaînes de corrélation à configurer** :
- **Trace → logs** : `Trace to logs` de la datasource Tempo vers OpenSearch, filtré sur `trace_id`. Depuis un span en erreur, on obtient en un clic les lignes de log du même pod sur la même fenêtre.
- **Logs → trace** : champ `trace_id` des logs rendu cliquable (`data links`) vers Tempo. Cela suppose que les applications injectent `trace_id`/`span_id` dans leurs logs — c'est le travail du SDK OTel, automatique avec l'auto-instrumentation.
- **Métriques → traces** : exemplars Prometheus, pour sauter d'un pic de latence à une trace représentative.

Authentification Grafana par **OIDC via Dex** (§8.7), RBAC mappé sur les groupes LLDAP. Exposition par la Gateway API : `grafana.apps.willbrid.lan` (§8.4).

### 11.7 Ce que cette conception coûte

| Composant | Emplacement | RAM approx. |
|---|---|---|
| OTel agents (DaemonSet ×3) | workers | 3 × 200 Mo |
| OTel gateway (×2) + cluster (×1) | workers | 3 × 400 Mo |
| Prometheus (rétention 24 h) + sidecar Thanos | worker | ~2 Go |
| Thanos Query + Store + Compactor | workers | ~1,3 Go |
| Tempo monolithique | worker | ~1 Go |
| Grafana | worker | ~256 Mo |
| **Total in-cluster** | | **~6,5 Go** |
| OpenSearch (heap 4 Go + overhead) | VM `data` | ~7 Go |
| OTel agents VM (×6) | VMs | 6 × 150 Mo |

Soit ~6,5 Go sur les **30 Go réellement allouables** des workers — 36 Go de RAM au total moins les 6 Go de HugePages réservées à Mayastor (3 × 2 Go, §2.7). C'est ce calcul qui fixe les 12 Go par worker (§2.1), et il laisse ~23 Go aux applications.

---

## 12. GitOps : ArgoCD

- ArgoCD dans le cluster, **SSO OIDC via Dex** (réutilise le connecteur LDAP), RBAC mappé sur groupes LDAP.
- Modèle **App of Apps** :

```
gitops/
├── bootstrap/       # app root
├── platform/        # cert-manager · gateway (GatewayClass + Gateway + certs) · kyverno
│                    # otel-operator + collectors · kube-prometheus-stack · thanos
│                    # tempo · grafana · openebs (mayastor + diskpools + SC)
│                    # openbao-secrets-operator · dex
└── apps/            # applications métier (chacune livre son HTTPRoute)
```

### 12.1 Boucle CI/CD

```
Dev push ──► GitLab CI :
   build ──► push Harbor ──► scan Trivy ──► signature Cosign
                                              │
   (si conforme) maj tag dans repo GitOps
                                              ▼
                              ArgoCD sync ──► Kyverno vérifie signature
                                              ▼
                              Déploiement K8s (pull image Harbor)
```

---

## 13. Sauvegarde & durcissement

| Domaine | Mise en œuvre |
|---|---|
| Sauvegarde VMs | Snapshots + Proxmox Backup Server — **`data` en priorité 1** (§2.5) |
| Sauvegarde K8s | Velero → bucket `velero` sur RustFS — **c'est la sauvegarde de référence des PV OpenEBS** (§8.8) |
| Disques OpenEBS | **Exclus des sauvegardes PBS** (`backup = false`, §4.5) : sauvegarder un pool Mayastor bloc à bloc donnerait une image incohérente et doublerait le volume pour rien. La protection passe par Velero |
| Bases | Dumps du PostgreSQL unique (bases gitlab + harbor) |
| OpenBao | Snapshots Raft |
| LLDAP | Export config/LDIF |
| OpenSearch | Snapshots d'index — vers une destination **externe à la VM `data`**, jamais son propre RustFS |
| Blocs Thanos / Tempo | Déjà sur RustFS ; le bucket est sauvegardé par le snapshot Proxmox de `data` |
| Policies | Kyverno (images signées, no `latest`, non-root, `HTTPRoute` restreintes) |
| Réseau | NetworkPolicies Cilium + Hubble ; services liés à `eth1` uniquement (§3.1) |
| Secrets | Rotation OpenBao, rien en clair dans Git |

> **Le point faible de ce plan est circulaire, et la topologie du §2.6 le rend plus aigu** : RustFS héberge les sauvegardes Velero — donc les données des PV OpenEBS — *et* réside sur la VM `data`, elle-même sauvegardée par PBS. Or **toutes** les VMs vivent sur le même HDD 4 To. Une panne de ce disque emporterait simultanément les VMs, les pools Mayastor et le bucket `velero`. La réplication `repl: 2` n'y change rien : elle protège du nœud perdu, pas du disque perdu (§2.6).
>
> **Le datastore PBS doit donc impérativement être sur un troisième support** — disque externe USB 3, second disque interne ou NAS. Ce n'est pas une optimisation : sans lui, il n'existe aucune copie des données hors du HDD, et le plan de sauvegarde n'en est pas un. Le SSD système n'est pas un candidat acceptable non plus (une panne y emporterait Proxmox et les sauvegardes ensemble, et sa capacité ne suffirait pas).

---

## 14. Ordre de dépendances (résumé)

```
Bridges vmbr0/vmbr1 + local-lvm (HDD 4 To) + template Rocky 10 (9002) + token API Proxmox
  └─► Module proxmox-vm : var.extra_disks (§4.5) ─► OpenTofu : core → data → platform → k8s
        └─► Ansible (common, harden, node-ip, rp_filter, openebs_node)
              ├─► CoreDNS (willbrid.lan) + mini-mail        [VM dns]
              ├─► HAProxy L4 (192.168.1.200)                [VM haproxy]
              ├─► LLDAP (uid=CUID v2, script Go) ──────────┐
              ├─► Root CA offline (bastion)                 │
              │     └─► OpenBao (Intermediate CA) + LDAP ◄──┘
              ├─► OpenSearch + RustFS (buckets)             [VM data]
              └─► Kubernetes (kubeadm + Cilium, 3 CP + 3 workers)
                    ├─► CRD Gateway API ─► Cilium (kube-proxy replacement, l7Proxy)
                    │     ├─► Gateway API en host network  ◄── HAProxy :80/:443
                    │     └─► Cilium Egress Gateway (192.168.1.230)
                    ├─► cert-manager (ClusterIssuer OpenBao) ─► certs du Gateway
                    ├─► OpenEBS  (prérequis nœud : hugepages + nvme-tcp + label)
                    │     ├─► DiskPool ×3 (scsi1, by-id)
                    │     └─► SC openebs-replicated (repl 2) + openebs-hostpath
                    ├─► Dex (OIDC↔LDAP) ─► authn users K8s
                    ├─► OTel Operator ─► agents + gateway
                    │     ├─► Prometheus (OTLP) ─► Thanos ─► RustFS
                    │     ├─► OpenSearch (logs VMs + apps)
                    │     └─► Tempo ─► RustFS
                    │           └─► Grafana (3 datasources + corrélation)
                    └─► OpenBao Secrets Operator
                          └─► VM platform : GitLab + Harbor + PostgreSQL unique
                                └─► ArgoCD (SSO Dex) ─► Kyverno
                                      └─► CI/CD complet ─► socle IA (§16)
```

---

## 15. Plan d'action par phases

### Phase 0 — Préparation
- [ ] Installer sur Ubuntu 24.04 : OpenTofu, Ansible, kubectl, helm, cmctl, `bao`, cosign, kubelogin, toolchain Go.
- [ ] Créer le bridge **`vmbr1`** sur Proxmox (`bridge-ports none`, aucune IP hôte) — §3.4.
- [ ] **Stockage** (§2.6) : vérifier que le thin pool **`local-lvm` est bien adossé au HDD 4 To**, que le SSD ne porte que Proxmox et son stockage `local`, et que `local` accepte le contenu **`snippets`** (requis par le module pour `user-data`/`network-data`).
- [ ] Poser une **alerte de remplissage du thin pool à 75 %** (`lvs -o lv_name,data_percent`) — un pool saturé met en erreur d'écriture toutes les VMs à la fois.
- [x] **Inventaire CPU vérifié** : 16 cœurs / 32 threads, aucun cœur désactivé au BIOS, aucun bridage noyau, `x86-64-v3` et `sse4_2` confirmés (§2).
- [x] Vérifier que le template **`rocky-linux-10-template` (vm_id 9002)** existe — présent sur le nœud `pve`.
- [ ] **Figer le plan de `vmid` des 12 VMs** : les identifiants **101 et 201 sont déjà pris** (`ubuntu-web-01`, `rocky9-app-01`) — vérifier l'absence de collision avant le premier `apply`.
- [ ] Créer le token API Proxmox restreint (rôle dédié, pas `root@pam`).
- [ ] Figer le plan d'adressage §3.2 et **réserver la plage `192.168.1.200-230` dans le DHCP du routeur**.
- [ ] Activer **KSM** sur l'hôte, régler le ballooning selon §2.3.

### Phase 1 — IaC & socle
- [x] **Étendre le module `proxmox-vm` avec `var.extra_disks`** (§4.5) — fait, également sur `proxmox-vm-template`, dans les trois stacks `proxmox-infra/vms/*` et dans la stack `proxmox-infra/templates` ; `tofu test` vert sur les modules et les stacks (les suites existantes passent inchangées : rétrocompatibilité). Reste à confirmer par un `tofu plan` réel contre Proxmox.
- [ ] Écrire les stacks `devsecops-homelab/vms/{core,data,platform,k8s}` sur le modèle de `proxmox-infra/vms` (§4.3), avec `disk_storage_id = "local-lvm"`.
- [ ] `tofu test` sur chaque stack (mock provider), puis `tofu apply` dans l'ordre `core` → `data` → `platform` → `k8s`.
- [ ] **Vérifier le second disque des workers** avant toute suite : `lsblk` doit montrer un disque de 100 Go **sans `FSTYPE` ni `MOUNTPOINT`**, et relever le lien exact sous `/dev/disk/by-id/` (§4.5).
- [ ] Rôles Ansible `common` + `harden` ; sysctl `rp_filter=0`, liaison des services sur `eth1` (§3.1).
- [ ] Déployer **CoreDNS** (zone `willbrid.lan`, vue interne/LAN, forward upstream) + **mini-serveur mail** (MX/A).
- [ ] Déployer **HAProxy** (frontends `:6443` et `:80/:443`, backends en `mode tcp`) — §8.3.

### Phase 2 — Identité & PKI
- [ ] Déployer LLDAP, arborescence, groupes.
- [ ] Compiler le **générateur CUID Go** + workflow d'onboarding + registre chiffré.
- [ ] Générer la **Root CA offline**.
- [ ] Déployer OpenBao (Raft), Intermediate CA signée par la Root, auth LDAP, policies.
- [ ] Distribuer la Root dans les trust stores de toutes les VMs.

### Phase 3 — Socle de données (VM `data`)
- [ ] Déployer **OpenSearch + Dashboards** : nœud unique, heap 4 Go, `number_of_replicas: 0`, TLS OpenBao, plugin security adossé à LLDAP.
- [ ] Définir les **politiques ISM** et les patterns d'index (`logs-vm-*`, `logs-k8s-*`, `logs-audit-*`, `events-k8s-*`) — §11.4.
- [ ] Déployer **RustFS** (Quadlet, TLS OpenBao) ; créer les buckets `thanos`, `tempo`, `velero` et leurs identifiants dédiés dans OpenBao.
- [ ] Déployer l'**OTel Collector sur les 6 VMs hors cluster** (`journald` + `filelog` + `hostmetrics`) — il remplace Fluent Bit et node-exporter.

### Phase 4 — Kubernetes
- [ ] Préparer les nœuds (containerd, swap off, sysctl, SELinux, `--node-ip` interne).
- [ ] **Rôle Ansible `openebs_node` sur les 3 workers** — HugePages (`vm.nr_hugepages = 1024`), modules `nvme_tcp`/`ext4`/`xfs`, `nvme_core.multipath=Y`, ports 10124 et 8420/4421 sur la zone interne, **puis un reboot** ; contrôler `grep HugePages_Total /proc/meminfo` = 1024 (§8.8.1).
- [ ] Installer les **CRD Gateway API** (*standard channel*) — **avant** Cilium.
- [ ] `kubeadm init` sur cp-1 via `ClusterConfiguration` (`controlPlaneEndpoint` HAProxy, `advertiseAddress` interne, `certSANs`, OIDC, skip kube-proxy).
- [ ] Installer **Cilium** : `kubeProxyReplacement`, `devices=eth1`, `l7Proxy`, `gatewayAPI` en host network, Hubble.
- [ ] Joindre **cp-2, cp-3** puis **worker-1/2/3** (HA d'emblée).
- [ ] **Cilium Egress Gateway** : label `egress-node`, IP `192.168.1.230`, `excludedCIDRs` internes.
- [ ] cert-manager + `ClusterIssuer` OpenBao ; créer le `Gateway` `apps` et son certificat wildcard.
- [ ] **OpenEBS** (§8.8) : label `openebs.io/engine=mayastor` sur les workers ; chart avec `io_engine.coreList: [3]`, moteurs LVM/ZFS désactivés, etcd interne sur Local PV ; **3 `DiskPool`** référençant `aio:///dev/disk/by-id/…` (jamais `/dev/sdX`) avec `maxExpansion: "2x"` ; les 2 `StorageClass` `openebs-replicated` et `openebs-hostpath`, **aucune en classe par défaut**.
- [ ] Valider le stockage de bout en bout : `kubectl mayastor get pools` (3 pools `Online`), puis un PVC de test sur chaque `StorageClass`, et vérifier qu'un rebuild se déclenche et se termine après l'arrêt/redémarrage d'un worker.
- [ ] Dex (connecteur LDAP) + kubelogin ; RBAC mappé sur les groupes LDAP.
- [ ] OpenBao Secrets Operator.

### Phase 5 — Observabilité
- [ ] **OTel Operator**, puis les 3 collectors : agent (DaemonSet), cluster (**1 réplica strict**), gateway (2 réplicas).
- [ ] **Prometheus** avec `--web.enable-otlp-receiver`, rétention 24 h, blocs de 2 h, **PVC sur `openebs-hostpath`** (§8.8) ; Alertmanager → mail interne.
- [ ] Alertes stockage : pool OpenEBS > 80 %, volume `Degraded` > 15 min, `io-engine` non prêt, thin pool LVM > 75 % côté hôte.
- [ ] **Thanos** : sidecar, Store Gateway, Query, Compactor (downsampling) sur le bucket `thanos`.
- [ ] **Tempo** monolithique sur le bucket `tempo`.
- [ ] Export des logs vers **OpenSearch** (exporter `opensearch`, bascule Data Prepper si besoin).
- [ ] **Grafana** : 3 datasources + chaînes de corrélation trace↔logs↔métriques, SSO Dex, exposition via `HTTPRoute`.

### Phase 6 — Plateforme (VM `platform`)
- [ ] Podman + Quadlet ; réseaux/volumes.
- [ ] Déployer le **PostgreSQL unique** (2 bases, 2 users), lié à `eth1` uniquement.
- [ ] Déployer **GitLab CE** (Quadlet, `After=postgres`), auth LDAP, TLS OpenBao, Puma réduit, Prometheus embarqué désactivé.
- [ ] Traduire le compose **Harbor** en Quadlet, `external_database`, auth LDAP, TLS, Trivy, Cosign.
- [ ] Runners GitLab dans K8s.

### Phase 7 — GitOps & policies
- [ ] ArgoCD + SSO Dex + RBAC LDAP, exposé par `HTTPRoute`.
- [ ] Repos GitOps (bootstrap/platform/apps) + app-of-apps ; reprise en GitOps de tout ce qui a été posé en phases 4-5.
- [ ] Boucle CI/CD (build→Harbor→Trivy→Cosign→sync).
- [ ] Kyverno : images signées Harbor uniquement, pas de `latest`, non-root, contrôle des `HTTPRoute` autorisées.

### Phase 8 — Sauvegarde & résilience
- [ ] Proxmox Backup Server sur un **troisième support physique** — ni le HDD 4 To (qui porte toutes les VMs), ni le SSD système (§13). `data` en priorité 1.
- [ ] Velero → bucket `velero` ; dumps PostgreSQL ; snapshots Raft OpenBao ; snapshots OpenSearch **hors** VM `data`.
- [ ] Tester une **restauration** (c'est la seule façon de savoir si le plan fonctionne).
- [ ] Ajouter `haproxy-2` + keepalived si le SPOF de la §8.3 devient gênant.

### Phase 9 — IA (§16)
- [ ] **Détection d'anomalies OpenSearch** — premier gain, sans modèle ni passerelle.
- [ ] Socle : **Ollama** (CPU) sur un worker + **passerelle LLM** + journalisation vers `logs-audit-ai-*`.
- [ ] Namespace `ai` : `ResourceQuota` + `CiliumNetworkPolicy` fermée par défaut, secrets dans OpenBao.
- [ ] Cas d'usage dans l'ordre du §16.9 : triage d'alertes → RAG → revue de MR → priorisation Trivy.

---

## 16. IA appliquée au homelab — cas d'usage

Le lab produit déjà tout ce dont une IA a besoin pour être utile : des métriques corrélées, des logs centralisés, des traces, du code d'infrastructure versionné et une chaîne CI/CD. Les cas ci-dessous sont classés par **rapport valeur / effort**, et chacun s'appuie uniquement sur des briques déjà présentes.

**Socle minimal commun** — à poser une fois, avant le premier cas d'usage :
- un modèle local (**Ollama** sur un worker, modèle 7-8B quantifié, ~8 Go RAM — le budget du §2.1 le permet sans GPU) ;
- une **passerelle LLM** (type LiteLLM) exposant une API unique : une clé par consommateur (révocable individuellement), quotas, et journal des appels vers OpenSearch (index `logs-audit-ai-*`, 90 j) ;
- un namespace `ai` avec `ResourceQuota` et NetworkPolicy fermée par défaut.

Cela suffit pour les huit cas suivants. Le GPU passthrough n'est nécessaire pour aucun d'eux.

---

### 16.1 Triage et enrichissement automatique des alertes

**Le cas.** Une alerte Alertmanager arrive aujourd'hui avec un nom de règle et des labels. Un webhook la route vers un service qui rassemble le contexte déjà disponible — les métriques Thanos de la fenêtre, les logs OpenSearch du pod concerné, la trace Tempo de la requête en erreur — et renvoie dans la notification un pré-diagnostic avec les 3 hypothèses les plus probables.

**Ce qui le rend faisable ici** : la corrélation du §11.6. Sans les attributs communs posés par `k8sattributes`, il faudrait deviner quels logs correspondent à quelle alerte.

**Valeur marché** : c'est le cœur de l'**AIOps**, et le sujet le plus demandé sur les postes SRE / Platform Engineer aujourd'hui. Savoir dire « j'ai réduit le temps de qualification d'une alerte en corrélant automatiquement les trois signaux » est un argument d'entretien concret.

---

### 16.2 Détection d'anomalies sur les logs et les métriques

**Le cas.** Plugin *Anomaly Detection* d'OpenSearch : détecteurs sur le volume de logs par service, le taux d'erreurs HTTP, les échecs d'authentification LDAP, les accès OpenBao. Les anomalies détectées deviennent des alertes comme les autres.

**Pourquoi commencer par là** : c'est du machine learning classique, **sans LLM, sans GPU, sans passerelle**. C'est le cas d'usage le plus rapide à mettre en production et le plus déterministe — donc le plus facile à défendre.

**Valeur marché** : montre qu'on sait distinguer « là où un modèle statistique suffit » de « là où un LLM est nécessaire ». C'est précisément le discernement que les recruteurs cherchent derrière le mot-clé « IA ».

---

### 16.3 Priorisation des vulnérabilités Trivy selon l'exposition réelle

**Le cas.** Harbor scanne et renvoie 200 CVE, dont 40 « critiques ». La question utile n'est pas leur score CVSS mais : *ce composant est-il réellement exposé ?* Un job de CI croise le rapport Trivy avec le contexte du cluster — le service est-il attaché à une `HTTPRoute` (§8.4) ? tourne-t-il en root ? sa `CiliumNetworkPolicy` autorise-t-elle du trafic entrant ? le paquet vulnérable est-il seulement chargé ? — et produit une liste de 5 CVE à traiter en premier, justifiée.

**Garde-fou** : ça ne remplace pas la policy Kyverno, qui reste binaire (image signée ou refusée). C'est une aide à la **hiérarchisation**, pas à la décision.

**Valeur marché** : la « fatigue CVE » est un problème universel et non résolu. C'est le cas d'usage DevSecOps le plus différenciant de cette liste.

---

### 16.4 Revue de merge request assistée

**Le cas.** À chaque MR, un job GitLab CI envoie le diff à la passerelle et poste un commentaire : incohérences, cas limites non traités, écarts aux conventions du dépôt. Particulièrement rentable sur le **code d'infrastructure** — un `tofu plan` qui détruit une ressource, une NetworkPolicy trop large, un secret en clair, un `latest` dans un manifeste.

**Garde-fou, non négociable** : le compte de service IA est **en lecture seule** sur GitLab. Il commente, il n'approuve jamais et ne pousse jamais. L'IA propose, la CI décide.

**Valeur marché** : « shift-left » concret et mesurable. Facile à démontrer en entretien avec une capture de MR.

---

### 16.5 Assistant RAG sur la documentation et le code du lab

**Le cas.** Indexer ce README, le code OpenTofu, les rôles Ansible, les manifestes GitOps et les post-mortems dans un index **k-NN d'OpenSearch** — le moteur vectoriel est déjà là, aucun Qdrant ni Weaviate à ajouter. Les embeddings sont générés par Ollama, la réindexation est un job CI déclenché à chaque merge.

Questions typiques : « pourquoi le trafic etcd passe-t-il par `eth1` ? », « qu'est-ce qui casse si j'éteins deux masters ? », « quelle policy bloque cette image ? » — avec les extraits de code en référence.

**Ce qui le rend crédible** : la base de connaissances **suit le code** au lieu de dériver, parce que son alimentation est dans la CI.

**Valeur marché** : le RAG est le cas d'usage IA d'entreprise le plus répandu. En construire un sur sa propre infrastructure, avec un moteur déjà en place, démontre la compétence sans le vernis de démo.

---

### 16.6 Génération de NetworkPolicies à partir des flux observés

**Le cas.** Hubble observe en continu les flux réels du cluster. Un job périodique exporte les flux d'un namespace sur 7 jours et génère la `CiliumNetworkPolicy` la plus restrictive qui les autorise — proposée en MR sur le dépôt GitOps, jamais appliquée automatiquement.

**Pourquoi c'est pertinent** : le micro-segmentation échoue presque toujours pour la même raison — écrire les policies à la main est fastidieux et on ne sait jamais ce qu'on va casser. Partir de l'observé renverse le problème.

**Valeur marché** : sécurité réseau Kubernetes + eBPF + Zero Trust. Combinaison rare et très recherchée.

---

### 16.7 Post-mortem et runbook générés

**Le cas.** À la clôture d'un incident, agréger la fenêtre temporelle (alertes, métriques, logs, traces, déploiements ArgoCD de la période) en un brouillon de post-mortem : chronologie, impact, cause probable, actions. Le brouillon est relu, corrigé, puis **réinjecté dans l'index RAG du §16.5**.

**La boucle vertueuse** : chaque incident documenté améliore l'assistant, qui aide à résoudre le suivant.

**Valeur marché** : la culture post-mortem est un marqueur de maturité SRE. L'automatiser tout en gardant la relecture humaine montre qu'on a compris où placer la limite.

---

### 16.8 Requêtes en langage naturel sur l'observabilité

**Le cas.** Traduire « quels pods ont redémarré plus de 3 fois cette semaine ? » en PromQL, ou « montre-moi les erreurs 5xx de la gateway hier soir » en requête OpenSearch. Intégrable dans Grafana ou dans un bot sur le serveur mail interne.

**Valeur marché** : le moins différenciant de la liste, mais le plus démonstratif — c'est celui qui se montre en dix secondes.

---

### 16.9 Ordre de mise en œuvre suggéré

| Ordre | Cas | Pourquoi à ce moment |
|---|---|---|
| 1 | **§16.2** Détection d'anomalies | Aucun prérequis IA : ni modèle, ni passerelle. Gain immédiat |
| 2 | Socle : Ollama + passerelle + journalisation | Le point de contrôle **avant** le premier appel LLM |
| 3 | **§16.1** Triage d'alertes | Valide la corrélation des trois signaux de bout en bout |
| 4 | **§16.5** RAG | Alimente tous les cas suivants en contexte |
| 5 | **§16.4** Revue de MR | Première intégration dans la CI, à faible risque |
| 6 | **§16.3** Priorisation Trivy | Le plus différenciant, mais demande les cas 4 et 5 en place |
| 7 | **§16.6** / **§16.7** | Une fois que le lab a produit assez de flux et d'incidents réels |

> **Trois règles qui traversent tous ces cas** : (1) l'IA **propose**, la CI ou l'humain **décide** — aucun droit d'écriture sur Git, Harbor ou le cluster ; (2) tous les appels passent par la passerelle et sont journalisés dans OpenSearch avec 90 jours de rétention ; (3) le namespace `ai` n'a **aucun** accès sortant par défaut — chaque destination est explicitement autorisée par `CiliumNetworkPolicy`.

---

## 17. Points de vigilance & risques

| Risque | Mitigation |
|---|---|
| Harbor sous Quadlet + PG externe | Traduction compose→Quadlet testée ; `external_database` dans harbor.yml ; compose Podman en secours |
| VM `platform` 16 Go serrée | Runners hors VM ; Puma réduit ; surveiller la RAM ; upgrade 24 Go planifié (§2.4) |
| PostgreSQL unique = SPOF des 2 apps | Sauvegardes fréquentes ; isolation des droits par base ; surveiller les perfs |
| **VM `haproxy` = SPOF d'accès au lab** | VM sans état, reconstruite par `tofu apply` + Ansible ; `haproxy-2` + keepalived en phase 8 (§8.3) |
| **VM `data` = logs + objet + sauvegardes** | Priorité 1 du plan PBS ; snapshots OpenSearch écrits **hors** de son propre RustFS (§2.5, §13) |
| **Perte de quorum etcd** | Ne jamais éteindre plus d'**un** control-plane — le piège de l'extinction sélective (§2.2) |
| **HDD 4 To = SPOF de tout le lab** | Toutes les VMs, les 3 pools Mayastor et le bucket `velero` partagent un seul disque physique. `repl: 2` protège du nœud perdu, **pas** du disque perdu : la seule vraie mitigation est un **datastore PBS sur un troisième support** (§13) |
| **Thin pool `local-lvm` saturé** | Incident le plus brutal possible : erreurs d'écriture sur **toutes** les VMs simultanément. Alerte à 75 %, `discard=on` déjà actif, surveiller `data_percent` **et** `metadata_percent` (§2.6) |
| **HugePages absentes → `io-engine` en `Pending`** | Symptôme muet et coûteux à diagnostiquer. Poser le rôle `openebs_node` **avant** tout déploiement, rebooter, et contrôler `HugePages_Total = 1024` (§8.8.1) |
| **`DiskPool` pointé sur `/dev/sdX`** | Un renommage au reboot ferait écraser un autre disque — Mayastor détruit toute donnée préexistante. **Toujours `/dev/disk/by-id/`**, adossé au `serial` défini dans OpenTofu (§4.5, §8.8.3) |
| **1 thread par worker consommé à 100 %** | Poll mode SPDK : 3 threads immobilisés en permanence sur 32, adossés à 16 cœurs physiques — jusqu'à 19 % de la machine. `io_engine.coreList` limité à un seul cœur ; deux réacteurs ne doivent pas partager un cœur physique (threads `N`/`N+16`) ; mode interruption à surveiller en amont (§2.7) |
| **CPU = ressource rare, pas la RAM** | 29 vCPU sur 32 threads (90 %) contre 86 Go sur 128 (67 %). Toute extension s'arbitre en vCPU d'abord ; il ne reste que 3 threads, et ils sont la réserve de l'hyperviseur (§2.1, §2.4) |
| **Mayastor sur backend HDD** | Chemin de données conçu pour du NVMe. Mitigé par `aio://`, `repl: 2` (pas 3), et surtout par le renvoi de l'état chaud vers `openebs-hostpath` (§8.8) |
| **Ajout d'un disque à une VM clonée** | Chemin peu éprouvé du provider `bpg/proxmox` : valider par `tofu test` puis `tofu plan` réel avant d'appliquer aux 3 workers (§4.5) |
| **Rocky 10 hors matrice OpenEBS** | La documentation valide Ubuntu et RHEL 8.8. Rocky 10 satisfait tous les prérequis techniques (noyau, SSE4.2, `nvme-tcp`) mais reste à valider en pratique — c'est le premier test de la phase 4 |
| CoreDNS `dns` = SPOF PKI/exposition | Résolveur secondaire ou restore rapide ; snapshot VM |
| Mail sortant externe non fiable | Réserver au trafic interne ; relais tiers si envoi externe |
| OpenSearch JVM gourmande | Heap 4 Go, swap off, `memory_lock`, ISM sur tous les index |
| **Doublons de métriques OTel** | `k8s_cluster` et `k8sobjects` en **1 seul réplica** : sinon compteurs faussés en silence (§11.2) |
| **Exporter `opensearch` en alpha** | Valider sur volume réel ; bascule vers Data Prepper prévue (§11.4) |
| **RustFS : mode distribué en test** | Mono-nœud uniquement ; la résilience vient des snapshots PBS, pas de l'erasure coding |
| **Routage asymétrique (2 NIC)** | Une seule passerelle, `rp_filter=0`, `--node-ip` épinglé, `excludedCIDRs` sur l'egress (§3.3, §8.6) |
| Egress via un seul nœud Cilium | Label `egress-node` déplaçable ; à vérifier avant d'éteindre un worker |
| Bootstrap poule/œuf (état/secrets) | État local chiffré ; migration vers GitLab/OpenBao ensuite |
| Root CA compromise | Root strictement offline, clé chiffrée |
| **Dérive des usages IA** | Namespace `ai` sans egress par défaut, comptes de service en lecture seule, appels journalisés 90 j (§16.9) |

---

## 18. Annexe — Récapitulatif des choix technologiques

| Couche | Technologie |
|---|---|
| Hyperviseur | Proxmox VE 9.1.1 — 2 × Xeon E5-2640 v3, **16 cœurs / 32 threads**, 128 Go, 2 nœuds NUMA — **29 vCPU / 86 Go alloués** |
| Stockage hôte | **SSD 1 To** : Proxmox + stockage `local` (ISO, template, snippets) — **HDD 4 To** : `local-lvm`, tous les disques de VM (~1,53 To provisionné) |
| OS VMs | Rocky Linux 10 (template `9002` de `proxmox-infra/templates`) |
| Poste admin | Ubuntu 24.04 (OpenTofu + Ansible) |
| Domaine interne | `willbrid.lan` |
| Réseau | **2 NIC** : `vmbr0` LAN `192.168.1.0/24` (route par défaut) + `vmbr1` interne `172.16.1.0/24` (isolé) |
| DNS interne | **CoreDNS autonome** (VM `dns`) |
| Mail interne | Mini-serveur mail conteneurisé (VM `dns`) |
| IaC | OpenTofu (`bpg/proxmox`) + Ansible — stacks `devsecops-homelab/vms/{core,data,platform,k8s}` |
| Annuaire | LLDAP, `uid` = **CUID v2** (script Go) |
| Secrets / PKI | OpenBao (Raft + Intermediate CA) |
| Root CA | offline (bastion) |
| Conteneurs plateforme | Podman + Quadlet |
| SCM / CI | GitLab CE |
| Registry | Harbor + Trivy + Cosign |
| Base de données | **PostgreSQL unique** (2 bases : gitlab, harbor) |
| Orchestration | Kubernetes (kubeadm) — **3 CP + 3 workers dès le départ** |
| CNI | Cilium (eBPF, sans kube-proxy, Hubble) |
| Entrée du lab | **VM HAProxy dédiée** (`192.168.1.200`, L4 passthrough) — keepalived reporté |
| Exposition des applications | **Gateway API** (`gateway.networking.k8s.io/v1`) via **Cilium**, host network mode |
| Sortie cluster | **Cilium Egress Gateway** — IP unique `192.168.1.230` |
| Stockage bloc K8s | **OpenEBS** — Replicated PV **Mayastor** (`repl: 2`, NVMe-oF/TCP sur `eth1`, 1 `DiskPool` de 100 Go par worker) + **Local PV hostpath** pour l'état chaud |
| Stockage objet | **RustFS** (Apache 2.0, S3) — buckets `thanos`, `tempo`, `velero` |
| Certificats K8s | cert-manager (`ClusterIssuer` OpenBao) |
| Authn users K8s | Dex (OIDC) ↔ LLDAP + kubelogin |
| GitOps | ArgoCD (SSO Dex) |
| Policies | Kyverno |
| Collecte d'observabilité | **OpenTelemetry Collector** — agent DaemonSet, instance cluster, gateway, agent VM |
| Métriques | **Prometheus** (OTLP natif, 24 h) + **Thanos** (long terme sur objet) |
| Logs | **OpenSearch** + Dashboards — VMs et applications K8s, backend unique |
| Traces | **Tempo** (monolithique, backend objet) |
| Visualisation | **Grafana** — Thanos, Tempo, OpenSearch + corrélation trace↔logs↔métriques |
| Sauvegarde | Proxmox Backup Server, Velero |
| IA | Ollama local + passerelle LLM ; cas d'usage AIOps, CI/CD et RAG (§16) |
