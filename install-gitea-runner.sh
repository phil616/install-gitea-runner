#!/usr/bin/env bash
# =============================================================================
# Gitea Runner 一键安装脚本
# 版本: v1.2.0
# 变更: 新增 Docker 环境检测与 docker 组自动配置
# 支持: gitea-runner (v1.0.0+) / act_runner (v0.x 历史兼容)
# 适用: Debian / Ubuntu / RHEL / CentOS / Rocky / AlmaLinux
# 用户: root
# 仓库: https://github.com/phil616/install-gitea-runner
# 上游: https://gitea.com/gitea/runner
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 输出工具
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[错误]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# --------------------------------------------------------------------------- #
# 基础检查
# --------------------------------------------------------------------------- #
[[ "$EUID" -ne 0 ]] && error "请以 root 用户运行此脚本（或使用 sudo）。"

for cmd in curl systemctl useradd; do
  command -v "$cmd" &>/dev/null || error "缺少依赖命令: $cmd，请先安装后重试。"
done

# --------------------------------------------------------------------------- #
# 检测系统架构
# --------------------------------------------------------------------------- #
detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64)          echo "amd64"   ;;
    aarch64|arm64)   echo "arm64"   ;;
    armv7l)          echo "arm-7"   ;;
    s390x)           echo "s390x"   ;;
    riscv64)         echo "riscv64" ;;
    *)               error "不支持的系统架构: $machine" ;;
  esac
}

ARCH="$(detect_arch)"

# --------------------------------------------------------------------------- #
# 获取最新版本号
# --------------------------------------------------------------------------- #
get_latest_version() {
  local ver
  ver=$(curl -sf "https://gitea.com/api/v1/repos/gitea/runner/releases?limit=1" \
        | grep -o '"tag_name":"[^"]*"' | head -1 \
        | sed 's/.*:"//;s/"//') 2>/dev/null || true

  if [[ -z "$ver" ]]; then
    ver=$(curl -sf "https://gitea.com/api/v1/repos/gitea/act_runner/releases?limit=1" \
          | grep -o '"tag_name":"[^"]*"' | head -1 \
          | sed 's/.*:"//;s/"//') 2>/dev/null || true
  fi

  echo "${ver:-v1.0.0}"
}

# --------------------------------------------------------------------------- #
# Docker 检测与安装
# --------------------------------------------------------------------------- #
setup_docker() {
  step "检测 Docker 环境"

  if command -v docker &>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
    success "Docker 已安装且正在运行: $(docker --version)"
    return 0
  fi

  if command -v docker &>/dev/null && ! systemctl is-active --quiet docker 2>/dev/null; then
    warn "Docker 已安装但服务未运行，尝试启动..."
    systemctl enable --now docker \
      && success "Docker 服务启动成功。" \
      || error "Docker 服务启动失败，请手动检查: systemctl status docker"
    return 0
  fi

  # Docker 未安装，询问是否自动安装
  warn "未检测到 Docker。"
  echo -e "  Runner 默认使用 Docker 运行 CI 任务，强烈建议安装。"
  echo -e "  如果你打算使用 host 模式（直接在宿主机执行），可以跳过。\n"
  read -rp "$(echo -e "${BOLD}是否自动安装 Docker？[Y/n]: ${RESET}")" INSTALL_DOCKER
  case "${INSTALL_DOCKER,,}" in
    n|no)
      warn "跳过 Docker 安装。如需使用 Docker 模式，请事后手动安装并将 gitea-runner 加入 docker 组。"
      DOCKER_INSTALLED=false
      return 0
      ;;
    *)
      ;;
  esac

  info "正在通过官方脚本安装 Docker..."
  curl -fsSL https://get.docker.com | bash \
    || error "Docker 安装失败，请检查网络或手动安装: https://docs.docker.com/engine/install/"

  systemctl enable --now docker \
    && success "Docker 安装并启动成功: $(docker --version)" \
    || error "Docker 服务启动失败，请手动检查: systemctl status docker"
}

# --------------------------------------------------------------------------- #
# Banner
# --------------------------------------------------------------------------- #
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║         Gitea Runner 一键安装脚本  v1.3.0             ║"
echo "  ║  https://github.com/phil616/install-gitea-runner      ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# --------------------------------------------------------------------------- #
# 交互式输入
# --------------------------------------------------------------------------- #
step "配置信息收集"
echo -e "请依次输入以下信息（直接回车使用方括号内的默认值）：\n"

# 1. Gitea 实例 URL
read -rp "$(echo -e "${BOLD}[1/5]${RESET} Gitea 实例 URL（例: https://gitea.example.com）: ")" GITEA_URL
[[ -z "$GITEA_URL" ]] && error "Gitea 实例 URL 不能为空。"
GITEA_URL="${GITEA_URL%/}"

