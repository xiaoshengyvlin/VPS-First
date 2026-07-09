#!/bin/sh
# ============================================
# Zako - VPS 一键初始化 & 管理脚本
# 支持: Alpine / Debian / Ubuntu / CentOS
# ============================================

MARKER_DIR="/var/lib/zako"
MARKER_FILE="$MARKER_DIR/initialized"
LOG_FILE="/var/log/zako-init.log"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
ZAKO_BACKUP_DIR="/var/backups/zako"

# ============ 颜色 ============
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# ============ 辅助函数 ============
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }
print_info()  { echo "${GREEN}[*]${NC} $*"; }
print_warn()  { echo "${YELLOW}[!]${NC} $*"; }
print_title() { echo ""; echo "${BOLD}${CYAN}=== $* ===${NC}"; }
print_error() { echo "${RED}[X]${NC} $*"; }
swapon_list() { swapon --show 2>/dev/null || swapon -s 2>/dev/null; }
wait_enter()  { printf "  按回车继续..."; read -r _; echo ""; }
ask_yn()      { printf "  %s [Y/n]: " "$1"; read -r yn; case "$yn" in [Nn]|[Nn][Oo]) return 1 ;; *) return 0 ;; esac; }

# ============ 包管理器配置 (共用) ============
setup_pkg() {
    case "$OS_ID" in
        alpine)
            PKG_UPDATE="apk update"
            PKG_UPGRADE="apk upgrade"
            PKG_INSTALL="apk add"
            ;;
        debian|ubuntu)
            PKG_UPDATE="apt update -y"
            PKG_UPGRADE="apt upgrade -y"
            PKG_INSTALL="apt install -y"
            ;;
        centos)
            if command -v dnf >/dev/null 2>&1; then
                PKG_UPDATE="dnf check-update"
                PKG_UPGRADE="dnf upgrade -y"
                PKG_INSTALL="dnf install -y"
            else
                PKG_UPDATE="yum check-update"
                PKG_UPGRADE="yum update -y"
                PKG_INSTALL="yum install -y"
            fi
            ;;
        *)
            print_error "不支持的系统: $OS_ID"
            exit 1
            ;;
    esac
}

# ============ 系统检测 ============
detect_os_mgmt() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            alpine|debian|ubuntu|centos|rhel|rocky|almalinux) OS_ID="$ID" ;;
            *) OS_ID="unknown" ;;
        esac
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
    else
        OS_ID="unknown"
    fi
    case "$OS_ID" in rhel|rocky|almalinux) OS_ID="centos" ;; esac
    setup_pkg
}

detect_os() {
    print_title "系统检测"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_NAME="$PRETTY_NAME"
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
        OS_NAME="Alpine $(cat /etc/alpine-release)"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        OS_NAME=$(cat /etc/redhat-release)
    else
        print_error "无法检测系统类型"; exit 1
    fi

    case "$OS_ID" in rhel|rocky|almalinux) OS_ID="centos" ;; esac

    echo "  检测到: ${BOLD}${OS_NAME}${NC} (${OS_ID})"
    echo ""
    echo "  ${BOLD}请选择系统类型:${NC}"
    echo "    ${GREEN}1.${NC} Alpine"
    echo "    ${GREEN}2.${NC} Debian"
    echo "    ${GREEN}3.${NC} Ubuntu"
    echo "    ${GREEN}4.${NC} CentOS"
    echo ""
    while true; do
        printf "  选择 (默认: %s): " "$OS_ID"
        read -r input
        [ -z "$input" ] && input="$OS_ID"
        case "$input" in
            1|alpine|Alpine)           OS_ID="alpine";  break ;;
            2|debian|Debian)           OS_ID="debian";  break ;;
            3|ubuntu|Ubuntu)           OS_ID="ubuntu";  break ;;
            4|centos|CentOS|rhel|RHEL) OS_ID="centos";  break ;;
            *) print_warn "请输入 1-4" ;;
        esac
    done
    print_info "确认系统: ${BOLD}$OS_ID${NC}"
    setup_pkg
}

# ============ SSH 辅助 ============
get_ssh_ports() {
    if command -v sshd >/dev/null 2>&1; then
        sshd -T 2>/dev/null | grep "^port " | awk '{print $2}' | sort -n | uniq
    elif [ -x /usr/sbin/sshd ]; then
        /usr/sbin/sshd -T 2>/dev/null | grep "^port " | awk '{print $2}' | sort -n | uniq
    fi
}

