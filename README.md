# DeepSeek Harness 局域网部署包

**中文** | [English](README.en.md)

将 [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) 的 Web UI 部署为本机服务，并通过 HTTPS 反向代理对**局域网**开放，附带一键安装 / 启停 / 升级 / 补丁管理。

本仓库提供两个平台的部署方案，架构与解锁原理完全相同：

| 平台 | 位置 | 说明 |
|---|---|---|
| Linux / macOS (bash) | 仓库根目录 | 一键安装 + systemd / 桌面自启，详见 [README（本页）](#快速开始) |
| Windows (PowerShell) | [`win/`](win/README.md) | 一键安装 + 管理台脚本，详见 [win/README.md](win/README.md) |

> ⚠️ **安全须知**：本方案会解除 dsh 对远程浏览器的功能限制（见下文「设计背景」）。
> 部署后局域网内**任何设备**都可以使用本机的 agent 能力（含命令执行）、读取/修改设置与凭据状态。
> 请**只在可信网络使用**。生产环境请等待 dsh 官方认证层，或仅通过 SSH 隧道访问。

## 功能特性

- 局域网可访问：HTTPS 反向代理（自签名证书，随 IP 变化自动重签）
- 解锁完整功能：设置 / Agent 预设 / 凭据管理在局域网浏览器可用（补丁，可还原）
- 会话归档（归档/恢复/删除会话）：与解锁补丁一同自动应用（`patches/archive-core-rc2.mjs`，源自 gavinlee9051/dsh-modern-skin）
- 统一管理台：交互菜单 + 子命令（启动/停止/重启/状态/日志/升级）
- 升级无忧：dsh 升级覆盖补丁后，每次启动自动重新应用（版本不匹配时归档补丁自动跳过并提示）
- Linux 版额外支持：自动安装 Node.js/nvm、桌面登录自启 + systemd 用户服务二选一

## 快速开始

### Linux / macOS

```bash
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack
bash install.sh            # 或 bash install.sh --no-autostart
```

### Windows

```bat
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack\win
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装完成后按提示的地址访问：

- 本机：`https://127.0.0.1:3080`
- 局域网：`https://<本机局域网IP>:3080`

首次访问会提示证书不受信任（自签名），选择继续访问即可。随后在页面设置中添加模型提供方（如 DeepSeek）并填入 API Key。

## 日常使用

### Linux / macOS

```bash
./dsh.sh            # 交互式管理菜单
./dsh.sh status     # 进程 / 地址 / 版本 / 补丁状态
./dsh.sh restart    # 重启
./dsh.sh upgrade    # 升级 dsh 并重启
./dsh.sh log        # 实时日志
```

### Windows

在 `win` 目录打开终端（PowerShell 或 cmd）：

```bat
dsh-manage.cmd               交互式菜单（1启动 2停止 3重启 4状态 5日志 6升级 7打开网页）
dsh-manage.cmd status        进程 / 地址 / 版本 / 补丁状态
dsh-manage.cmd restart       重启
dsh-manage.cmd upgrade       升级 dsh 并自动重启、重打补丁
dsh-manage.cmd log           实时日志（Ctrl+C 退出）
dsh-manage.cmd open          打印带 token 的登录地址并用浏览器打开
```

## 脚本说明

### Linux / macOS（仓库根目录）

| 脚本 | 作用 |
|---|---|
| `install.sh` | 一键安装部署 |
| `dsh.sh` | 统一管理入口 |
| `start.sh` / `stop.sh` | 启动 / 停止 |
| `run.sh` | 前台启动（供 systemd 调用） |
| `upgrade.sh` | 升级 dsh 并自动重启、重打补丁 |
| `patch-lan.sh` | 局域网功能解锁补丁（幂等） |
| `patch-archive.sh` | 会话归档功能补丁（幂等，自动应用） |
| `patches/` | 核心补丁定义（`archive-core-rc2.mjs` 等） |
| `gen-cert.sh` | 自签名证书生成/更新 |
| `uninstall.sh` | 停止并移除自启动注册 |

### Windows（`win/`）

| 脚本 | 作用 |
|---|---|
| `win/install.ps1` | 一键安装部署（检查 Node → 全局装 dsh → 启动） |
| `win/dsh.ps1` | 统一管理入口（内含打补丁 / 建证书逻辑） |
| `win/dsh-manage.cmd` | `dsh.ps1` 的 cmd 包装 |
| `win/proxy.js` | HTTPS 反向代理（0.0.0.0:3080 → 127.0.0.1:3081），改写 Host/Origin/Referer |
| `win/uninstall.ps1` | 停止服务，可选卸载全局包 / 删除 ~/.dsh 数据 |

## 架构

```
浏览器(任意设备)
   │  https://<LAN-IP>:3080
   ▼
proxy.js (HTTPS, 0.0.0.0:3080)   ← 自签名证书 cert/
   │  改写 Host / Origin / Referer → 127.0.0.1:3081
   ▼
dsh web (HTTP, 仅监听 127.0.0.1:3081)
```

端口可通过环境变量 `PROXY_PORT` / `DSH_PORT` 覆盖。

## 设计背景：为什么需要代理和补丁

部署过程中会遇到 dsh 的三层安全机制，本包逐一给出了解法（也解释了为什么必须这么绕）：

1. **拒绝绑定 `0.0.0.0`**
   `dsh web --host 0.0.0.0` 会报错 "intentionally not supported yet for safety"。
   → 所以 dsh 只监听 localhost，由独立反向代理对外暴露。

2. **浏览器信任围栏 + 安全上下文**
   - 围栏要求 `Origin.host === Host.host` 且特权 RPC 的 Host 必须是 loopback，
     否则 `/api` 全部 403；`--trusted-host` 只影响 Host 检查，救不了 Origin。
     → 代理统一改写 `Host` / `Origin` / `Referer` 为内部地址。
   - `crypto.randomUUID()` 等 WebCrypto API 仅存在于安全上下文（HTTPS 或 localhost），
     明文 HTTP 访问局域网 IP 时前端会报
     "加载提供方目录失败: crypto.randomUUID is not a function"。
     → 代理提供 HTTPS（自签名证书）。

3. **设置面仅限 loopback（产品行为）**
   浏览器端用页面 URL 判断是否本机，非 loopback 直接禁用设置/预设/凭据；
   服务端也把这些方法硬编码为 loopback-only（注释称"直到存在真正的认证层"）。
   → 修改客户端下发文件中的 `isLoopback` 判定（原文件备份为 `.orig`，
     还原后重启即可）。配合代理的地址改写即可全功能使用。
   平台差异：Linux 用 `patch-lan.sh`；Windows 由 `win/dsh.ps1` 启动时自动应用。

### 会话归档功能

本仓库合并了来自 [dsh-modern-skin](https://github.com/gavinlee9051/dsh-modern-skin) 的
**归档会话**核心功能（仅核心，不含皮肤样式）：在 dsh 侧边栏新增「已归档」分区，
会话可归档 / 恢复 / 删除。实现为对 dsh 核心若干包的编译产物做锚点替换
（`patches/archive-core-rc2.mjs`），Linux 由 `patch-archive.sh`、Windows 由
`win/dsh.ps1` 在**每次启动**时幂等应用（含升级后自动重打）。

- **版本绑定**：补丁针对 `dsh 0.1.1-rc.2` 验证；`status` 会显示「归档补丁」状态。
  当 dsh 升级到其它版本时启动脚本会**自动跳过**并提示（避免误改不兼容的代码），
  直到该补丁随新版本锚点更新。
- **还原**：`npm install -g @deepseek-ai/dsh` 后重启即可回到官方原版。

## 常见问题

- **提示 `dsh web authentication required`？** dsh 0.1.5+ 需要一次性登录 token。启动脚本已自动从日志提取并打印带 token 的地址（形如 `https://127.0.0.1:3080/?token=...`），打开一次即可（会写入 cookie）；token 每次启动会轮换，`status` 也会显示当前 token 地址。
- **首次打开提示证书不安全？** 自签名所致，信任即可；IP 变化后下次启动自动重签。
- **页面白屏或行为异常？** 强制刷新（Ctrl+Shift+R）；仍异常看 `./dsh.sh log`（Windows：`dsh-manage.cmd log`）。
- **升级后补丁失效？** 每次启动会自动重打；若日志出现 `[patch] FAILED` / 状态显示补丁未应用，说明新版代码结构变了，欢迎提 issue。
- **防火墙（Linux）？** 若 ufw 激活且默认拒入站：`sudo ufw allow 3080/tcp`。
- **防火墙（Windows）？** 放行 TCP 3080 入站。
- **开机自启？** Linux：`systemctl --user enable --now deepseek-harness.service`（未登录常驻需 `sudo loginctl enable-linger $USER`）；Windows：默认不注册，用任务计划程序 / 启动目录指向 `win\dsh.ps1 start`。

## License

MIT。dsh 本身为 [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness) 的 MIT 项目，本仓库仅含部署辅助脚本。
