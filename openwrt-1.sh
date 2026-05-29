#!/usr/bin/env bash
# =========================================================
# OpenWRT VM Installer for Proxmox VE 8 / 9
# Fixed & Updated Edition
# Based on community-scripts + custom fixes
# =========================================================
set -Eeo pipefail
source /dev/stdin <<< $(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)
# =========================================================
# UI
# =========================================================
function header_info() {
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
echo -e "加载中..."
# =========================================================
# VARIABLES
# =========================================================
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
NEXTID=$(pvesh get /cluster/nextid)
GEN_MAC=02:$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/:$//' | tr 'a-f' 'A-F')
GEN_MAC_LAN=02:$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/:$//' | tr 'a-f' 'A-F')
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" >/dev/null
# =========================================================
# CLEANUP
# =========================================================
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
function cleanup() {
  popd >/dev/null || true
  rm -rf "$TEMP_DIR"
}
function cleanup_vmid() {
  if qm status "$VMID" &>/dev/null; then
    qm stop "$VMID" &>/dev/null || true
    qm destroy "$VMID" &>/dev/null || true
  fi
}
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  echo -e "\n${RD}[ERROR]${CL} line ${line_number}"
  echo -e "Command: ${YW}${command}${CL}"
  echo -e "Exit Code: ${exit_code}\n"
  cleanup_vmid
}
# =========================================================
# LOG FUNCTIONS
# =========================================================
function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}
function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}
function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}
# =========================================================
# CHECKS
# =========================================================
function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/(8|9)\."; then
    msg_error "PVE 版本不支持"
    echo -e "需要 PVE 8.1+"
    exit 1
  fi
}
function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n${CROSS} 不支持 PiMox / ARM 平台\n"
    exit 1
  fi
}
function ssh_check() {
  if [ -n "${SSH_CLIENT:+x}" ]; then
    if whiptail --defaultno \
      --title "SSH 警告" \
      --yesno "建议在 PVE Web Shell 中运行。\n继续?" \
      10 60; then
      :
    else
      exit
    fi
  fi
}
# =========================================================
# DEFAULT SETTINGS
# =========================================================
function default_settings() {
  VMID=$NEXTID
  HN="OpenWRT"
  CORE_COUNT="1"
  RAM_SIZE="1024"
  BRG="vmbr0"
  LAN_BRG="vmbr0"
  VLAN=""
  LAN_VLAN=",tag=999"
  MAC=$GEN_MAC
  LAN_MAC=$GEN_MAC_LAN
  LAN_IP_ADDR="192.168.1.1"
  LAN_NETMASK="255.255.255.0"
  MTU=""
  START_VM="yes"
  echo -e "${DGN}VMID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}CPU: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}RAM: ${BGN}${RAM_SIZE}${CL}"
}
# =========================================================
# START MENU
# =========================================================
if (whiptail --title "OpenWRT 虚拟机" \
  --yesno "开始创建 OpenWRT VM ?" 10 58); then
  :
else
  exit
fi
arch_check
pve_check
ssh_check
default_settings
# =========================================================
# STORAGE
# =========================================================
msg_info "检查存储"
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{print $2}')
  FREE=$(echo "$line" \
    | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f \
    | awk '{printf( "%9sB", $6)}')
  ITEM="Type: $TYPE Free: $FREE"
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "没有可用存储"
  exit 1
fi
if [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  STORAGE=$(whiptail \
    --title "存储池" \
    --radiolist "选择存储池" \
    16 78 6 \
    "${STORAGE_MENU[@]}" \
    3>&1 1>&2 2>&3)
fi
msg_ok "使用存储: $STORAGE"
# =========================================================
# DOWNLOAD IMAGE
# =========================================================
msg_info "下载 OpenWRT 镜像"
URL="https://dl.ikoolcore.com/dl/OpenWrt%20Firmware/R2Max/QWRT-R26.03.23-x86-64-generic-squashfs-combined-efi.img.gz"
wget -q --show-progress "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename "$URL")
msg_ok "下载完成: $FILE"
gunzip -f "$FILE"
FILE="${FILE%.gz}"
RAW_IMAGE="${FILE%.img}.img"
mv "$FILE" "$RAW_IMAGE"
qemu-img resize -f raw "$RAW_IMAGE" 2048M >/dev/null
msg_ok "镜像已扩容"
# =========================================================
# STORAGE TYPE
# =========================================================
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs|dir)
    DISK_EXT=".qcow2"
    DISK_IMPORT="-format qcow2"
    ;;
  *)
    DISK_EXT=""
    DISK_IMPORT=""
    ;;
esac
# =========================================================
# CREATE VM
# =========================================================
msg_info "创建 OpenWRT VM"
qm create "$VMID" \
  -name "$HN" \
  -machine q35 \
  -cores "$CORE_COUNT" \
  -memory "$RAM_SIZE" \
  -cpu host \
  -ostype l26 \
  -bios ovmf \
  -scsihw virtio-scsi-pci \
  -agent enabled=1 \
  -onboot 1 \
  --tablet 0
msg_ok "VM 已创建"
# =========================================================
# EFI DISK
# =========================================================
msg_info "创建 EFI 磁盘"
qm set "$VMID" \
  -efidisk0 "${STORAGE}:4,efitype=4m,pre-enrolled-keys=1"
msg_ok "EFI 磁盘创建完成"
# =========================================================
# IMPORT DISK
# =========================================================
msg_info "导入 OpenWRT 磁盘"
qm importdisk "$VMID" "$RAW_IMAGE" "$STORAGE" ${DISK_IMPORT}
msg_ok "磁盘导入完成"
# =========================================================
# ATTACH DISK
# =========================================================
IMPORTED_DISK=$(qm config "$VMID" \
  | grep unused0 \
  | awk '{print $2}' \
  | sed 's/,.*//')
msg_info "挂载系统磁盘"
qm set "$VMID" \
  -scsi0 "$IMPORTED_DISK" \
  -boot order=scsi0
msg_ok "系统磁盘挂载完成"
# =========================================================
# NETWORK
# =========================================================
msg_info "配置网卡"
qm set "$VMID" \
  -net0 virtio,bridge=${LAN_BRG},macaddr=${LAN_MAC}${LAN_VLAN}${MTU} \
  -net1 virtio,bridge=${BRG},macaddr=${MAC}${VLAN}${MTU}
msg_ok "网卡配置完成"
# =========================================================
# START VM
# =========================================================
if [ "$START_VM" == "yes" ]; then
  msg_info "启动虚拟机"
  qm start "$VMID"
  msg_ok "OpenWRT 已启动"
fi
# =========================================================
# FINAL INFO
# =========================================================
echo
echo -e "${GN}=================================================${CL}"
echo -e "${GN} OpenWRT VM 创建完成${CL}"
echo -e "${GN}=================================================${CL}"
echo
echo -e "${BL}VMID:${CL} ${VMID}"
echo -e "${BL}LAN IP:${CL} ${LAN_IP_ADDR}"
echo -e "${BL}默认管理地址:${CL} http://${LAN_IP_ADDR}"
echo
