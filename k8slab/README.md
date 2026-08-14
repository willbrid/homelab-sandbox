# k8slab

Ce répertoire contient le **provisionnement des VMs** des clusters Kubernetes que je crée pour mes tests.

Il ne fait que fournir les machines : création des VMs à partir des templates Proxmox, réseau, disques. L'installation de Kubernetes elle-même se fait ensuite, sur les VMs ainsi obtenues.

Une stack par famille d'OS, sur le modèle de `proxmox-infra/vms` et en réutilisant le module `proxmox-infra/modules/proxmox-vm` :

| Stack | Contenu |
|---|---|
| `rocky-linux-10/` | Un control plane (`control1`) et trois workers (`worker1` à `worker3`), clonés du template Rocky Linux 10 |

Les workers reçoivent un **second disque vierge** (`extra_disks`, `scsi1`) destiné au stockage persistant du cluster : ni partitionné, ni formaté, ni monté par OpenTofu — c'est la charge hébergée qui en décide. L'output `vms` expose son chemin stable sous `/dev/disk/by-id/`, à utiliser plutôt que `/dev/sdX`.

## Prérequis

Les templates Proxmox doivent exister au préalable — voir `proxmox-infra/templates` et le script `scripts/download-proxmox-image.sh` à la racine du repository.

## Utilisation

```
cd k8slab/rocky-linux-10
cp terraform.tfvars.example terraform.tfvars   # puis adapter les valeurs
tofu init
tofu plan
tofu apply
```

> **Note** : `terraform.tfvars` contient des identifiants Proxmox et n'est pas versionné (`.gitignore`).
