#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
#         Jon Spriggs (jontheniceguy)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Based on work from https://i12bretro.github.io/tutorials/0405.html

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
   ____                 _       __     __
  / __ \____  ___  ____| |     / /____/ /_
 / / / / __ \/ _ \/ __ \ | /| / / ___/ __/
/ /_/ / /_/ /  __/ / / / |/ |/ / /  / /_
\____/ .___/\___/_/ /_/|__/|__/_/   \__/
    /_/ W I R E L E S S   F R E E D O M

EOF
}
header_info
echo -e "\n Loading..."

RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="openwrt-vm"
var_os="openwrt"
var_version=" "
DISK_SIZE="1G"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
GEN_MAC_LAN=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

BFR="\\r\\033[K"
HOLD=" "

set -Eeo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  echo -e "\n${RD}[ERROR] line ${line_number}: ${command}${CL}"
  cleanup_vmid
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ✓ ${GN}$1${CL}"; }
function msg_error() { echo -e "${BFR} ✗ ${RD}$1${CL}"; }

# =========================
# PVE CHECK (保持原逻辑)
# =========================
function pve_check() {
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
  [[ "$PVE_VER" =~ ^(8|9)\. ]] || { msg_error "PVE not supported"; exit 1; }
}

function arch_check() {
  [ "$(dpkg --print-architecture)" = "amd64" ] || exit 1
}

function ssh_check() {
  [ -n "${SSH_CLIENT:+x}" ] && exit 0
}

function default_settings() {
  VMID=$(pvesh get /cluster/nextid)
  HN="openwrt"
  CORE_COUNT=1
  RAM_SIZE=256
  BRG="vmbr0"
  LAN_BRG="vmbr0"
  MAC=$GEN_MAC
  LAN_MAC=$GEN_MAC_LAN
  LAN_IP_ADDR="192.168.1.1"
  LAN_NETMASK="255.255.255.0"
  MTU=""
  START_VM="yes"
}

arch_check
pve_check
ssh_check
default_settings

# =========================
# STORAGE
# =========================
msg_info "Checking storage"

STORAGE=$(pvesm status -content images | awk 'NR>1 {print $1; exit}')
msg_ok "Using storage $STORAGE"

# =========================
# 🔥 FIXED IMAGE SOURCE
# =========================
msg_info "Downloading OpenWrt Image"

# ✅ 替换为稳定 ImmortalWrt EFI x86_64
URL="https://downloads.immortalwrt.org/releases/24.10.1/targets/x86/64/immortalwrt-24.10.1-x86-64-generic-ext4-combined-efi.img.gz"

FILE=$(basename "$URL")

curl -f#SL -o "$FILE" "$URL"

msg_ok "Downloaded $FILE"

gunzip -f "$FILE"

FILE="${FILE%.gz}"

msg_ok "Extracted image"

qemu-img resize -f raw "$FILE" 2G >/dev/null

# =========================
# CREATE VM
# =========================
msg_info "Creating VM"

qm create $VMID \
  -name "$HN" \
  -cores $CORE_COUNT \
  -memory $RAM_SIZE \
  -machine q35 \
  -bios ovmf \
  -cpu host \
  -onboot 1 \
  -ostype l26 \
  -scsihw virtio-scsi-pci \
  --tablet 0

msg_ok "VM created"

# EFI
qm set $VMID -efidisk0 ${STORAGE}:4,efitype=4m,pre-enrolled-keys=1

# IMPORT DISK
qm importdisk $VMID "$FILE" $STORAGE --format raw

DISK=$(qm config $VMID | awk -F': ' '/unused0/ {print $2}')

qm set $VMID \
  -scsi0 $DISK \
  -boot order=scsi0

# NETWORK
qm set $VMID \
  -net0 virtio,bridge=$LAN_BRG,macaddr=$LAN_MAC \
  -net1 virtio,bridge=$BRG,macaddr=$MAC

# START
[ "$START_VM" = "yes" ] && qm start $VMID

msg_ok "Done: OpenWrt VM Created"
