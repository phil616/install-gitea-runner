# Gitea Runner 一键安装脚本

> 适用于 Linux 服务器的 [Gitea Actions Runner](https://gitea.com/gitea/runner) 自动化安装工具，支持 `gitea-runner v1.0.0+` 及历史版本 `act_runner v0.x`。

---

## 特性

- **全自动**：自动检测 CPU 架构、自动查询最新版本、自动注册、自动配置 systemd
- **交互友好**：5 步引导输入，全部有默认值，Token 输入不回显
- **安全加固**：独立系统用户（无 shell）、`NoNewPrivileges`、`PrivateTmp`、`ProtectSystem`
- **幂等执行**：已注册的 Runner、已存在的配置均跳过，重复运行不破坏现有环境
- **日志管理**：journald 持久化，保留 30 天，开箱即用
- **版本兼容**：自动识别 v1.0.0+ 新仓库与 v0.x 旧仓库的下载地址差异

---

## 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Debian 10+ · Ubuntu 20.04+ · RHEL/CentOS 8+ · Rocky · AlmaLinux |
| 架构 | `amd64` · `arm64` · `arm-7` · `s390x` · `riscv64` |
| 执行用户 | `root`（或具备 sudo 权限）|
| 依赖命令 | `curl` · `systemctl` · `useradd`（通常已预装）|
| Gitea 版本 | 1.19+（需已在管理后台启用 Actions）|

---

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/phil616/install-gitea-runner/main/install-gitea-runner.sh)
```

> **提示**：如果你的服务器访问 GitHub 原始内容较慢，可以先手动下载脚本再执行：
> ```bash
> curl -fsSLO https://raw.githubusercontent.com/phil616/install-gitea-runner/main/install-gitea-runner.sh
> bash install-gitea-runner.sh
> ```

---

## 安装流程

脚本执行后会依次引导你完成以下 5 步输入：

```
[1/5] Gitea 实例 URL        例: https://gitea.example.com
[2/5] Runner 注册 Token     在 Gitea 管理后台获取（输入不回显）
[3/5] Runner 名称           默认使用主机名
[4/5] Runner Labels         默认覆盖常用 ubuntu 标签
[5/5] 安装版本              默认自动获取最新版本
```

确认摘要后按回车，脚本将自动完成以下所有操作：

```
下载二进制  →  创建系统用户  →  生成配置文件  →  注册 Runner
     →  写入 systemd 服务  →  配置 journald  →  启动并启用自启
```

---

## 安装后的文件布局

```
/usr/local/bin/gitea-runner          # 可执行二进制
/etc/gitea-runner/config.yaml        # Runner 配置文件
/var/lib/gitea-runner/.runner        # 注册凭据文件（勿删）
/etc/systemd/system/gitea-runner.service  # systemd 服务单元
/etc/systemd/journald.conf.d/99-gitea-runner.conf  # 日志持久化配置
/var/log/gitea-runner/               # 日志目录（journald 软链）
```

---

## 服务管理

```bash
# 查看运行状态
systemctl status gitea-runner

# 启动 / 停止 / 重启
systemctl start   gitea-runner
systemctl stop    gitea-runner
systemctl restart gitea-runner

# 开机自启（安装时已启用）
systemctl enable  gitea-runner
systemctl disable gitea-runner
```

---

## 查看日志

```bash
# 实时跟踪日志（Ctrl+C 退出）
journalctl -u gitea-runner -f

# 查看最近 100 行
journalctl -u gitea-runner -n 100

# 查看今日日志
journalctl -u gitea-runner --since today

# 按时间范围过滤
journalctl -u gitea-runner --since "2025-01-01" --until "2025-12-31"

# 只看错误和警告
journalctl -u gitea-runner -p warning
```

> 日志由 journald 统一管理，默认**保留 30 天、最大占用 200MB**，无需手动轮转。

---

## 在 Gitea 管理面板验证

安装完成后，访问：

```
https://<你的 Gitea 地址>/-/admin/actions/runners
```

Runner 应显示为 **Online** 状态。如果显示 Offline，请查看日志排查原因。

---

## 如何获取 Runner Token

1. 以管理员身份登录 Gitea
2. 点击右上角头像 → **管理面板（Site Administration）**
3. 左侧菜单 → **Actions** → **Runners**
4. 点击 **Create new Runner**，复制 Token

> Token 可重复注册多个 Runner，直到你在管理面板手动重置。

---

## 重新注册 Runner

如需更换 Gitea 实例或 Token，删除注册文件后重新运行脚本即可：

```bash
systemctl stop gitea-runner
rm /var/lib/gitea-runner/.runner
bash install-gitea-runner.sh
```

---

## 卸载

```bash
systemctl stop gitea-runner
systemctl disable gitea-runner
rm -f /etc/systemd/system/gitea-runner.service
rm -f /usr/local/bin/gitea-runner
rm -rf /var/lib/gitea-runner /etc/gitea-runner
userdel gitea-runner
systemctl daemon-reload
```

---

## 常见问题

**Q：安装时提示「下载失败」怎么办？**

脚本会自动重试并切换备用下载源。如果仍然失败，可手动指定版本后重试，或检查服务器的出站网络是否能访问 `gitea.com`。

**Q：注册时提示「Token 无效」？**

Token 是一次性的注册凭据，每次在 Gitea 管理面板重置后都会变化。请确认你使用的是最新 Token，且 Gitea URL 没有包含末尾斜杠。

**Q：我的工作流需要 Docker，怎么处理？**

安装完成后，将 `gitea-runner` 用户加入 `docker` 组并重启服务：

```bash
usermod -aG docker gitea-runner
systemctl restart gitea-runner
```

> 这会赋予 Runner 对 Docker daemon 的访问权，等效于 root 访问，请在受信环境中使用。

**Q：脚本支持 ARM 服务器吗？**

支持，脚本会自动检测 `uname -m` 并下载对应架构的二进制（amd64 / arm64 / arm-7 / s390x / riscv64）。

---

## 相关链接

- [Gitea Runner 官方仓库](https://gitea.com/gitea/runner)
- [Gitea Actions 官方文档](https://docs.gitea.com/usage/actions/overview)
- [Runner 配置文件参考](https://gitea.com/gitea/runner/src/branch/main/config.example.yaml)

---

## License

MIT
