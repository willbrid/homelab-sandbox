#!/bin/bash

IMAGE_DIR="/tmp"
mkdir -p $IMAGE_DIR

# Ubuntu 24.04 (Noble) cloud image
wget -O $IMAGE_DIR/ubuntu-24.04-cloud.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Rocky Linux 9 cloud image
wget -O $IMAGE_DIR/rocky-9-cloud.img \
  https://dl.rockylinux.org/pub/rocky/9.7/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2

# Rocky Linux 10 cloud image
wget -O $IMAGE_DIR/rocky-10-cloud.img \
  https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2

echo "Images téléchargées dans $IMAGE_DIR"