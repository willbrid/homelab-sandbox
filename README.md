# homelab-sandbox

Ce repository documente mon environnement de lab personnel basé sur **Proxmox VE 9.1**. Il inclut la configuration des VM, des containers et de l’infrastructure réseau.

```
git clone https://github.com/willbrid/homelab-sandbox.git
```

> **Note**: La mise en place de notre infrastructure sur Proxmox est entièrement automatisée grâce à `OpenTofu`.

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