# 2. Runner 注册 Token（明文显示）
echo -e "      ${YELLOW}提示: 在 Gitea 管理面板 -> Actions -> Runners 页面获取 Token${RESET}"
read -rp "$(echo -e "${BOLD}[2/5]${RESET} Runner 注册 Token: ")" RUNNER_TOKEN
[[ -z "$RUNNER_TOKEN" ]] && error "Runner Token 不能为空。"

# 3. Runner 名称
DEFAULT_NAME="$(hostname -s)-runner"
read -rp "$(echo -e "${BOLD}[3/5]${RESET} Runner 名称 [默认: ${DEFAULT_NAME}]: ")" RUNNER_NAME
RUNNER_NAME="${RUNNER_NAME:-$DEFAULT_NAME}"

# 4. Runner Labels
DEFAULT_LABELS="ubuntu-latest:docker://node:20-bullseye,ubuntu-22.04:docker://node:20-bullseye,linux/amd64:host"
read -rp "$(echo -e "${BOLD}[4/5]${RESET} Runner Labels [回车使用默认]: ")" RUNNER_LABELS
RUNNER_LABELS="${RUNNER_LABELS:-$DEFAULT_LABELS}"

# 5. 安装版本
LATEST_VERSION="$(get_latest_version)"
read -rp "$(echo -e "${BOLD}[5/5]${RESET} 安装版本 [默认: ${LATEST_VERSION}]: ")" RUNNER_VERSION
RUNNER_VERSION="${RUNNER_VERSION:-$LATEST_VERSION}"
RUNNER_VERSION="${RUNNER_VERSION#v}"

# --------------------------------------------------------------------------- #
# 确认摘要
# --------------------------------------------------------------------------- #
echo -e "\n${BOLD}─────────────────── 安装摘要 ───────────────────${RESET}"
echo -e "  Gitea URL   : ${CYAN}${GITEA_URL}${RESET}"
echo -e "  Token       : ${CYAN}${RUNNER_TOKEN}${RESET}"
echo -e "  Runner 名称 : ${CYAN}${RUNNER_NAME}${RESET}"
echo -e "  Labels      : ${CYAN}${RUNNER_LABELS}${RESET}"
echo -e "  版本        : ${CYAN}v${RUNNER_VERSION}${RESET}"
echo -e "  架构        : ${CYAN}${ARCH}${RESET}"
echo -e "  安装路径    : /usr/local/bin/gitea-runner"
echo -e "  工作目录    : /var/lib/gitea-runner"
echo -e "  配置目录    : /etc/gitea-runner"
echo -e "  日志        : journald (journalctl -u gitea-runner)"
echo -e "${BOLD}────────────────────────────────────────────────${RESET}"

read -rp $'\n确认安装？[Y/n]: ' CONFIRM
case "${CONFIRM,,}" in
  n|no) echo "已取消。"; exit 0 ;;
  *)    ;;
esac

# --------------------------------------------------------------------------- #
# Docker 检测（在确认安装后执行，避免无效询问）
# --------------------------------------------------------------------------- #
DOCKER_INSTALLED=true
setup_docker

# --------------------------------------------------------------------------- #
# 下载二进制
# --------------------------------------------------------------------------- #
step "下载 Gitea Runner v${RUNNER_VERSION} (${ARCH})"

if [[ "$(printf '%s\n' "1.0.0" "${RUNNER_VERSION}" | sort -V | head -1)" == "1.0.0" ]]; then
  DL_URL="https://gitea.com/gitea/runner/releases/download/v${RUNNER_VERSION}/gitea-runner-${RUNNER_VERSION}-linux-${ARCH}"
else
  DL_URL="https://dl.gitea.com/act_runner/v${RUNNER_VERSION}/act_runner-${RUNNER_VERSION}-linux-${ARCH}"
fi

TMP_BIN="$(mktemp)"
info "下载地址: ${DL_URL}"

if ! curl -fsSL --retry 3 --retry-delay 2 -o "$TMP_BIN" "$DL_URL"; then
  ALT_URL="https://dl.gitea.com/act_runner/${RUNNER_VERSION}/act_runner-${RUNNER_VERSION}-linux-${ARCH}"
  warn "主下载地址失败，尝试备用地址: ${ALT_URL}"
  curl -fsSL --retry 3 --retry-delay 2 -o "$TMP_BIN" "$ALT_URL" \
    || error "下载失败，请检查版本号（v${RUNNER_VERSION}）或网络连接是否正常。"
fi

