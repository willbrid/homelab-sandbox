#!/bin/bash
# Ubuntu 24.04   : https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
# Rocky linux 9  : https://dl.rockylinux.org/pub/rocky/9.8/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
# Rocky linux 10 : https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
#

IMAGE_URL="${1:?Usage: $0 <IMAGE_URL> Exemple: $0 https://dl.rockylinux.org/.../Rocky-10-GenericCloud-Base.latest.x86_64.qcow2}"

IMAGE_DIR="/var/lib/vz/template/iso"
mkdir -p $IMAGE_DIR
ORIGINAL_FILENAME=$(basename "${IMAGE_URL%%\?*}" | sed 's/%[0-9A-Fa-f]\{2\}/./g')
BASE_NAME="${ORIGINAL_FILENAME%.*}"
ISO_TARGET="$IMAGE_DIR/${BASE_NAME}-agent.img"

# Download cloud image
wget -O $ISO_TARGET $IMAGE_URL

echo "Images téléchargées dans $IMAGE_DIR"