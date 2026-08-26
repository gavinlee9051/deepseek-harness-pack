# DeepSeek Harness 局域网部署包

**中文** | [English](README.en.md)

将 [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) 的 Web UI 部署为本机服务，并通过 HTTPS 反向代理对**局域网**开放，附带一键启停/升级/补丁管理。

> ⚠️ **安全须知**：本方案会解除 dsh 对远程浏览器的功能限制（见下文“设计背景”）。
> 部署后局域网内**任何设备**都可以使用本机的 agent 能力（含命令执行）、读取/修改设置与凭据状态。
> 请**只在可信网络使用**。生产环境请等待 dsh 官方认证层，或仅通过 SSH 隧道访问。

## 功能特性

- 一键安装：自动处理 Node.js / nvm / dsh 安装
- 局域网可访问：HTTPS 反向代理（自签名证书，随 IP 变化自动重签）
- 解锁完整功能：设置 / Agent 预设 / 凭据管理在局域网浏览器可用（补丁，可还原）
- 统一管理台：交互菜单 + 子命令（启动/停止/重启/状态/日志/升级）
- 开机自启：桌面登录自启动 + systemd 用户服务二选一
- 升级无忧：dsh 升级覆盖补丁后，每次启动自动重新应用

## 快速开始

```bash
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack
bash install.sh
```

安装完成后按提示的地址访问：

- 本机：`https://127.0.0.1:3080`
- 局域网：`https://<本机局域网IP>:3080`

首次访问会提示证书不受信任（自签名），选择继续访问即可。

## 日常使用

```bash
./dsh.sh            # 交互式管理菜单
./dsh.sh status     # 进程 / 地址 / 版本 / 补丁状态
./dsh.sh restart    # 重启
./dsh.sh upgrade    # 升级 dsh 并重启
./dsh.sh log        # 实时日志
```

| 脚本 | 作用 |
|---|---|
| `install.sh` | 一键安装部署 |
| `dsh.sh` | 统一管理入口 |
| `start.sh` / `stop.sh` | 启动 / 停止 |
| `run.sh` | 前台启动（供 systemd 调用） |
| `upgrade.sh` | 升级 dsh 并自动重启、重打补丁 |
| `patch-lan.sh` | 局域网功能解锁补丁（幂等） |
| `gen-cert.sh` | 自签名证书生成/更新 |
| `uninstall.sh` | 停止并移除自启动注册 |

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
     “加载提供方目录失败: crypto.randomUUID is not a function”。
     → 代理提供 HTTPS（自签名证书）。

3. **设置面仅限 loopback（产品行为）**
   浏览器端用页面 URL 判断是否本机，非 loopback 直接禁用设置/预设/凭据；
   服务端也把这些方法硬编码为 loopback-only（注释称“直到存在真正的认证层”）。
   → `patch-lan.sh` 修改客户端下发文件中的 `isLoopback` 判定（原文件备份为 `.orig`，
     还原：`cp client.js.orig client.js` 后重启）。配合代理的地址改写即可全功能使用。

## 常见问题

- **首次打开提示证书不安全？** 自签名所致，信任即可；IP 变化后下次启动自动重签。
- **页面白屏或行为异常？** 强制刷新（Ctrl+Shift+R）；仍异常看 `./dsh.sh log`。
- **升级后补丁失效？** 每次启动会自动重打；若日志出现 `[patch] FAILED` 说明新版代码结构变了，欢迎提 issue。
- **防火墙？** 若 ufw 激活且默认拒入站：`sudo ufw allow 3080/tcp`。
- **想开机无需登录就启动？** `systemctl --user enable --now deepseek-harness.service`
  （未登录常驻需 `sudo loginctl enable-linger $USER`）。

## License

MIT。dsh 本身为 [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness) 的 MIT 项目，本包仅是部署辅助脚本。