install -m 0755 "$TMP_BIN" /usr/local/bin/gitea-runner
rm -f "$TMP_BIN"

ACTUAL_VER="$(/usr/local/bin/gitea-runner --version 2>&1 | head -1 || true)"
success "二进制安装完成: ${ACTUAL_VER}"

# --------------------------------------------------------------------------- #
# 创建系统用户
# --------------------------------------------------------------------------- #
step "创建系统用户 gitea-runner"

if id "gitea-runner" &>/dev/null; then
  warn "用户 gitea-runner 已存在，跳过创建。"
else
  useradd \
    --system \
    --no-create-home \
    --home-dir /var/lib/gitea-runner \
    --shell /sbin/nologin \
    --comment "Gitea Runner Service" \
    gitea-runner
  success "用户 gitea-runner 创建成功。"
fi

# --------------------------------------------------------------------------- #
# 将 gitea-runner 加入 docker 组
# --------------------------------------------------------------------------- #
step "配置 Docker 访问权限"

if [[ "$DOCKER_INSTALLED" == true ]]; then
  if getent group docker &>/dev/null; then
    if id -nG gitea-runner | grep -qw docker; then
      warn "gitea-runner 已在 docker 组中，跳过。"
    else
      usermod -aG docker gitea-runner
      success "已将 gitea-runner 加入 docker 组（-aG 追加，不影响已有组）。"
    fi
  else
    warn "docker 组不存在，跳过（Docker 安装可能未完成）。"
  fi
else
  warn "Docker 未安装，跳过 docker 组配置。如需后续添加，执行: usermod -aG docker gitea-runner"
fi

# --------------------------------------------------------------------------- #
# 创建目录
# --------------------------------------------------------------------------- #
step "创建工作目录与配置目录"

install -d -m 750 -o gitea-runner -g gitea-runner /var/lib/gitea-runner
install -d -m 750 -o gitea-runner -g gitea-runner /etc/gitea-runner

success "目录创建完成。"

# --------------------------------------------------------------------------- #
# 生成配置文件
# --------------------------------------------------------------------------- #
step "生成 Runner 配置文件"

CONFIG_FILE="/etc/gitea-runner/config.yaml"

if [[ -f "$CONFIG_FILE" ]]; then
  warn "配置文件已存在，跳过生成（保留现有配置）: ${CONFIG_FILE}"
