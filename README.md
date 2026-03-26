# homelab-sandbox

Ce repository documente mon environnement de lab personnel basé sur **Proxmox VE 9.1**. Il inclut la configuration des VM, des containers et de l’infrastructure réseau.

```
git clone https://github.com/willbrid/homelab-sandbox.git
```

### Configuration des templates

Grâce à nos modules, nous déployons automatiquement nos templates Proxmox pour les systèmes **Ubuntu 24.04**, **Rocky Linux 9.7** et **Rocky Linux 10**.

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
--- **proxmox_password** : mot de passe d'accès