ssh_backup() {
    mkdir -p "$ZAKO_BACKUP_DIR"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="$ZAKO_BACKUP_DIR/ssh_$timestamp"
    mkdir -p "$backup_dir"
    cp "$SSHD_CONFIG" "$backup_dir/sshd_config.bak"
    [ -d "$SSHD_CONFIG_DIR" ] && cp -r "$SSHD_CONFIG_DIR" "$backup_dir/sshd_config.d" 2>/dev/null || true
    echo "$backup_dir"
}

ssh_validate() {
    backup_dir="$1"
    if command -v sshd >/dev/null 2>&1; then
        if ! sshd -t 2>/dev/null; then false; else true; fi
    elif [ -x /usr/sbin/sshd ]; then
        if ! /usr/sbin/sshd -t 2>/dev/null; then false; else true; fi
    else
        return 0
    fi
}

ssh_rollback() {
    backup_dir="$1"
    print_error "SSH 配置校验失败，正在从备份恢复..."
    cp "$backup_dir/sshd_config.bak" "$SSHD_CONFIG"
    if [ -d "$backup_dir/sshd_config.d" ] && [ -n "$SSHD_CONFIG_DIR" ]; then
        rm -rf "${SSHD_CONFIG_DIR:?}"/*
        cp -r "$backup_dir/sshd_config.d"/* "$SSHD_CONFIG_DIR"/ 2>/dev/null || true
    fi
}

validate_port() {
    port="$1"; existing_ports="$2"
    if [ -z "$port" ]; then return 1; fi
    case "$port" in ''|*[!0-9]*) print_warn "请输入纯数字"; return 1 ;; esac
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        print_warn "端口范围: 1024-65535"; return 1
    fi
    if echo "$existing_ports" | grep -q "^$port\$"; then
        print_warn "端口 $port 已经在监听中"; return 1
    fi
    return 0
}

# ============ 防火墙 ============
manage_firewall() {
    action="$1"; port="$2"
    case "$action" in
        open)
            if command -v ufw >/dev/null 2>&1; then
                ufw allow "$port"/tcp 2>/dev/null || true
                print_info "UFW 已放行端口 $port/tcp"
            elif command -v firewall-cmd >/dev/null 2>&1; then
                firewall-cmd --permanent --add-port="$port"/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                print_info "firewalld 已放行端口 $port/tcp"
            else
                print_warn "未检测到防火墙，跳过端口 $port"
            fi
            ;;
        close)
            if command -v ufw >/dev/null 2>&1; then
                ufw delete allow "$port"/tcp 2>/dev/null || true
                print_info "UFW 已关闭端口 $port/tcp"
            elif command -v firewall-cmd >/dev/null 2>&1; then
                firewall-cmd --permanent --remove-port="$port"/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                print_info "firewalld 已关闭端口 $port/tcp"
            fi
            ;;
    esac
}

# ============ SSH 操作 ============
add_ssh_port() {
    new_port="$1"
    print_info "配置 SSH 新端口: ${BOLD}$new_port${NC}"

    backup_dir=$(ssh_backup)
    print_info "备份已保存到: $backup_dir"

    if grep -q "# BEGIN ZAKO MANAGED BLOCK" "$SSHD_CONFIG" 2>/dev/null; then
        sed -i "/# BEGIN ZAKO MANAGED BLOCK/a\\
Port $new_port" "$SSHD_CONFIG"
    else
        cat >> "$SSHD_CONFIG" << EOF

# BEGIN ZAKO MANAGED BLOCK
Port $new_port
# END ZAKO MANAGED BLOCK
EOF
    fi

    if ! ssh_validate "$backup_dir"; then
        ssh_rollback "$backup_dir"
        return 1
    fi

    print_info "SSH 配置校验通过"
    manage_firewall open "$new_port"
    restart_sshd
    print_info "SSH 现在同时监听新端口 ${BOLD}$new_port${NC} 和原有端口"
}

remove_ssh_port() {
    port_to_remove="$1"
    current_ports=$(get_ssh_ports)
    if [ "$(echo "$current_ports" | wc -l)" -le 1 ]; then
        print_error "只有一个端口在监听，不能删除！至少保留一个端口。"
        return 1
    fi

    print_warn "即将从 SSH 配置中移除端口: ${BOLD}$port_to_remove${NC}"
    backup_dir=$(ssh_backup)

    sed -i "/^# BEGIN ZAKO MANAGED BLOCK/,/^# END ZAKO MANAGED BLOCK/ s/^Port $port_to_remove\$//" "$SSHD_CONFIG"

    if ! ssh_validate "$backup_dir"; then
        ssh_rollback "$backup_dir"
        return 1
    fi

    print_info "SSH 配置校验通过"
    manage_firewall close "$port_to_remove"
    restart_sshd
    print_info "已移除端口 ${BOLD}$port_to_remove${NC}"
}

restart_sshd() {
    print_info "重启 SSH 服务..."
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active sshd >/dev/null 2>&1; then
        systemctl restart sshd
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active ssh >/dev/null 2>&1; then
        systemctl restart ssh
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sshd restart 2>/dev/null || rc-service ssh restart 2>/dev/null || true
    else
        service sshd restart 2>/dev/null || service ssh restart 2>/dev/null || true
    fi
}

# ============ 配置: SSH 端口 ============
config_ssh() {
    print_title "SSH 端口配置"
    echo "  SSH 双端口模式: 增加新端口同时保留原端口，确保不会失联。"
    echo "  新端口测试可用后，用 ${BOLD}zako${NC} 管理面板删除旧端口。"
    echo ""

    current_ports=$(get_ssh_ports)
    [ -z "$current_ports" ] && current_ports="22" && print_warn "无法检测 SSH 端口，默认使用 22"
    echo "  当前 SSH 监听端口: ${BOLD}$(echo "$current_ports" | tr '\n' ' ')${NC}"

    while true; do
        printf "  请输入新 SSH 端口 (1024-65535，回车跳过): "
        read -r new_port
        [ -z "$new_port" ] && print_warn "跳过 SSH 端口配置" && return
        validate_port "$new_port" "$current_ports" && break
    done

    NEW_SSH_PORT="$new_port"
    print_info "新 SSH 端口已记录: ${BOLD}$NEW_SSH_PORT${NC}"
}

# ============ 配置: 系统更新 & 工具 ============
config_update() {
    print_title "系统更新 & 基础工具"
    if ask_yn "是否更新所有软件包?"; then DO_UPDATE=true; print_info "将执行系统更新"
    else DO_UPDATE=false; print_info "跳过系统更新"; fi

    if [ "$OS_ID" = "alpine" ]; then
        if ask_yn "是否安装基础工具 (vim wget curl zip unzip lrzsz htop)?"; then
            DO_INSTALL_TOOLS=true; print_info "将安装基础工具"
        else DO_INSTALL_TOOLS=false; print_info "跳过基础工具安装"; fi
    else
        if ask_yn "是否安装基础工具 (vim wget curl zip unzip lrzsz htop net-tools)?"; then
            DO_INSTALL_TOOLS=true; print_info "将安装基础工具"
        else DO_INSTALL_TOOLS=false; print_info "跳过基础工具安装"; fi
    fi
}

do_update()   { print_info "更新软件包..."; $PKG_UPDATE || true; $PKG_UPGRADE || true; }

do_install_tools() {
    print_info "安装基础工具..."
    case "$OS_ID" in
        alpine) $PKG_INSTALL vim wget curl zip unzip lrzsz htop 2>/dev/null || true ;;
        debian|ubuntu) $PKG_INSTALL vim wget curl zip unzip lrzsz htop net-tools 2>/dev/null || true ;;
        centos) $PKG_INSTALL epel-release 2>/dev/null || true
                $PKG_INSTALL vim wget curl zip unzip lrzsz htop net-tools 2>/dev/null || true ;;
    esac
    print_info "基础工具安装完成"
}

# ============ 配置: BBR ============
config_bbr() {
    print_title "BBR 拥塞控制"
    if ask_yn "是否开启 BBR?"; then DO_BBR=true; print_info "将开启 BBR"
    else DO_BBR=false; print_info "跳过 BBR"; fi
}

do_bbr() {
    [ "$(uname -r | cut -d. -f1)" -lt 4 ] && print_warn "内核版本低于 4.x，BBR 可能不支持，跳过" && return
    print_info "开启 BBR..."
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf 2>/dev/null || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr && print_info "BBR 已启用" || \
        print_warn "BBR 启用失败，当前: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null)"
}

# ============ 配置: 主机名 & 时区 ============
config_host() {
    print_title "主机名 & 时区"
    current_hostname=$(hostname)
    printf "  输入主机名 (当前: ${BOLD}%s${NC}，回车跳过): " "$current_hostname"
    read -r new_hostname
    if [ -n "$new_hostname" ]; then
        NEW_HOSTNAME="$new_hostname"
        print_info "主机名将设为: ${BOLD}$NEW_HOSTNAME${NC}"
    else print_info "跳过主机名设置"; fi

    if ask_yn "是否设置时区为 ${BOLD}Asia/Shanghai${NC} (上海)?"; then
        DO_TIMEZONE=true; print_info "时区将设为: Asia/Shanghai"
    else DO_TIMEZONE=false; print_info "跳过时区设置"; fi
}

do_hostname() {
    if [ -n "$NEW_HOSTNAME" ]; then
        print_info "设置主机名: $NEW_HOSTNAME"
        hostname "$NEW_HOSTNAME"
        echo "$NEW_HOSTNAME" > /etc/hostname 2>/dev/null || true
        if grep -q "127.0.0.1" /etc/hosts 2>/dev/null; then
            old_name=$(hostname 2>/dev/null)
            [ -n "$old_name" ] && sed -i "s/$(echo "$old_name" | sed 's/[.]/[.]/g')/$NEW_HOSTNAME/g" /etc/hosts 2>/dev/null || true
        fi
    fi
}

do_timezone() {
    [ "$DO_TIMEZONE" != true ] && return
    print_info "设置时区为 Asia/Shanghai..."
    if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
    else
        case "$OS_ID" in
            alpine) $PKG_INSTALL tzdata ;;
            debian|ubuntu) $PKG_INSTALL tzdata 2>/dev/null || true ;;
            centos) timedatectl set-timezone Asia/Shanghai 2>/dev/null || true ;;
        esac
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
    fi
    print_info "时区已设置"
}

# ============ 配置: Speedtest ============
config_speedtest() {
    print_title "Speedtest"
    if ask_yn "是否安装 speedtest?"; then DO_SPEEDTEST=true; print_info "将安装 speedtest"
    else DO_SPEEDTEST=false; print_info "跳过 speedtest"; fi
}

do_speedtest() {
    print_info "安装 speedtest..."
    case "$OS_ID" in
        alpine)
            $PKG_INSTALL speedtest-cli 2>/dev/null || {
                wget -O /usr/local/bin/speedtest-cli https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py 2>/dev/null || \
                curl -sSL -o /usr/local/bin/speedtest-cli https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py 2>/dev/null
                chmod +x /usr/local/bin/speedtest-cli 2>/dev/null || true
            } ;;
        debian|ubuntu)
            command -v speedtest >/dev/null 2>&1 || command -v speedtest-cli >/dev/null 2>&1 && print_info "speedtest 已安装" && return
            curl -sSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh 2>/dev/null | sh >/dev/null 2>&1 || true
            apt install -y speedtest 2>/dev/null || $PKG_INSTALL speedtest-cli 2>/dev/null || true ;;
        centos)
            curl -sSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh 2>/dev/null | sh >/dev/null 2>&1 || true
            yum install -y speedtest 2>/dev/null || dnf install -y speedtest 2>/dev/null || true ;;
    esac
    command -v speedtest >/dev/null 2>&1 || command -v speedtest-cli >/dev/null 2>&1 && print_info "speedtest 安装完成" || \
        print_warn "speedtest 安装失败，可稍后手动安装"
}

# ============ 配置: ZRAM ============
config_zram() {
    print_title "ZRAM 虚拟内存"

    total_mem=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
    echo "  当前内存: ${BOLD}${total_mem}MB${NC}"
    echo "  ZRAM 在内存中划一块区域存放压缩数据，适合小内存 VPS。"
    echo ""
    if ask_yn "是否开启 ZRAM? (256MB 以下强烈推荐)"; then
        DO_ZRAM=true; print_info "将开启 ZRAM"
    else DO_ZRAM=false; print_info "跳过 ZRAM"; fi
}

do_zram() {
    [ "$DO_ZRAM" != true ] && return
    print_info "开启 ZRAM..."

    case "$OS_ID" in
        alpine)
            modprobe zram 2>/dev/null || true
            apk add zram-init 2>/dev/null || {
                # 手动启用 ZRAM
                echo 1 > /sys/block/zram0/reset 2>/dev/null || true
                echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
                echo 256M > /sys/block/zram0/disksize 2>/dev/null || true
                mkswap /dev/zram0 2>/dev/null
                swapon /dev/zram0 2>/dev/null
                grep -q "/dev/zram0" /etc/fstab 2>/dev/null || echo "/dev/zram0 none swap defaults 0 0" >> /etc/fstab
            }
            ;;
        debian|ubuntu)
            $PKG_INSTALL zram-tools 2>/dev/null || true
            systemctl restart zramswap 2>/dev/null || true
            ;;
        centos)
            modprobe zram 2>/dev/null || true
            $PKG_INSTALL zram-generator 2>/dev/null || {
                echo 1 > /sys/block/zram0/reset 2>/dev/null || true
                echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
                echo 256M > /sys/block/zram0/disksize 2>/dev/null || true
                mkswap /dev/zram0 2>/dev/null
                swapon /dev/zram0 2>/dev/null
            }
            ;;
    esac

    swapon_list | grep -q zram && print_info "ZRAM 已开启" || print_warn "ZRAM 开启失败"
}

# ============ 配置: SWAP ============
config_swap() {
    print_title "SWAP 虚拟内存"
    if swapon_list | grep -q .; then
        print_info "当前已有 SWAP:"; swapon_list
        printf "  是否仍然添加新的 SWAP? [y/N]: "; read -r yn
        case "$yn" in [Yy]|[Yy][Ee][Ss]) ;; *) DO_SWAP=false; print_info "跳过 SWAP"; return ;; esac
    fi

    if ask_yn "是否开启 SWAP?"; then
        DO_SWAP=true
        while true; do
            printf "  请输入 SWAP 大小 (单位 MB，默认 1024): "; read -r swap_size
            [ -z "$swap_size" ] && swap_size=1024
            case "$swap_size" in ''|*[!0-9]*) print_warn "请输入纯数字"; continue ;; esac
            [ "$swap_size" -lt 64 ] && print_warn "SWAP 大小至少 64MB" && continue
            SWAP_SIZE="$swap_size"; break
        done
        print_info "SWAP 大小: ${BOLD}${SWAP_SIZE}MB${NC}"
    else DO_SWAP=false; print_info "跳过 SWAP"; fi
}

do_swap() {
    [ "$DO_SWAP" != true ] && return
    swapfile="/swapfile"
    if [ -f "$swapfile" ]; then
        swapoff "$swapfile" 2>/dev/null || true
        rm -f "$swapfile"
    fi
    print_info "创建 ${SWAP_SIZE}MB SWAP 文件..."
    dd if=/dev/zero of="$swapfile" bs=1M count="$SWAP_SIZE" 2>/dev/null
    chmod 600 "$swapfile"
    mkswap "$swapfile" >/dev/null 2>&1
    swapon "$swapfile"
    grep -q "$swapfile" /etc/fstab 2>/dev/null || echo "$swapfile none swap sw 0 0" >> /etc/fstab
    print_info "SWAP 已启用 ($(swapon_list | grep "$swapfile" | awk '{print $3}'))"
}

# ============ 汇总 & 执行 ============
show_summary() {
    print_title "配置汇总"
    echo ""
    echo "  ${BOLD}系统类型:${NC}     $OS_ID ($OS_NAME)"
    echo "  ${BOLD}SSH 端口:${NC}     $(echo "$current_ports" | tr '\n' ' ') $(if [ -n "$NEW_SSH_PORT" ]; then echo "-> 新增 $NEW_SSH_PORT"; else echo "(不变)"; fi)"
    echo "  ${BOLD}系统更新:${NC}     $(if [ "$DO_UPDATE" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}基础工具:${NC}     $(if [ "$DO_INSTALL_TOOLS" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}BBR:${NC}         $(if [ "$DO_BBR" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}主机名:${NC}      ${NEW_HOSTNAME:-不变}"
    echo "  ${BOLD}上海时区:${NC}    $(if [ "$DO_TIMEZONE" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}Speedtest:${NC}  $(if [ "$DO_SPEEDTEST" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}ZRAM:${NC}        $(if [ "$DO_ZRAM" = true ]; then echo '是'; else echo '否'; fi)"
    echo "  ${BOLD}SWAP:${NC}        $(if [ "$DO_SWAP" = true ]; then echo "是 (${SWAP_SIZE}MB)"; else echo '否'; fi)"
    echo ""
}

do_all() {
    print_title "开始执行"
    log "[START] 开始执行初始化"
    mkdir -p "$MARKER_DIR"

    [ -n "$NEW_SSH_PORT" ] && add_ssh_port "$NEW_SSH_PORT"
    [ "$DO_UPDATE" = true ] && do_update
    [ "$DO_INSTALL_TOOLS" = true ] && do_install_tools
    [ "$DO_BBR" = true ] && do_bbr
    do_hostname
    do_timezone
    [ "$DO_SPEEDTEST" = true ] && do_speedtest
    [ "$DO_ZRAM" = true ] && do_zram
    [ "$DO_SWAP" = true ] && do_swap

    date '+%Y-%m-%d %H:%M:%S' > "$MARKER_FILE"
    echo "os=$OS_ID" >> "$MARKER_FILE"
    echo "hostname=$(hostname)" >> "$MARKER_FILE"

    install_zako_cmd
    log "[DONE] 初始化完成"

    print_title "初始化完成!"
    echo ""
    echo "  以后运行 ${BOLD}zako${NC} 即可进入管理面板。"
    echo "  管理面板功能:"
    echo "    1. 删除旧 SSH 端口"
    echo "    2. 更换 SSH 端口"
    echo "    3. 安装 fail2ban"
    echo "    4. 安装 Docker"
    if [ "$OS_ID" != "alpine" ]; then
        echo "    5. 安装宝塔面板"
        echo "    6. NodeQuality 跑分测试"
        echo "    7. speedtest 测速"
        echo "    8. 安装 sing-box"
    else
        echo "    5. (宝塔面板不支持 Alpine，菜单已隐藏)"
        echo "    6. NodeQuality 跑分测试"
        echo "    7. speedtest 测速"
        echo "    8. 安装 sing-box"
    fi
    echo ""
    echo "  ${YELLOW}提示: 用新 SSH 端口连接测试成功后，运行 ${BOLD}zako${NC} 选择 1 删除旧端口。${NC}"
}

install_zako_cmd() {
    wget -qO /usr/local/bin/zako https://github.com/xiaoshengyvlin/VPS-First/raw/main/zako.sh 2>/dev/null || \
        curl -sSL -o /usr/local/bin/zako https://github.com/xiaoshengyvlin/VPS-First/raw/main/zako.sh 2>/dev/null
    chmod +x /usr/local/bin/zako 2>/dev/null || true
    command -v zako >/dev/null 2>&1 && print_info "已安装 zako 管理命令" || print_warn "zako 命令安装失败，可稍后手动安装"
}

# ============ 管理面板 ============
show_menu_banner() {
    echo ""
    echo "${BOLD}${CYAN}  ╔════════════════════════════════╗${NC}"
    echo "${BOLD}${CYAN}  ║       Z A K O  管 理 面 板     ║${NC}"
    echo "${BOLD}${CYAN}  ╚════════════════════════════════╝${NC}"
    echo ""
    echo "  ${BOLD}SSH 相关${NC}"
    echo "    ${GREEN}1.${NC} 删除旧 SSH 端口  ${YELLOW}(先确认新端口可用!)${NC}"
    echo "    ${GREEN}2.${NC} 更换 SSH 端口"
    echo ""
    echo "  ${BOLD}安全${NC}"
    echo "    ${GREEN}3.${NC} 安装 fail2ban"
    echo ""
    echo "  ${BOLD}环境${NC}"
    if [ "$OS_ID" = "alpine" ]; then
        echo "    ${GREEN}4.${NC} 安装 Docker (apk 方式)"
    else
        echo "    ${GREEN}4.${NC} 安装 Docker + docker-compose"
        echo "    ${GREEN}5.${NC} 安装宝塔面板"
    fi
    echo ""
    echo "  ${BOLD}测试${NC}"
    echo "    ${GREEN}6.${NC} NodeQuality 跑分测试"
    echo "    ${GREEN}7.${NC} speedtest 测速"
    echo ""
    echo "  ${BOLD}其他${NC}"
    echo "    ${GREEN}8.${NC} 安装 sing-box (233boy)"
    echo ""
    echo "  ${GREEN}0.${NC} 退出"
    echo ""
    echo "  ${YELLOW}重新初始化: zako --force${NC}"
    echo ""
}

management_menu() {
    show_menu_banner
    while true; do
        printf "  ${BOLD}选择:${NC} "
        read -r choice
        case "$choice" in
            1) mgmt_remove_ssh_port; wait_enter; show_menu_banner ;;
            2) mgmt_change_ssh_port; wait_enter; show_menu_banner ;;
            3) mgmt_install_fail2ban; wait_enter; show_menu_banner ;;
            4) mgmt_install_docker; wait_enter; show_menu_banner ;;
            5)
                if [ "$OS_ID" = "alpine" ]; then
                    print_warn "无效选项 (Alpine 不支持)" 
                else
                    mgmt_install_btpanel
                fi
                wait_enter; show_menu_banner ;;
            6) mgmt_nodequality; wait_enter; show_menu_banner ;;
            7) mgmt_speedtest; wait_enter; show_menu_banner ;;
            8) mgmt_install_singbox; wait_enter; show_menu_banner ;;
            0) echo "  再见"; exit 0 ;;
            *) print_warn "无效选项" ;;
        esac
    done
}

mgmt_remove_ssh_port() {
    print_title "删除旧 SSH 端口"
    ports=$(get_ssh_ports)
    [ -z "$ports" ] && print_error "无法获取当前 SSH 端口" && return

    echo "  当前监听端口:"
    for p in $ports; do echo "    ${BOLD}$p${NC}"; done

    [ "$(echo "$ports" | wc -l)" -le 1 ] && print_warn "只有一个端口，不能删除。" && return

    printf "  输入要删除的端口号: "; read -r del_port
    echo "$ports" | grep -q "^$del_port$" || { print_error "端口 $del_port 不在监听列表中"; return; }

    printf "  ${YELLOW}确认删除端口 ${BOLD}%s${NC}${YELLOW}? [y/N]: ${NC}" "$del_port"
    read -r yn
    case "$yn" in [Yy]|[Yy][Ee][Ss]) remove_ssh_port "$del_port" ;; *) print_info "取消" ;; esac
}

mgmt_change_ssh_port() {
    print_title "更换 SSH 端口"
    ports=$(get_ssh_ports)
    echo "  当前监听端口: $(echo "$ports" | tr '\n' ' ')"
    echo ""

    while true; do
        printf "  输入新端口号 (1024-65535): "; read -r new_port
        [ -z "$new_port" ] && print_info "取消" && return
        validate_port "$new_port" "$ports" && break
    done

    printf "  ${YELLOW}确认添加端口 ${BOLD}%s${NC}${YELLOW}? [y/N]: ${NC}" "$new_port"
    read -r yn
    case "$yn" in [Yy]|[Yy][Ee][Ss]) add_ssh_port "$new_port" ;; *) print_info "取消" ;; esac
}

mgmt_install_fail2ban() {
    print_title "安装 fail2ban"
    ask_yn "确认安装?" || { print_info "取消"; return; }

    case "$OS_ID" in
        alpine) $PKG_INSTALL fail2ban 2>/dev/null || true ;;
        debian|ubuntu) $PKG_UPDATE && $PKG_INSTALL fail2ban 2>/dev/null || true ;;
        centos) $PKG_INSTALL epel-release 2>/dev/null || true
                $PKG_INSTALL fail2ban 2>/dev/null || true
                systemctl enable fail2ban 2>/dev/null || true
                systemctl start fail2ban 2>/dev/null || true ;;
    esac
    command -v fail2ban-client >/dev/null 2>&1 && print_info "fail2ban 安装完成" || print_error "fail2ban 安装失败"
}

mgmt_install_docker() {
    print_title "安装 Docker + docker-compose"
    ask_yn "确认安装?" || { print_info "取消"; return; }

    case "$OS_ID" in
        alpine)
            print_info "安装 Docker (Alpine)..."
            apk add docker docker-compose 2>/dev/null || true
            rc-update add docker boot 2>/dev/null || true
            rc-service docker start 2>/dev/null || true
            ;;
        *)
            print_info "安装 Docker..."
            curl -fsSL https://get.docker.com | sh 2>/dev/null || { print_error "Docker 官方脚本安装失败"; return; }
            systemctl enable docker 2>/dev/null || true
            systemctl start docker 2>/dev/null || true
            print_info "Docker 安装完成"

            print_info "安装 docker-compose..."
            command -v curl >/dev/null 2>&1 && {
                curl -sSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null || true
                chmod +x /usr/local/bin/docker-compose 2>/dev/null || true
            }
            ;;
    esac

    command -v docker >/dev/null 2>&1 && print_info "Docker 安装完成" || print_warn "Docker 安装失败"
    command -v docker-compose >/dev/null 2>&1 && print_info "docker-compose 安装完成" || \
        { docker compose version >/dev/null 2>&1 && print_info "Docker Compose 插件已可用"; }
}

mgmt_nodequality() {
    print_title "NodeQuality 跑分测试"
    echo "  在沙箱环境中运行 VPS 综合性能测试，测完自动清理，无痕测试。"
    echo "  包含: Yabs + IP 质量 + 网络质量 + 融合怪部分功能。"
    echo ""
    ask_yn "确认执行?" || { print_info "取消"; return; }
    print_info "正在下载并运行 NodeQuality..."
    curl -sSL -o /tmp/nq.sh https://run.NodeQuality.com 2>/dev/null || \
        wget -qO /tmp/nq.sh https://run.NodeQuality.com 2>/dev/null
    bash /tmp/nq.sh
    rm -f /tmp/nq.sh
}

mgmt_speedtest() {
    print_title "speedtest 测速"
    if command -v speedtest >/dev/null 2>&1; then
        speedtest
    elif command -v speedtest-cli >/dev/null 2>&1; then
        speedtest-cli
    else
        print_warn "speedtest 未安装，正在安装..."
        do_speedtest
        command -v speedtest >/dev/null 2>&1 && speedtest && return
        command -v speedtest-cli >/dev/null 2>&1 && speedtest-cli && return
        print_error "安装失败，请稍后重试"
    fi
}

mgmt_install_singbox() {
    print_title "安装 sing-box (233boy)"
    ask_yn "确认安装?" || { print_info "取消"; return; }
    print_info "正在安装 sing-box..."
    if ! command -v bash >/dev/null 2>&1; then
        print_info "安装 bash..."
        case "$OS_ID" in
            alpine) apk add bash 2>/dev/null || true ;;
            *) $PKG_INSTALL bash 2>/dev/null || true ;;
        esac
    fi
    curl -sSL -o /tmp/singbox-install.sh https://github.com/233boy/sing-box/raw/main/install.sh 2>/dev/null || \
        wget -qO /tmp/singbox-install.sh https://github.com/233boy/sing-box/raw/main/install.sh 2>/dev/null
    bash /tmp/singbox-install.sh
    rm -f /tmp/singbox-install.sh
}

mgmt_install_btpanel() {
    print_title "安装宝塔面板"
    echo "  宝塔面板是一个可视化的服务器管理面板。"
    echo "  安装完成后请保存面板地址、用户名和密码。"
    echo ""
    ask_yn "确认安装?" || { print_info "取消"; return; }

    case "$OS_ID" in
        alpine)
            print_error "宝塔面板不支持 Alpine 系统"; return ;;
        debian|ubuntu)
            print_info "正在安装宝塔面板 (Debian/Ubuntu)..."
            wget -O install.sh https://download.bt.cn/install/install-ubuntu_6.0.sh 2>/dev/null || \
                curl -sSL -o install.sh https://download.bt.cn/install/install-ubuntu_6.0.sh
            bash install.sh ed8484bec ;;
        centos)
            print_info "正在安装宝塔面板 (CentOS)..."
            wget -O install.sh https://download.bt.cn/install/install_6.0.sh 2>/dev/null || \
                curl -sSL -o install.sh https://download.bt.cn/install/install_6.0.sh
            bash install.sh ed8484bec ;;
        *)
            print_error "不支持的系统"; return ;;
    esac
}

# ============ 入口 ============
main() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "请以 root 身份运行此脚本"
        exit 1
    fi

    cd "$(dirname "$0")" || true
    mkdir -p "$MARKER_DIR"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE" 2>/dev/null || true

    if [ "$1" = "--force" ]; then
        print_info "--force: 强制进入初始化向导"
    elif [ -f "$MARKER_FILE" ]; then
        detect_os_mgmt
        management_menu
        return
    fi

    # ===== 初始化向导 =====
    clear 2>/dev/null || true
    echo ""
    echo "${BOLD}${CYAN}  ╔═══════════════════════════════════╗${NC}"
    echo "${BOLD}${CYAN}  ║  Z A K O   V P S  初 始 化 向 导  ║${NC}"
    echo "${BOLD}${CYAN}  ╚═══════════════════════════════════╝${NC}"
    echo ""

    detect_os
    config_ssh
    config_update
    config_bbr
    config_host
    config_speedtest
    config_zram
    config_swap

    show_summary
    printf "  ${BOLD}${YELLOW}确认执行? 按 y 继续: ${NC}"
    read -r confirm
    case "$confirm" in
        [Yy]|[Yy][Ee][Ss]) do_all ;;
        *) print_info "已取消"; exit 0 ;;
    esac
}

main "$@"
