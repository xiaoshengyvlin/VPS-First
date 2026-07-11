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
| TCP 优化 | 扩大缓冲区，优化高延迟/跨国线路 |
| 主机名 | 自定义 |
| 时区 | 可选设为 Asia/Shanghai |
| Speedtest | 可选安装 |
| ZRAM | 可选开启，小内存 VPS 推荐 |
| SWAP | 可选开启，自定义大小 |

### 管理面板

初始化完成后，输入 `zako` 进入管理面板，顶部实时显示主机信息：

```
╭─────────────────────────────────────────────────────╮
│  ▲ ZAKO 管理面板                              v2   │
├─────────────────────────────────────────────────────┤
│  主机 my-vps          系统 Debian 12                │
│  内核 5.15.0          运行 3d12h                    │
│  CPU  AMD EPYC        内存 22/244M                  │
│  Swap 0/0M            使用率 12%                    │
╰─────────────────────────────────────────────────────╯
```

| 选项 | 功能 |
|------|------|
| 1 | 删除旧 SSH 端口 |
| 2 | 更换 SSH 端口 |
| 3 | 安装 fail2ban |
| 4 | 安装 Docker + docker-compose |
| 5 | 安装宝塔面板（Alpine 隐藏） |
| 6 | NodeQuality 跑分测试 |
| 7 | speedtest 测速 |
| 8 | 安装 sing-box (233boy) |
| r | 重新初始化（清除配置） |
| q | 退出 |

### 初始化检查

初始化完成后自动逐项验证：

```
=== 初始化检查 ===
  ✓ SSH 端口       22 22222
  ✓ 系统更新       已执行
  ○ 基础工具       跳过
  ✓ BBR            已启用
  ✓ TCP 优化       已启用
  ✓ 主机名         my-vps
  ✓ 时区           Asia/Shanghai
  ○ Speedtest      跳过
  ✓ ZRAM           已开启
  ✓ SWAP           已启用 (1024MB)
  ✓ zako 命令      已安装
```

`✓` 生效 / `✗` 失败 / `○` 跳过

## 重新初始化

```bash
zako --force
```

或在管理面板按 `r`。

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

## 容器支持

- 内存/Swap 优先读取 cgroup 限额（v1/v2），容器内不显示母机数据
- CPU 使用率基于 `/proc/stat` 采样，容器级精准