else
  /usr/local/bin/gitea-runner generate-config > "$CONFIG_FILE" 2>/dev/null || true

  if [[ ! -s "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'YAML'
log:
  level: info

runner:
  capacity: 2
  timeout: 3h
  insecure: false

cache:
  enabled: true

container:
  network: bridge
  privileged: false
  options:
  workdir_parent:
YAML
  fi

  chown gitea-runner:gitea-runner "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"
  success "配置文件已生成: ${CONFIG_FILE}"
fi

# --------------------------------------------------------------------------- #
# 注册 Runner
# --------------------------------------------------------------------------- #
step "注册 Runner 到 Gitea 实例"

RUNNER_FILE="/var/lib/gitea-runner/.runner"

if [[ -f "$RUNNER_FILE" ]]; then
  warn ".runner 注册文件已存在，跳过注册。如需重新注册请先删除: ${RUNNER_FILE}"
else
  info "正在向 ${GITEA_URL} 注册 Runner..."

  # 以 root 身份切换到工作目录执行注册。
  # .runner 会写入当前目录（/var/lib/gitea-runner），注册后再 chown 给专用用户。
  (
    cd /var/lib/gitea-runner
    /usr/local/bin/gitea-runner register \
      --no-interactive \
      --instance "$GITEA_URL" \
      --token    "$RUNNER_TOKEN" \
      --name     "$RUNNER_NAME" \
      --labels   "$RUNNER_LABELS" \
      --config   "$CONFIG_FILE"
  ) 2>&1 | tee /tmp/gitea-runner-register.log

  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    error "注册失败，请检查以下内容：\n  - Gitea URL 是否正确: ${GITEA_URL}\n  - Token 是否有效（未过期、未被重置）\n  - 网络是否可以访问 Gitea 实例\n  详细日志: /tmp/gitea-runner-register.log"
  fi

  if [[ ! -f "$RUNNER_FILE" ]]; then
    error "注册命令执行成功但未生成 .runner 文件，请查看日志: /tmp/gitea-runner-register.log"
  fi

  chown gitea-runner:gitea-runner "$RUNNER_FILE"
  chmod 600 "$RUNNER_FILE"
  success "Runner 注册成功，凭据文件: ${RUNNER_FILE}"
fi

# --------------------------------------------------------------------------- #
# 创建 systemd 服务文件
# --------------------------------------------------------------------------- #
step "创建 systemd 服务"

cat > /etc/systemd/system/gitea-runner.service <<EOF
[Unit]
Description=Gitea Actions Runner
Documentation=https://gitea.com/gitea/runner
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=gitea-runner
Group=gitea-runner
WorkingDirectory=/var/lib/gitea-runner

ExecStart=/usr/local/bin/gitea-runner daemon --config /etc/gitea-runner/config.yaml
ExecReload=/bin/kill -s HUP \$MAINPID

Restart=always
RestartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

StandardOutput=journal
StandardError=journal
SyslogIdentifier=gitea-runner

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/gitea-runner /etc/gitea-runner /tmp

Environment=HOME=/var/lib/gitea-runner

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/gitea-runner.service
success "systemd 服务文件创建完成: /etc/systemd/system/gitea-runner.service"

# --------------------------------------------------------------------------- #
# 配置 journald 日志持久化
# --------------------------------------------------------------------------- #
step "配置 journald 日志持久化"

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-gitea-runner.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=200M
SystemKeepFree=100M
MaxRetentionSec=30day
EOF

success "日志持久化配置完成（保留 30 天，上限 200MB）。"

# --------------------------------------------------------------------------- #
# 启动服务
# --------------------------------------------------------------------------- #
step "启用并启动 gitea-runner 服务"

systemctl daemon-reload
systemctl enable gitea-runner.service
systemctl restart gitea-runner.service

sleep 3
if systemctl is-active --quiet gitea-runner.service; then
  success "gitea-runner 服务运行正常。"
else
  warn "服务启动后状态异常，请执行以下命令查看日志:\n  journalctl -u gitea-runner -n 50"
fi

# --------------------------------------------------------------------------- #
# 完成说明
# --------------------------------------------------------------------------- #
echo -e "\n${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║         Gitea Runner 安装完成                         ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${BOLD}── 服务管理 ─────────────────────────────────────────────${RESET}"
echo -e "  启动   ${CYAN}systemctl start   gitea-runner${RESET}"
echo -e "  停止   ${CYAN}systemctl stop    gitea-runner${RESET}"
echo -e "  重启   ${CYAN}systemctl restart gitea-runner${RESET}"
echo -e "  状态   ${CYAN}systemctl status  gitea-runner${RESET}"
echo -e "  自启   ${CYAN}systemctl enable  gitea-runner${RESET}  ${GREEN}(已启用)${RESET}"

echo -e "\n${BOLD}── 查看日志 ─────────────────────────────────────────────${RESET}"
echo -e "  实时跟踪   ${CYAN}journalctl -u gitea-runner -f${RESET}"
echo -e "  最近100行  ${CYAN}journalctl -u gitea-runner -n 100${RESET}"
echo -e "  今日日志   ${CYAN}journalctl -u gitea-runner --since today${RESET}"
echo -e "  只看错误   ${CYAN}journalctl -u gitea-runner -p err${RESET}"

echo -e "\n${BOLD}── 重要文件 ─────────────────────────────────────────────${RESET}"
echo -e "  配置文件   ${CYAN}/etc/gitea-runner/config.yaml${RESET}"
echo -e "  注册凭据   ${CYAN}/var/lib/gitea-runner/.runner${RESET}"
echo -e "  服务文件   ${CYAN}/etc/systemd/system/gitea-runner.service${RESET}"

echo -e "\n${BOLD}── 重新注册 ─────────────────────────────────────────────${RESET}"
echo -e "  ${YELLOW}删除凭据文件后重新运行本脚本即可:${RESET}"
echo -e "  ${CYAN}rm /var/lib/gitea-runner/.runner && bash install-gitea-runner.sh${RESET}"

echo -e "\n${BOLD}── 验证 Runner 状态 ─────────────────────────────────────${RESET}"
echo -e "  访问: ${CYAN}${GITEA_URL}/-/admin/actions/runners${RESET}"
echo -e "  Runner ${GREEN}${RUNNER_NAME}${RESET} 应显示为 ${GREEN}Online${RESET} 状态。"

echo -e "\n${BOLD}── 卸载 ─────────────────────────────────────────────────${RESET}"
echo -e "  ${CYAN}systemctl stop gitea-runner && systemctl disable gitea-runner${RESET}"
echo -e "  ${CYAN}rm -f /etc/systemd/system/gitea-runner.service /usr/local/bin/gitea-runner${RESET}"
echo -e "  ${CYAN}rm -rf /var/lib/gitea-runner /etc/gitea-runner${RESET}"
echo -e "  ${CYAN}userdel gitea-runner && systemctl daemon-reload${RESET}"
echo ""
