# Windows 版：DeepSeek Harness 局域网部署包

本目录是本仓库的 **Windows 移植**（PowerShell 版），功能与根目录的 Linux 版一致：
将 [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) 的 Web UI 部署为本机服务，并通过 HTTPS 反向代理对**局域网**开放，附带一键安装 / 启停 / 升级 / 卸载。

> ⚠️ **安全须知**：本方案会解除 dsh 对远程浏览器的功能限制。
> 部署后局域网内**任何设备**都可以使用本机的 agent 能力（含命令执行）、读取/修改设置与凭据状态。
> 请**只在可信网络使用**。

## 环境要求

- Windows 10/11
- Node.js >= 22（未安装：`winget install OpenJS.NodeJS.LTS` 或从 https://nodejs.org 下载）
- Git for Windows（自带 openssl，用于生成证书）

## 快速开始

```bat
git clone https://github.com/gavinlee9051/deepseek-harness-pack.git
cd deepseek-harness-pack\win
powershell -ExecutionPolicy Bypass -File install.ps1
```

访问地址（IP 以实际为准）：

- 本机：`https://127.0.0.1:3080`
- 局域网：`https://<本机局域网IP>:3080`

首次访问提示证书不受信任（自签名）→ 选择「继续访问」。

## 日常使用

在 `win` 目录打开终端：

```bat
dsh-manage.cmd               交互式菜单（1启动 2停止 3重启 4状态 5日志 6升级 7打开网页）
dsh-manage.cmd start         启动（自动打补丁、检查/重建证书）
dsh-manage.cmd stop          停止
dsh-manage.cmd restart       重启
dsh-manage.cmd status        进程 / 地址 / 版本 / 补丁（局域网解锁 + 会话归档）状态
dsh-manage.cmd log           实时日志（Ctrl+C 退出）
dsh-manage.cmd upgrade       升级 dsh 并自动重启、重打补丁
dsh-manage.cmd open          打印当前带 token 的登录地址并用默认浏览器打开
```

> 侧边栏会话菜单新增「归档会话」，归档后出现在「已归档」分区，可恢复或永久删除。
> 该功能为合并自 [dsh-modern-skin](https://github.com/gavinlee9051/dsh-modern-skin) 的核心功能
> （不含皮肤样式），由 `dsh.ps1` 启动时幂等应用。`status` 显示 `archive patch: applied`。
> 补丁按 dsh 版本选择，已验证 `0.1.1-rc.2` 与 `0.1.5-rc.1`；其它版本会提示 skipped，
> 等补丁更新后再自动生效。

PowerShell 直调：

```powershell
powershell -ExecutionPolicy Bypass -File dsh.ps1 status
```

## 首次使用：配置模型凭据

浏览器打开 `https://127.0.0.1:3080`，在设置中添加模型提供方（如 DeepSeek）并填入 API Key。

## 脚本说明

| 文件 | 作用 |
| --- | --- |
| `install.ps1` | 一键安装部署（检查 Node → 全局装 dsh → 启动） |
| `dsh.ps1` | 统一管理入口（内含打补丁 / 建证书逻辑） |
| `dsh-manage.cmd` | `dsh.ps1` 的 cmd 包装 |
| `proxy.js` | HTTPS 反向代理（0.0.0.0:3080 → 127.0.0.1:3081），改写 Host/Origin/Referer |
| `uninstall.ps1` | 停止服务，可选卸载全局包 / 删除 ~/.dsh 数据 / 清理运行文件 |

> `dsh.ps1` 会在部署目录 `patches\` 或仓库根 `patches\` 下查找与 dsh 版本匹配的归档补丁
> （`archive-core-rc2.mjs` / `archive-core-0.1.5.mjs`）。若你只拷贝本 `win` 目录单独使用，
> 请把仓库根的 `patches\` 目录一并复制到 `dsh.ps1` 同级，否则启动会提示找不到补丁脚本
> （不影响 dsh 与局域网功能）。

运行期生成：`cert/`（证书）、`logs/`（日志）、`*.pid`（进程号）——已加入 `.gitignore`。

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

与根目录 Linux 版相同（dsh 拒绝绑定 0.0.0.0、浏览器信任围栏、WebCrypto 需安全上下文、
设置面仅限 loopback）。区别仅在实现方式：

- 启动时以 PowerShell 自动把 dsh 下发的 `client.js` 中 `isLoopback` 判定改为恒真（原文件备份为 `.orig`），升级后每次启动自动重打；
- 用 `--trusted-host` 放行公开权威主机，由 `proxy.js` 统一改写 `Host`/`Origin`/`Referer`。

## 常见问题

- **提示 `dsh web authentication required`？** dsh 0.1.5+ 需要一次性登录 token。`dsh.ps1 start/restart` 会自动从日志提取并打印带 token 的地址（形如 `https://127.0.0.1:3080/?token=...`），打开一次即可（写入 cookie）；token 每次启动轮换，`status` 亦会显示当前 token 地址。
- **首次打开提示证书不安全？** 自签名所致，信任即可；IP 变化后下次启动自动重签。
- **页面白屏或行为异常？** 强制刷新（Ctrl+Shift+R）；仍异常看 `dsh-manage.cmd log`。
- **升级后补丁失效？** 每次启动自动重打；若 `status` 显示补丁未应用，说明新版代码结构变了，欢迎提 issue。
- **防火墙拦截局域网访问？** 放行 TCP 3080 入站。
- **想开机自启？** 用「任务计划程序」或「启动」目录指向 `dsh.ps1 start`（默认不注册）。

## License

MIT。dsh 本身为 [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness) 的 MIT 项目，本目录是其部署辅助脚本的 Windows 移植。
