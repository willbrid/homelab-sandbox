# homelab-sandbox

Ce repository documente mon environnement de lab personnel basé sur **Proxmox VE 9.1**. Il inclut la configuration des VM, des containers et de l’infrastructure réseau.

```
git clone https://github.com/willbrid/homelab-sandbox.git
```

> **Note**: La mise en place de notre infrastructure sur Proxmox est entièrement automatisée grâce à `OpenTofu`.

### Configuration des templates

Grâce à nos modules, nous déployons automatiquement nos templates Proxmox pour les systèmes **Ubuntu 24.04**, **Rocky Linux 9.7** et **Rocky Linux 10**.

- Créer une interface réseau **vmbr1** sur proxmox

--- Se connecter sur le noeud Proxmox via SSH (root)

```
vesh create /nodes/pve/network \
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
proxmox_url      = "https://@IP:8006"
proxmox_username = "xxx
proxmox_password = "xxx"
ssh_public_key   = "xxx"
```

--- **proxmox_url**      : url web de proxmox <br>
--- **proxmox_username** : identifiant d'accès <br>
--- **proxmox_password** : mot de passe d'accès <br>
--- **ssh_public_key**   : emplacement local du fichier clé public généré

- Exécuter les commandes **tofu** pour créer nos templates

```
tofu init
tofu plan
tofu apply
```