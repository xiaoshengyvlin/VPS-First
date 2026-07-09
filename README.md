# VPS-First

VPS 一键初始化 & 管理脚本，新机到手一条命令搞定基础配置。

**支持系统：** Alpine / Debian / Ubuntu / CentOS

## 快速开始

```bash
bash <(wget -qO- https://github.com/xiaoshengyvlin/VPS-First/raw/main/zako.sh 2>/dev/null || curl -sSL https://github.com/xiaoshengyvlin/VPS-First/raw/main/zako.sh)
```

## 功能

### 初始化向导

| 步骤 | 说明 |
|------|------|
| 系统检测 | 自动识别，1-4 选号确认 |
| SSH 端口 | 双端口模式，新老端口同时监听 |
| 系统更新 | 可选更新所有软件包 |
| 基础工具 | vim wget curl zip unzip lrzsz htop (net-tools) |
| BBR | 可选开启 TCP BBR 拥塞控制 |
| 主机名 | 自定义 |
| 时区 | 可选设为 Asia/Shanghai |
| Speedtest | 可选安装 |
| ZRAM | 可选开启，小内存 VPS 推荐 |
| SWAP | 可选开启，自定义大小 |

### 管理面板

初始化完成后，输入 `zako` 进入管理面板：

| 选项 | 功能 |
|------|------|
| 1 | 删除旧 SSH 端口 |
| 2 | 更换 SSH 端口 |
| 3 | 安装 fail2ban |
| 4 | 安装 Docker + docker-compose |
| 5 | 安装宝塔面板（Alpine 隐藏） |
| 6 | 安装 sing-box (233boy) |

## 安全设计

- SSH 改端口采用双端口过渡，确认新端口可用后再删旧端口
- 每次修改 SSH 配置前自动备份，`sshd -t` 校验失败自动回滚
- 防火墙端口自动同步放行/关闭
- `rm -rf` 路径均设 `:?` 保护，防止空变量误删

## Alpine 特殊处理

- 基础工具不包含 net-tools
- Docker 通过 `apk` 安装，非官方脚本
- 宝塔面板在管理面板中隐藏
- sing-box 安装前自动补装 bash

## 重新初始化

```bash
zako.sh --force
```
