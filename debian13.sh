#!/usr/bin/env bash
# Debian 13 VM for Proxmox VE
source /dev/stdin <<< $(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)
function header_info {
  clear
  cat <<"EOF"
██████╗ ███████╗██████╗ ██╗ █████╗ ███╗   ██╗
██╔══██╗██╔════╝██╔══██╗██║██╔══██╗████╗  ██║
██║  ██║█████╗  ██████╔╝██║███████║██╔██╗ ██║
██║  ██║██╔══╝  ██╔══██╗██║██╔══██║██║╚██╗██║
██████╔╝███████╗██████╔╝██║██║  ██║██║ ╚████║
╚═════╝ ╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝
            Debian 13 Trixie VM
EOF
}
header_info
echo -e "\n 加载中..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="debian13vm"
var_os="debian"
var_version="13"
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "
CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${command}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}
function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}
function cleanup() {
  popd >/dev/null
  post_update_to_api "done" "none"
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "PVE 社区开源脚本" --title "Debian 13 VM" --yesno "这将会创建 Debian 13 虚拟机. 继续?" 10 58; then
  :
else
  header_info
  echo -e "${CROSS}${RD}用户退出脚本${CL}\n"
  exit
fi
function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}
function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}
function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}
function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "请使用root用户运行脚本."
    echo -e "\n自动退出中..."
    sleep 2
    exit
  fi
}
function pve_check() {
 if ! pveversion | grep -Eq "pve-manager/8\.[1-9](\.[0-9]+)*"; then
    msg_error "代码不支持这个版本的 PVE 环境"
    echo -e "需要在 PVE 8.1 及以上版本下运行."
    echo -e "自动退出中..."
    sleep 2
    exit
  fi
}
function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}脚本无法与 PiMox 兼容!\n"
    echo -e "\n 访问 https://github.com/asylumexp/Proxmox 获得 ARM64 支持.\n"
    echo -e "自动退出中..."
    sleep 2
    exit
  fi
}
function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "建议使用 Proxmox Shell 而不是 SSH，SSH 可能导致变量获取异常。是否继续？" 10 62; then
        echo "继续执行"
      else
        clear
        exit
      fi
    fi
  fi
}
function default_settings() {
  VMID="$NEXTID"
  FORMAT=""
  MACHINE=" -machine q35"
  DISK_SIZE="32G"
  HN="debian13"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}虚拟机 ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}虚拟机类型: ${BGN}q35${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}磁盘大小: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU 类型: ${BGN}HOST${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU 核心数: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM 大小: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}网桥: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC 地址: ${BGN}${MAC}${CL}"
}
check_root
arch_check
pve_check
ssh_check
default_settings
post_to_api_vm
msg_info "验证存储..."
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "无法检测到有效存储位置."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE 脚本" --title "存储池" --radiolist \
      "请选择存储池用于部署 Debian 13 虚拟机\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
  done
fi
msg_ok "使用 ${CL}${BL}$STORAGE${CL} ${GN} 作为存储位置."
msg_ok "虚拟机 ID 是 ${CL}${BL}$VMID${CL}."
msg_info "尝试下载 Debian 13 Cloud 镜像"
URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
wget -q --show-progress $URL
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "下载完成 ${CL}${BL}${FILE}${CL}"
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done
msg_info "正在创建 Debian 13 虚拟机"
qm create $VMID \
  -agent 1 \
  ${MACHINE} \
  -tablet 0 \
  -localtime 1 \
  -bios ovmf \
  ${CPU_TYPE} \
  -cores $CORE_COUNT \
  -memory $RAM_SIZE \
  -name $HN \
  -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU \
  -onboot 1 \
  -ostype l26 \
  -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${THIN}size=${DISK_SIZE} \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
msg_ok "Debian 13 虚拟机创建完成！ ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "正在启动 Debian 13 虚拟机"
  qm start $VMID
  msg_ok "Debian 13 虚拟机已启动"
fi
msg_ok "Debian 13 虚拟机部署完成!\n"
echo "更多信息请访问:"
echo "https://github.com/community-scripts/ProxmoxVE/discussions/836
