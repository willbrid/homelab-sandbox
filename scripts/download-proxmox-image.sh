#!/bin/bash
# Usage: ./download-proxmox-image.sh <IMAGE_URL> [--no-agent] [--disable-selinux]
#
# Ubuntu 24.04   : https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
# Rocky linux 9  : https://dl.rockylinux.org/pub/rocky/9.8/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
# Rocky linux 10 : https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
#
# Par défaut     : installe qemu-guest-agent, passe SELinux en permissive et relabel.
# --no-agent     : télécharge uniquement (Ubuntu, qui installe l'agent via cloud-init).
# --disable-selinux : désactive complètement SELinux dans l'image (SELINUX=disabled).
#                    Par défaut : permissive (SELINUX=permissive).

set -euo pipefail

IMAGE_URL="${1:?Usage: $0 <IMAGE_URL> [--no-agent] [--disable-selinux]}"
shift

INSTALL_AGENT=true
DISABLE_SELINUX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-agent)        INSTALL_AGENT=false ;;
    --disable-selinux) DISABLE_SELINUX=true ;;
    *) echo "Option inconnue : $1"; exit 1 ;;
  esac
  shift
done

IMAGE_DIR="/var/lib/vz/template/iso"
ORIGINAL_FILENAME=$(basename "${IMAGE_URL%%\?*}" | sed 's/%[0-9A-Fa-f]\{2\}/./g')
BASE_NAME="${ORIGINAL_FILENAME%.*}"
WORK_FILE="/tmp/${ORIGINAL_FILENAME}"
ISO_TARGET="${IMAGE_DIR}/${BASE_NAME}-agent.img"

# --- Vérification : libguestfs-tools ---
if $INSTALL_AGENT && ! command -v virt-customize &>/dev/null; then
  echo "==> libguestfs-tools absent — installation en cours..."
  apt-get update && apt-get install -y libguestfs-tools
fi

mkdir -p "$IMAGE_DIR"

# --- Téléchargement (ignoré si l'image est déjà présente) ---
if [[ -f "$ISO_TARGET" ]]; then
  echo "==> Image déjà présente : $ISO_TARGET (téléchargement ignoré)"
  WORK_FILE="$ISO_TARGET"
else
  echo "==> Téléchargement : $IMAGE_URL"
  wget -q --show-progress -O "$WORK_FILE" "$IMAGE_URL"
fi

# --- Personnalisation (RHEL/Rocky uniquement) ---
if $INSTALL_AGENT; then
  if $DISABLE_SELINUX; then
    SELINUX_MODE="disabled"
    SELINUX_CMD='sed -i "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config || true'
  else
    SELINUX_MODE="permissive"
    SELINUX_CMD='sed -i "s/^SELINUX=enforcing/SELINUX=permissive/" /etc/selinux/config || true'
  fi

  echo "==> Personnalisation de l'image (SELinux → ${SELINUX_MODE})..."
  VIRT_CUSTOMIZE_ARGS=(
    -a "$WORK_FILE"
    --install qemu-guest-agent
    --run-command 'systemctl enable qemu-guest-agent.service'
    --run-command "$SELINUX_CMD"
  )
  # virt-customize relabel automatiquement tout système SELinux détecté.
  # --no-selinux-relabel est nécessaire pour l'inhiber quand SELinux est désactivé.
  $DISABLE_SELINUX && VIRT_CUSTOMIZE_ARGS+=(--no-selinux-relabel)

  virt-customize "${VIRT_CUSTOMIZE_ARGS[@]}"
fi

# --- Dépôt dans le stockage ISO Proxmox ---
if [[ "$WORK_FILE" != "$ISO_TARGET" ]]; then
  echo "==> Copie vers $ISO_TARGET"
  cp "$WORK_FILE" "$ISO_TARGET"
  rm -f "$WORK_FILE"
fi

echo ""
echo "============================================"
echo " Image prête    : $ISO_TARGET"
echo " Référence Tofu : local:iso/${BASE_NAME}-agent.img"
echo "============================================"
