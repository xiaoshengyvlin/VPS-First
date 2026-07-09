show_menu_banner() {
    _hostname=$(hostname 2>/dev/null || echo "?")
    _os_name=$(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME=" | cut -d'"' -f2 || echo "$OS_ID")
    _kernel=$(uname -r 2>/dev/null | cut -d- -f1)
    _ip=$(ip -4 addr show scope global 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1 || echo "N/A")
    _mem=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d/%dM", $3, $2}' || echo "?")
    _cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' | head -1 || echo "?")
    _swap=$(free -m 2>/dev/null | awk '/^Swap:/{printf "%d/%dM", $3, $2}' || echo "?")
    _uptime=$(awk '{d=int($1/86400);h=int($1%86400/3600);m=int($1%3600/60);printf "%dd %dh %dm",d,h,m}' /proc/uptime 2>/dev/null || echo "?")

    echo ""
    echo "  ${CYAN}╭─────────────────────────────────────────────────────╮${NC}"
    echo "  ${CYAN}│${NC}  ${BOLD}${YELLOW}▲ ZAKO 管理面板${NC}                      ${CYAN}${BOLD}v2${NC} ${CYAN}│${NC}"
    echo "  ${CYAN}├─────────────────────────────────────────────────────┤${NC}"
    printf "  ${CYAN}│${NC}  ${BOLD}主机${NC} %-16s ${BOLD}系统${NC} %-14s ${CYAN}│${NC}\n" "$_hostname" "$_os_name"
    printf "  ${CYAN}│${NC}  ${BOLD}内核${NC} %-16s ${BOLD}运行${NC} %-14s ${CYAN}│${NC}\n" "$_kernel" "$_uptime"
    printf "  ${CYAN}│${NC}  ${BOLD}CPU${NC}  %-16s ${BOLD}内存${NC} %-14s ${CYAN}│${NC}\n" "$(echo "$_cpu" | cut -c1-16)" "$_mem"
    printf "  ${CYAN}│${NC}  ${BOLD}IPv4${NC} %-16s ${BOLD}Swap${NC} %-14s ${CYAN}│${NC}\n" "$_ip" "$_swap"
    echo "  ${CYAN}╰─────────────────────────────────────────────────────╯${NC}"
    echo ""

    echo "  ${BOLD}${CYAN}[ SSH ]${NC}"
    echo "  ${GREEN} 1.${NC} 删除旧 SSH 端口     ${YELLOW}◆ 先确认新端口可用${NC}"
    echo "  ${GREEN} 2.${NC} 更换 SSH 端口"
    echo ""

    echo "  ${BOLD}${CYAN}[ 安全 ]${NC}"
    echo "  ${GREEN} 3.${NC} 安装 fail2ban"
    echo ""

    echo "  ${BOLD}${CYAN}[ 环境 ]${NC}"
    if [ "$OS_ID" = "alpine" ]; then
        echo "  ${GREEN} 4.${NC} 安装 Docker ${YELLOW}(apk)${NC}"
    else
        echo "  ${GREEN} 4.${NC} 安装 Docker + docker-compose"
        echo "  ${GREEN} 5.${NC} 安装宝塔面板"
    fi
    echo ""

    echo "  ${BOLD}${CYAN}[ 测试 ]${NC}"
    echo "  ${GREEN} 6.${NC} NodeQuality 跑分测试"
    echo "  ${GREEN} 7.${NC} speedtest 测速"
    echo ""

    echo "  ${BOLD}${CYAN}[ 系统 ]${NC}"
    echo "  ${GREEN} 8.${NC} 安装 sing-box (233boy)"
    echo "  ${GREEN} r.${NC} 重新初始化        ${YELLOW}◆ 清除配置重走向导${NC}"
    echo ""

    echo "  ${BOLD}输入${NC} ${GREEN}1-8${NC} ${BOLD}选择功能${NC}  ${GREEN}r${NC}${BOLD}重初始化${NC}  ${GREEN}q${NC}${BOLD}退出${NC}"
    echo ""
}