# linux_sh

用于初始化 Debian 系 VPS 的模块化脚本集合。当前实现围绕 README 里的目标拆成独立阶段，并在执行前后做分阶段检查，方便先审阅、再 dry-run、再正式执行。

## 功能

- 更新软件源并安装常用基础软件
- 运行时交互选择时区，并启用 NTP
- 配置 `vnstat` / `vnstati`，登录 SSH 时显示最近 24 小时流量摘要
- 设置统一的 shell 提示符和 `ls --color=auto`
- 检测 LXC，非 LXC 环境下启用 BBR
- 通过可选的 UDP/443 封禁来禁用 QUIC，优先让 YouTube 等场景回退到 TCP/TLS

## 目录结构

- `bootstrap.sh`：主入口，负责参数解析、阶段发现、分阶段检查和执行
- `lib/common.sh`：公共函数、日志、交互和写文件辅助函数
- `stages/00-preflight.sh`：环境检查
- `stages/10-packages.sh`：软件包安装
- `stages/20-timezone.sh`：时区与 NTP
- `stages/30-vnstat.sh`：流量统计与 SSH 登录摘要
- `stages/40-shell.sh`：shell 提示符
- `stages/50-bbr.sh`：BBR
- `stages/60-youtube.sh`：QUIC 屏蔽

## 使用方式

需要 root 执行：

```sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

常用参数：

```sh
./bootstrap.sh --help
./bootstrap.sh --list-stages
sudo ./bootstrap.sh --dry-run
sudo ./bootstrap.sh --inspect-only
sudo ./bootstrap.sh --timezone Asia/Shanghai
sudo ./bootstrap.sh --only timezone
sudo ./bootstrap.sh --skip youtube-quic
sudo ./bootstrap.sh --enable-quic-block
sudo ./bootstrap.sh --disable-quic-block
```

## 阶段说明

### `preflight`

- 检查 root、`apt-get`、`dpkg`、`systemctl`
- 检查系统是否为 Debian 系
- 输出虚拟化类型，供后续 BBR 阶段使用

### `packages`

- 执行 `apt-get update`
- 执行 `apt-get upgrade -y`
- 安装以下基础包：
  - `sudo`
  - `curl`
  - `wget`
  - `vim`
  - `lsof`
  - `ca-certificates`
  - `iproute2`
  - `iptables`
  - `vnstat`
  - `vnstati`（如果源里存在单独包则安装）

### `timezone`

- 默认会在执行时给出可选时区菜单
- 支持 `--timezone` 直接指定
- 非交互模式且未指定时区时，保持当前时区不变
- 会尝试开启 `timedatectl set-ntp true`

### `vnstat`

- 启用 `vnstat.service`
- 自动识别默认出接口并初始化数据库
- 写入 `/usr/local/lib/linux_sh/vnstat-login.sh`
- 写入 `/etc/profile.d/40-linux-sh-vnstat.sh`
- SSH 登录时显示最近 24 小时文本流量信息，并在可用时生成 `vnstati` 图片到 `/var/tmp/linux_sh/`

### `shell`

- 写入 `/etc/profile.d/20-linux-sh-shell.sh`
- 使用和 README 原始风格接近的彩色提示符
- 主机名改为动态 `\h`，不硬编码固定名字

### `bbr`

- 若检测到 LXC，则直接跳过
- 若内核支持 BBR，则写入 `/etc/sysctl.d/99-linux-sh-bbr.conf`
- 应用：

```conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

### `youtube-quic`

- 这是可选阶段
- 默认交互执行时会询问是否启用
- 启用后会创建 `linux-sh-disable-quic.service`
- 服务通过 `iptables` 持久化阻断出站 `UDP/443`
- 这是系统级 QUIC 屏蔽，不只针对 YouTube

## 建议执行顺序

1. `sudo ./bootstrap.sh --inspect-only`
2. `sudo ./bootstrap.sh --dry-run`
3. `sudo ./bootstrap.sh`
4. 重新 SSH 登录，确认 `vnstat` 摘要和 shell 提示符
5. 检查 `sysctl net.ipv4.tcp_congestion_control` 与 QUIC 服务状态

## 五轮检查建议

1. 结构检查：确认 `bootstrap.sh`、`lib/`、`stages/` 是否齐全
2. 语法检查：对所有 `*.sh` 执行 `bash -n`
3. 帮助检查：运行 `./bootstrap.sh --help` 和 `--list-stages`
4. 干跑检查：运行 `--dry-run --non-interactive`
5. 审计检查：运行 `--inspect-only`，确认各阶段状态输出符合预期

## 说明

- 目标系统以 Debian / Ubuntu 这类 Debian 系为主
- 目前没有引入代理、第三方加速器或复杂的路由策略
- QUIC 屏蔽是保守实现，优先保证可回退、可关闭、可审计
