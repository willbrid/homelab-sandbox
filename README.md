# homelab-sandbox

Ce repository documente mon environnement de lab personnel basé sur **Proxmox VE 9.1**. Il inclut la configuration des VM, des containers et de l’infrastructure réseau.

```
git clone https://github.com/willbrid/homelab-sandbox.git
```

> **Note**: La mise en place de notre infrastructure sur Proxmox est entièrement automatisée grâce à `OpenTofu`.

### Construction des images cloud

Le script `scripts/download-proxmox-image.sh` télécharge une image cloud officielle, l'adapte puis la dépose dans le stockage ISO de Proxmox (`/var/lib/vz/template/iso`). C'est un **prérequis** au déploiement des templates : le module `proxmox-vm-template` référence l'image via `local:iso/<nom>` et échoue si le fichier n'existe pas — il ne la télécharge pas lui-même.

- Pourquoi ne pas utiliser l'image cloud telle quelle

--- Les images **GenericCloud** de Rocky Linux n'embarquent pas `qemu-guest-agent`. Or l'agent est indispensable à toute la chaîne : OpenTofu attend sa réponse pour considérer la VM comme démarrée, remonte les IP via lui (`ipv4_addresses`), et l'**extinction gracieuse** d'une VM en dépend — sans agent, le provider procède à un arrêt brutal.

--- Installer l'agent au premier boot via cloud-init supposerait un dépôt de paquets joignable à chaque création de VM et rallongerait le boot. L'injecter **une seule fois dans l'image** avec `virt-customize` rend le template autonome et le temps de démarrage prévisible.

--- `virt-customize` modifie l'image hors ligne : sur Rocky/RHEL, SELinux en `enforcing` déclencherait alors un relabel complet du système de fichiers au premier boot (plusieurs minutes + redémarrage), au risque de dépasser les timeouts du provider. Le script bascule donc SELinux en `permissive` et laisse `virt-customize` relabeler l'image à froid.

- Exécuter le script sur le nœud Proxmox (en `root`)

```
scp scripts/download-proxmox-image.sh root@<IP-PROXMOX>:/root/
ssh root@<IP-PROXMOX>
chmod +x /root/download-proxmox-image.sh
```

> NB: `libguestfs-tools` est installé automatiquement par le script s'il est absent.

- Construire les trois images

--- Ubuntu 24.04 — l'image cloud installe déjà l'agent, `--no-agent` se contente donc du téléchargement

```
./download-proxmox-image.sh https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img --no-agent
```

--- Rocky Linux 9

```
./download-proxmox-image.sh https://dl.rockylinux.org/pub/rocky/9.8/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
```

--- Rocky Linux 10

```
./download-proxmox-image.sh https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
```

Le script affiche en fin d'exécution le chemin produit et sa référence Tofu :

```
============================================
 Image prête    : /var/lib/vz/template/iso/Rocky-10-GenericCloud-Base.latest.x86_64-agent.img
 Référence Tofu : local:iso/Rocky-10-GenericCloud-Base.latest.x86_64-agent.img
============================================
```

Le suffixe `-agent.img` est systématique et correspond aux `image_filename` déclarés dans `proxmox-infra/templates/main.tf`.

- Option `--disable-selinux` : désactive complètement SELinux dans l'image (`SELINUX=disabled`) au lieu de le passer en `permissive`. À réserver aux cas où le relabel pose problème — `permissive` conserve la journalisation des refus.

> NB: Si l'image cible existe déjà dans le stockage ISO, le téléchargement est ignoré et la personnalisation est réappliquée sur place. Pour repartir d'une image neuve, supprimer d'abord le fichier `-agent.img` correspondant.

### Configuration des templates

Grâce à nos modules, nous déployons automatiquement nos templates Proxmox pour les systèmes **Ubuntu 24.04**, **Rocky Linux 9.8** et **Rocky Linux 10**.

- Créer une interface réseau **vmbr1** sur proxmox

--- Se connecter sur le noeud Proxmox via SSH (root)

```
pvesh create /nodes/pve/network \
  --iface vmbr1 \
  --type bridge \
  --autostart 1 \
  --comments "Internal bridge for secondary NICs"
```

--- Appliquer la configuration réseau

```
pvesh set /nodes/pve/network
```

> NB: Sautez cette étape si cette interface est déjà créée.

- Générer notre clé publique afin de l’intégrer à nos templates

```
ssh-keygen -t ed25519 -C "tofu-proxmox" -f ~/.ssh/id_ed25519_proxmox-server
```

> NB: Ne renseignez pas de mot de passe pendant la génération de la clé avec `ssh-keygen` : appuyez sur **Entrée** pour ignorer cette étape.

- Définir son fichier **templates.auto.tfvars** contenant les variables

```
cd promox-infra/templates
```

```
vi templates.auto.tfvars
```

```
proxmox_url         = "https://@IP:8006"
proxmox_username    = "xxx
proxmox_password    = "xxx"
cloud_init_ssh_keys = ["xxx"]
```

--- **proxmox_url**            : url web de proxmox <br>
--- **proxmox_username**       : identifiant d'accès <br>
--- **proxmox_password**       : mot de passe d'accès <br>
--- **cloud_init_ssh_keys**[i] : contenu du fichier clé public généré

- Exécuter les commandes **tofu** pour créer nos templates

```
tofu init
tofu plan
tofu apply
```

### Éteindre une VM sans la détruire

Les stacks du répertoire `proxmox-infra/vms` permettent d'éteindre une VM tout en conservant ses disques, sa configuration et son cloud-init.

- Extinction ponctuelle, sans modifier `terraform.tfvars`

```
tofu apply -var='stopped_vms=["rocky10-app-01"]'
```

- Extinction durable : positionner `started = false` sur la VM concernée dans `terraform.tfvars`

```
vms = {
  "rocky10-app-01" = {
    vm_id   = 301
    started = false
  }
}
```

Pour rallumer la VM : retirer son nom de `stopped_vms` (ou repasser `started = true`) puis réappliquer.

L'arrêt est **gracieux** : Proxmox demande d'abord à l'OS invité de s'arrêter proprement (ACPI + `qemu-guest-agent`) et ne force l'arrêt qu'au bout de `timeout_shutdown_vm` secondes (600 par défaut). Ce délai est surchargeable globalement ou par VM :

```
timeout_shutdown_vm = 600   # valeur par défaut de la stack

vms = {
  "rocky10-db-01" = {
    vm_id               = 303
    timeout_shutdown_vm = 900   # surcharge pour cette VM
  }
}
```

> NB: `stop_on_destroy` (`false` par défaut) applique la même logique d'arrêt gracieux avant un `tofu destroy`. Le passer à `true` accélère la destruction au prix d'un arrêt brutal.

> NB: `on_boot` reste indépendant de l'état d'alimentation. Une VM éteinte mais conservée à `on_boot = true` redémarrera au reboot du nœud Proxmox ; ajouter `on_boot = false` pour une extinction de longue durée.

### Quelques commandes utiles dans Proxmox

- Stopper une vm d'id `VMID`

```
qm stop $VMID
```

- Supprimer une vm d'id `VMID`

```
qm destroy $VMID --purge 1 --destroy-unreferenced-disks 1
```

- Supprimer un template d'id `TPLID`

```
qm destroy $TPLID --purge 1 --destroy-unreferenced-disks 1
```
