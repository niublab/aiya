#!/bin/bash

# Element Server Suite (ESS) Community Edition 部署脚本
# 中文版本 - 基于安全和最佳实践改进
# 版本: 2.1
# 兼容 ESS-Helm Chart 25.6.0

# 严格错误处理
set -euo pipefail

# 脚本配置
SCRIPT_VERSION="2.1"
ESS_CHART_VERSION="25.6.0"
INSTALL_DIR="/opt/matrix"
CONFIG_DIR="${INSTALL_DIR}/config"
LOG_FILE="${INSTALL_DIR}/logs/setup.log"
NAMESPACE="ess"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # 无颜色

# 配置变量
DOMAIN_NAME=""
SYNAPSE_DOMAIN=""
AUTH_DOMAIN=""
RTC_DOMAIN=""
WEB_DOMAIN=""
CERT_EMAIL=""
ADMIN_EMAIL=""
CLOUDFLARE_API_TOKEN=""
CLOUDFLARE_ZONE_ID=""

# 必需端口
REQUIRED_PORTS=(80 443 30881 30882)

# 错误处理清理函数
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "脚本执行失败，退出代码: $exit_code"
        print_info "正在清理临时文件..."
        print_info "请查看日志: $LOG_FILE"
    fi
}

# 设置清理陷阱
trap cleanup EXIT

# 增强的日志函数
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 确保日志目录存在
    if [[ ! -d "$(dirname "$LOG_FILE")" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    fi
    
    # 只有在可以写入日志文件时才记录
    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]] 2>/dev/null; then
        echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 增强格式的打印函数
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    
    # 只有在日志可用时才记录
    if [[ -n "${LOG_FILE:-}" ]]; then
        log "$message"
    fi
}

print_title() {
    echo
    print_message "$CYAN" "=== $1 ==="
    echo
}

print_step() {
    print_message "$BLUE" "→ $1"
}

print_success() {
    print_message "$GREEN" "✓ $1"
}

print_error() {
    print_message "$RED" "✗ $1"
}

print_warning() {
    print_message "$YELLOW" "⚠ $1"
}

print_info() {
    print_message "$WHITE" "ℹ $1"
}

# 增强的错误退出函数
error_exit() {
    print_error "$1"
    
    # 只有在日志可用时才记录
    if [[ -n "${LOG_FILE:-}" ]]; then
        log "错误: $1"
    fi
    exit 1
}

# 进度显示函数
show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    printf "\r[%3d%%] %s" "$percent" "$desc"
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 网络操作重试机制
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "命令执行失败，第 $attempt/$max_attempts 次重试，${delay}秒后重试..."
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    print_error "命令在 $max_attempts 次尝试后仍然失败: $cmd"
    return 1
}

# 增强的命令检查
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 输入验证函数
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error_exit "域名格式无效: $domain"
    fi
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error_exit "邮箱格式无效: $email"
    fi
}

# 增强的目录创建，具有适当权限
create_directories() {
    print_step "创建安装目录..."
    
    # 使用适当的权限创建目录
    if [[ $EUID -eq 0 ]]; then
        # root用户直接创建
        mkdir -p "$INSTALL_DIR"
        mkdir -p "$CONFIG_DIR"
        mkdir -p "${INSTALL_DIR}/logs"
        mkdir -p "${INSTALL_DIR}/data"
        mkdir -p "${INSTALL_DIR}/backup"
    else
        # 非root用户使用sudo
        sudo mkdir -p "$INSTALL_DIR"
        sudo mkdir -p "$CONFIG_DIR"
        sudo mkdir -p "${INSTALL_DIR}/logs"
        sudo mkdir -p "${INSTALL_DIR}/data"
        sudo mkdir -p "${INSTALL_DIR}/backup"
    fi
    
    # 设置适当的所有权和权限
    if [[ $EUID -eq 0 ]]; then
        # root用户设置权限
        chmod 755 "$INSTALL_DIR"
        chmod 700 "$CONFIG_DIR"  # 配置文件更严格的权限
        chmod 755 "${INSTALL_DIR}/logs"
        chmod 755 "${INSTALL_DIR}/data"
        chmod 755 "${INSTALL_DIR}/backup"
    else
        # 非root用户使用sudo并设置用户所有权
        sudo chown -R "$USER:$USER" "$INSTALL_DIR"
        chmod 755 "$INSTALL_DIR"
        chmod 700 "$CONFIG_DIR"
        chmod 755 "${INSTALL_DIR}/logs"
        chmod 755 "${INSTALL_DIR}/data"
        chmod 755 "${INSTALL_DIR}/backup"
    fi
    
    # 确保可以创建日志文件
    touch "$LOG_FILE" 2>/dev/null || {
        if [[ $EUID -eq 0 ]]; then
            touch "$LOG_FILE"
        else
            sudo touch "$LOG_FILE"
            sudo chown "$USER:$USER" "$LOG_FILE" 2>/dev/null || true
        fi
    }
    
    print_success "目录创建成功"
}

# 安全配置文件权限
secure_config_files() {
    print_step "设置配置文件安全权限..."
    
    if [[ -d "$CONFIG_DIR" ]]; then
        find "$CONFIG_DIR" -name "*.yaml" -exec chmod 600 {} \;
        if [[ $EUID -ne 0 ]]; then
            find "$CONFIG_DIR" -name "*.yaml" -exec chown "$USER:$USER" {} \;
        fi
        print_success "配置文件权限设置完成"
    fi
}

# 带版本信息的欢迎消息
show_welcome() {
    clear
    print_title "Element Server Suite Community Edition 部署脚本"
    print_info "脚本版本: $SCRIPT_VERSION"
    print_info "目标 ESS Chart 版本: $ESS_CHART_VERSION"
    print_info "基于项目: https://github.com/element-hq/ess-helm"
    echo
    print_info "此脚本将使用 Kubernetes (K3s) 和 Helm 部署 Element Server Suite Community Edition"
    print_info "采用增强的安全性和最佳实践。"
    echo
    print_warning "请确保您具备以下条件:"
    print_info "  • 干净的 Debian 系列系统"
    print_info "  • 至少 2 CPU 核心和 2GB 内存"
    print_info "  • 5GB+ 可用磁盘空间"
    print_info "  • 在 DNS 中配置的域名"
    print_info "  • Let's Encrypt 证书的邮箱"
    echo
    
    read -p "按 Enter 继续或 Ctrl+C 退出..."
}

# 增强的系统要求检查
check_system() {
    print_title "系统要求检查"
    
    # 检查操作系统
    if [[ ! -f /etc/debian_version ]]; then
        error_exit "此脚本仅支持 Debian 系列系统"
    fi
    print_success "操作系统: Debian 系列 ✓"
    
    # 检查用户（现在允许root）
    if [[ $EUID -eq 0 ]]; then
        print_warning "检测到 root 用户，将以 root 权限运行"
        print_success "用户检查: root 用户 ✓"
    else
        print_success "用户检查: 非 root 用户 ✓"
        
        # 检查 sudo 权限
        if ! sudo -n true 2>/dev/null; then
            print_warning "需要 sudo 权限，请输入密码:"
            sudo -v || error_exit "无法获取 sudo 权限"
        fi
        print_success "Sudo 权限: 可用 ✓"
    fi
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "网络连接失败，请检查网络设置"
    fi
    print_success "网络连接: 可用 ✓"
    
    # 检查磁盘空间（最少 5GB）
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB in KB
        error_exit "磁盘空间不足，至少需要 5GB 可用空间"
    fi
    print_success "磁盘空间: 充足 ✓"
    
    # 检查内存（最少 2GB）
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 1800 ]]; then  # 允许一些余量
        print_warning "系统内存少于 2GB，性能可能受到影响"
    else
        print_success "内存: 充足 ✓"
    fi
    
    # 检查 CPU 核心（最少 2 个）
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        print_warning "系统 CPU 核心少于 2 个，性能可能受到影响"
    else
        print_success "CPU 核心: 充足 ✓"
    fi
}

# 网络要求检查
check_network_requirements() {
    print_title "网络要求检查"
    
    print_step "检查端口可用性..."
    for port in "${REQUIRED_PORTS[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            error_exit "端口 $port 已被占用，请先释放后继续"
        fi
        print_success "端口 $port: 可用 ✓"
    done
    
    print_step "检查 DNS 解析..."
    if [[ -n "$DOMAIN_NAME" ]]; then
        if ! nslookup "$DOMAIN_NAME" &>/dev/null; then
            print_warning "域名 $DOMAIN_NAME 无法解析，请确保 DNS 配置正确"
        else
            print_success "域名解析: $DOMAIN_NAME ✓"
        fi
    fi
}

# 使用多种方法获取公网 IP
get_public_ip() {
    print_step "检测公网 IP 地址..."
    
    local ip=""
    local methods=(
        "curl -s https://ipv4.icanhazip.com"
        "curl -s https://api.ipify.org"
        "curl -s https://checkip.amazonaws.com"
        "dig +short myip.opendns.com @resolver1.opendns.com"
    )
    
    for method in "${methods[@]}"; do
        if ip=$(timeout 10 $method 2>/dev/null) && [[ -n "$ip" ]]; then
            # 验证 IP 格式
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_success "检测到公网 IP: $ip"
                echo "$ip"
                return 0
            fi
        fi
    done
    
    print_warning "无法自动检测公网 IP"
    return 1
}

# 增强的域名配置，带验证
configure_domains() {
    print_title "域名配置"
    
    print_info "您需要为 ESS Community 配置 5 个域名:"
    print_info "1. 服务器名称（主域名）"
    print_info "2. Synapse 服务器"
    print_info "3. 认证服务"
    print_info "4. RTC 后端"
    print_info "5. Element Web 客户端"
    echo
    
    # 获取公网 IP
    local public_ip
    if public_ip=$(get_public_ip); then
        print_info "请确保所有域名都指向: $public_ip"
        echo
    fi
    
    # 服务器名称（主域名）
    while [[ -z "$DOMAIN_NAME" ]]; do
        read -p "输入服务器名称 (例如: matrix.example.com): " DOMAIN_NAME
        if [[ -n "$DOMAIN_NAME" ]]; then
            validate_domain "$DOMAIN_NAME"
        fi
    done
    
    # Synapse 域名
    while [[ -z "$SYNAPSE_DOMAIN" ]]; do
        read -p "输入 Synapse 域名 (例如: synapse.example.com): " SYNAPSE_DOMAIN
        if [[ -n "$SYNAPSE_DOMAIN" ]]; then
            validate_domain "$SYNAPSE_DOMAIN"
        fi
    done
    
    # 认证域名
    while [[ -z "$AUTH_DOMAIN" ]]; do
        read -p "输入认证服务域名 (例如: auth.example.com): " AUTH_DOMAIN
        if [[ -n "$AUTH_DOMAIN" ]]; then
            validate_domain "$AUTH_DOMAIN"
        fi
    done
    
    # RTC 域名
    while [[ -z "$RTC_DOMAIN" ]]; do
        read -p "输入 RTC 后端域名 (例如: rtc.example.com): " RTC_DOMAIN
        if [[ -n "$RTC_DOMAIN" ]]; then
            validate_domain "$RTC_DOMAIN"
        fi
    done
    
    # Web 客户端域名
    while [[ -z "$WEB_DOMAIN" ]]; do
        read -p "输入 Element Web 域名 (例如: chat.example.com): " WEB_DOMAIN
        if [[ -n "$WEB_DOMAIN" ]]; then
            validate_domain "$WEB_DOMAIN"
        fi
    done
    
    print_success "域名配置完成"
}

# 增强的端口配置
configure_ports() {
    print_title "端口配置"
    
    print_info "ESS Community 需要以下端口:"
    print_info "• TCP 80: HTTP (重定向到 HTTPS)"
    print_info "• TCP 443: HTTPS"
    print_info "• TCP 30881: WebRTC TCP 连接"
    print_info "• UDP 30882: WebRTC UDP 连接"
    echo
    
    print_step "生成端口配置..."
    cat > "${CONFIG_DIR}/ports.yaml" << EOF
# ESS Community 端口配置
global:
  ports:
    http: 80
    https: 443
    webrtc:
      tcp: 30881
      udp: 30882

# 服务特定端口配置
services:
  traefik:
    ports:
      web:
        port: 80
        exposedPort: 80
      websecure:
        port: 443
        exposedPort: 443
  
  matrixRtcBackend:
    ports:
      webrtc:
        tcp: 30881
        udp: 30882
EOF
    
    print_success "端口配置生成完成"
}

# 增强选项的证书配置
configure_certificates() {
    print_title "证书配置"
    
    print_info "选择证书配置方法:"
    print_info "1. Let's Encrypt (自动，推荐)"
    print_info "2. 现有通配符证书"
    print_info "3. 单独证书"
    print_info "4. 外部反向代理 (集群中无 TLS)"
    echo
    
    local cert_choice
    while [[ ! "$cert_choice" =~ ^[1-4]$ ]]; do
        read -p "选择选项 (1-4): " cert_choice
    done
    
    case $cert_choice in
        1)
            configure_letsencrypt
            ;;
        2)
            configure_wildcard_cert
            ;;
        3)
            configure_individual_certs
            ;;
        4)
            configure_external_proxy
            ;;
    esac
}

# Let's Encrypt 配置
configure_letsencrypt() {
    print_step "配置 Let's Encrypt..."
    
    while [[ -z "$CERT_EMAIL" ]]; do
        read -p "输入 Let's Encrypt 证书邮箱: " CERT_EMAIL
        if [[ -n "$CERT_EMAIL" ]]; then
            validate_email "$CERT_EMAIL"
        fi
    done
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# Let's Encrypt TLS 配置
global:
  tls:
    mode: letsencrypt
    letsencrypt:
      email: "$CERT_EMAIL"
      server: https://acme-v02.api.letsencrypt.org/directory
      
# 证书颁发者配置
certManager:
  enabled: true
  issuer:
    name: letsencrypt-prod
    email: "$CERT_EMAIL"
    server: https://acme-v02.api.letsencrypt.org/directory
    
# Ingress TLS 配置
ingress:
  tls:
    enabled: true
    issuer: letsencrypt-prod
EOF
    
    print_success "Let's Encrypt 配置完成"
}

# 通配符证书配置
configure_wildcard_cert() {
    print_step "配置通配符证书..."
    
    print_info "请确保您的通配符证书覆盖:"
    print_info "• $DOMAIN_NAME"
    print_info "• $SYNAPSE_DOMAIN"
    print_info "• $AUTH_DOMAIN"
    print_info "• $RTC_DOMAIN"
    print_info "• $WEB_DOMAIN"
    echo
    
    local cert_path key_path
    read -p "输入证书文件路径: " cert_path
    read -p "输入私钥文件路径: " key_path
    
    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        error_exit "证书或密钥文件未找到"
    fi
    
    # 将证书导入 Kubernetes
    if [[ $EUID -eq 0 ]]; then
        kubectl create secret tls ess-certificate -n "$NAMESPACE" \
            --cert="$cert_path" --key="$key_path" || error_exit "导入证书失败"
    else
        sudo k3s kubectl create secret tls ess-certificate -n "$NAMESPACE" \
            --cert="$cert_path" --key="$key_path" || error_exit "导入证书失败"
    fi
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# 通配符证书 TLS 配置
global:
  tls:
    mode: existing
    secretName: ess-certificate
    
# Ingress TLS 配置
ingress:
  tls:
    enabled: true
    secretName: ess-certificate
EOF
    
    print_success "通配符证书配置完成"
}

# 单独证书配置
configure_individual_certs() {
    print_step "配置单独证书..."
    
    print_info "您需要为每个域名单独的证书"
    
    local domains=("$WEB_DOMAIN" "$SYNAPSE_DOMAIN" "$AUTH_DOMAIN" "$RTC_DOMAIN" "$DOMAIN_NAME")
    local secrets=("ess-chat-certificate" "ess-matrix-certificate" "ess-auth-certificate" "ess-rtc-certificate" "ess-well-known-certificate")
    
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local secret="${secrets[$i]}"
        
        print_step "为 $domain 配置证书..."
        
        local cert_path key_path
        read -p "输入 $domain 的证书文件路径: " cert_path
        read -p "输入 $domain 的私钥文件路径: " key_path
        
        if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
            error_exit "$domain 的证书或密钥文件未找到"
        fi
        
        if [[ $EUID -eq 0 ]]; then
            kubectl create secret tls "$secret" -n "$NAMESPACE" \
                --cert="$cert_path" --key="$key_path" || error_exit "$domain 证书导入失败"
        else
            sudo k3s kubectl create secret tls "$secret" -n "$NAMESPACE" \
                --cert="$cert_path" --key="$key_path" || error_exit "$domain 证书导入失败"
        fi
    done
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# 单独证书 TLS 配置
global:
  tls:
    mode: individual
    
# 服务特定 TLS 配置
services:
  elementWeb:
    tls:
      secretName: ess-chat-certificate
  synapse:
    tls:
      secretName: ess-matrix-certificate
  matrixAuthenticationService:
    tls:
      secretName: ess-auth-certificate
  matrixRtcBackend:
    tls:
      secretName: ess-rtc-certificate
  wellKnown:
    tls:
      secretName: ess-well-known-certificate
EOF
    
    print_success "单独证书配置完成"
}

# 外部代理配置
configure_external_proxy() {
    print_step "配置外部反向代理..."
    
    print_info "选择了外部反向代理配置"
    print_info "TLS 将在反向代理级别终止"
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# 外部反向代理 TLS 配置
global:
  tls:
    mode: disabled
    
# 外部代理的 Ingress 配置
ingress:
  tls:
    enabled: false
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.entrypoints: web
EOF
    
    print_success "外部代理配置完成"
}

# 安装配置
configure_installation() {
    print_title "安装配置"
    
    while [[ -z "$ADMIN_EMAIL" ]]; do
        read -p "输入管理员邮箱: " ADMIN_EMAIL
        if [[ -n "$ADMIN_EMAIL" ]]; then
            validate_email "$ADMIN_EMAIL"
        fi
    done
    
    print_success "安装配置完成"
}

# 配置摘要
show_configuration_summary() {
    print_title "配置摘要"
    
    print_info "安装目录: $INSTALL_DIR"
    print_info "命名空间: $NAMESPACE"
    print_info "ESS Chart 版本: $ESS_CHART_VERSION"
    echo
    print_info "域名配置:"
    print_info "  服务器名称: $DOMAIN_NAME"
    print_info "  Synapse: $SYNAPSE_DOMAIN"
    print_info "  认证服务: $AUTH_DOMAIN"
    print_info "  RTC 后端: $RTC_DOMAIN"
    print_info "  Element Web: $WEB_DOMAIN"
    echo
    print_info "管理员邮箱: $ADMIN_EMAIL"
    if [[ -n "$CERT_EMAIL" ]]; then
        print_info "证书邮箱: $CERT_EMAIL"
    fi
    echo
    
    read -p "继续使用此配置? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "配置已取消"
        exit 0
    fi
}

# 保存配置到文件
save_configuration() {
    print_step "保存配置..."
    
    cat > "${CONFIG_DIR}/main.yaml" << EOF
# ESS Community 主配置
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION

metadata:
  version: "$SCRIPT_VERSION"
  chartVersion: "$ESS_CHART_VERSION"
  generatedAt: "$(date -Iseconds)"
  
installation:
  directory: "$INSTALL_DIR"
  namespace: "$NAMESPACE"
  
domains:
  serverName: "$DOMAIN_NAME"
  synapse: "$SYNAPSE_DOMAIN"
  authentication: "$AUTH_DOMAIN"
  rtcBackend: "$RTC_DOMAIN"
  elementWeb: "$WEB_DOMAIN"
  
contacts:
  adminEmail: "$ADMIN_EMAIL"
  certEmail: "$CERT_EMAIL"
  
network:
  requiredPorts: [${REQUIRED_PORTS[*]}]
EOF
    
    secure_config_files
    print_success "配置已保存到 ${CONFIG_DIR}/main.yaml"
}

# 增强的依赖安装，带重试
install_dependencies() {
    print_title "安装依赖"
    
    print_step "更新软件包列表..."
    if [[ $EUID -eq 0 ]]; then
        retry_command "apt-get update" 3 5
    else
        retry_command "sudo apt-get update" 3 5
    fi
    
    local packages=(
        "curl"
        "wget"
        "gnupg"
        "lsb-release"
        "ca-certificates"
        "apt-transport-https"
        "software-properties-common"
        "dnsutils"
        "net-tools"
        "jq"
    )
    
    print_step "安装必需软件包..."
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            print_step "安装 $package..."
            if [[ $EUID -eq 0 ]]; then
                retry_command "apt-get install -y $package" 3 5
            else
                retry_command "sudo apt-get install -y $package" 3 5
            fi
        else
            print_success "$package 已安装"
        fi
    done
    
    print_success "依赖安装完成"
}

# 增强配置的 K3s 安装
install_k3s() {
    print_title "安装 K3s"
    
    if check_command k3s; then
        print_success "K3s 已安装"
        return 0
    fi
    
    print_step "安装 K3s..."
    local k3s_config="--default-local-storage-path=${INSTALL_DIR}/data/k3s-storage"
    k3s_config+=" --disable=traefik"  # 我们将单独配置 Traefik
    
    retry_command "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"server ${k3s_config}\" sh -" 3 10
    
    print_step "配置 kubectl 访问..."
    mkdir -p ~/.kube
    export KUBECONFIG=~/.kube/config
    
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl config view --raw > "$KUBECONFIG"
    else
        sudo k3s kubectl config view --raw > "$KUBECONFIG"
        chown "$USER:$USER" "$KUBECONFIG"
    fi
    chmod 600 "$KUBECONFIG"
    
    # 添加到 bashrc 以持久化
    if ! grep -q "export KUBECONFIG=~/.kube/config" ~/.bashrc; then
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
    fi
    
    print_step "等待 K3s 就绪..."
    local retries=0
    while true; do
        if [[ $EUID -eq 0 ]]; then
            if k3s kubectl get nodes &>/dev/null; then
                break
            fi
        else
            if sudo k3s kubectl get nodes &>/dev/null; then
                break
            fi
        fi
        
        if [[ $retries -ge 30 ]]; then
            error_exit "K3s 启动超时"
        fi
        sleep 2
        ((retries++))
    done
    
    print_success "K3s 安装完成"
}

# 自定义端口的 Traefik 配置
configure_k3s_ports() {
    print_title "配置 K3s 网络"
    
    print_step "安装自定义配置的 Traefik..."
    
    if [[ $EUID -eq 0 ]]; then
        tee /var/lib/rancher/k3s/server/manifests/traefik-config.yaml > /dev/null << EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        port: 8080
        exposedPort: 80
      websecure:
        port: 8443
        exposedPort: 443
      webrtc-tcp:
        port: 30881
        exposedPort: 30881
        protocol: TCP
      webrtc-udp:
        port: 30882
        exposedPort: 30882
        protocol: UDP
    service:
      type: LoadBalancer
    additionalArguments:
      - "--entrypoints.webrtc-tcp.address=:30881/tcp"
      - "--entrypoints.webrtc-udp.address=:30882/udp"
EOF
    else
        sudo tee /var/lib/rancher/k3s/server/manifests/traefik-config.yaml > /dev/null << EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        port: 8080
        exposedPort: 80
      websecure:
        port: 8443
        exposedPort: 443
      webrtc-tcp:
        port: 30881
        exposedPort: 30881
        protocol: TCP
      webrtc-udp:
        port: 30882
        exposedPort: 30882
        protocol: UDP
    service:
      type: LoadBalancer
    additionalArguments:
      - "--entrypoints.webrtc-tcp.address=:30881/tcp"
      - "--entrypoints.webrtc-udp.address=:30882/udp"
EOF
    fi
    
    print_step "重启 K3s 以应用 Traefik 配置..."
    if [[ $EUID -eq 0 ]]; then
        systemctl restart k3s
    else
        sudo systemctl restart k3s
    fi
    
    # 等待 Traefik 就绪
    print_step "等待 Traefik 就绪..."
    local retries=0
    while true; do
        local traefik_running
        if [[ $EUID -eq 0 ]]; then
            traefik_running=$(k3s kubectl get pods -n kube-system | grep traefik | grep -c Running || true)
        else
            traefik_running=$(sudo k3s kubectl get pods -n kube-system | grep traefik | grep -c Running || true)
        fi
        
        if [[ $traefik_running -gt 0 ]]; then
            break
        fi
        
        if [[ $retries -ge 60 ]]; then
            error_exit "Traefik 启动超时"
        fi
        sleep 2
        ((retries++))
    done
    
    print_success "Traefik 配置完成"
}

# Helm 安装
install_helm() {
    print_title "安装 Helm"
    
    if check_command helm; then
        print_success "Helm 已安装"
        return 0
    fi
    
    print_step "安装 Helm..."
    retry_command "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" 3 10
    
    print_success "Helm 安装完成"
}

# 命名空间创建
create_namespace() {
    print_title "创建 Kubernetes 命名空间"
    
    print_step "创建命名空间: $NAMESPACE"
    local namespace_exists
    if [[ $EUID -eq 0 ]]; then
        namespace_exists=$(k3s kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "not_found")
    else
        namespace_exists=$(sudo k3s kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "not_found")
    fi
    
    if [[ "$namespace_exists" == "not_found" ]]; then
        if [[ $EUID -eq 0 ]]; then
            k3s kubectl create namespace "$NAMESPACE"
        else
            sudo k3s kubectl create namespace "$NAMESPACE"
        fi
        print_success "命名空间 '$NAMESPACE' 已创建"
    else
        print_success "命名空间 '$NAMESPACE' 已存在"
    fi
}

# 增强配置的 Cert-manager 安装
install_cert_manager() {
    print_title "安装 Cert-Manager"
    
    # 检查 cert-manager 是否已安装
    local cert_manager_exists
    if [[ $EUID -eq 0 ]]; then
        cert_manager_exists=$(k3s kubectl get namespace cert-manager 2>/dev/null || echo "not_found")
    else
        cert_manager_exists=$(sudo k3s kubectl get namespace cert-manager 2>/dev/null || echo "not_found")
    fi
    
    if [[ "$cert_manager_exists" != "not_found" ]]; then
        print_success "Cert-manager 已安装"
        return 0
    fi
    
    print_step "添加 Jetstack Helm 仓库..."
    retry_command "helm repo add jetstack https://charts.jetstack.io --force-update" 3 5
    
    print_step "更新 Helm 仓库..."
    retry_command "helm repo update" 3 5
    
    print_step "安装 cert-manager..."
    retry_command "helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.17.0 \
        --set crds.enabled=true \
        --wait \
        --timeout=10m" 3 10
    
    # 如果使用 Let's Encrypt，创建 ClusterIssuer
    if [[ -n "$CERT_EMAIL" ]]; then
        print_step "创建 Let's Encrypt ClusterIssuer..."
        if [[ $EUID -eq 0 ]]; then
            k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
        else
            sudo k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
        fi
    fi
    
    print_success "Cert-manager 安装完成"
}

# Cloudflare DNS 配置（可选）
configure_cloudflare_dns() {
    print_title "Cloudflare DNS 配置（可选）"
    
    print_info "您想配置 Cloudflare DNS 验证证书吗？"
    print_info "这对通配符证书或无法进行 HTTP 验证时很有用。"
    echo
    
    read -p "配置 Cloudflare DNS? (y/N): " use_cloudflare
    if [[ ! "$use_cloudflare" =~ ^[Yy]$ ]]; then
        print_info "跳过 Cloudflare DNS 配置"
        return 0
    fi
    
    read -p "输入 Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    read -p "输入 Cloudflare Zone ID: " CLOUDFLARE_ZONE_ID
    
    if [[ -z "$CLOUDFLARE_API_TOKEN" ]] || [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
        print_warning "未提供 Cloudflare 凭据，跳过 DNS 配置"
        return 0
    fi
    
    # 创建 Cloudflare secret
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl create secret generic cloudflare-api-token-secret \
            --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
            -n cert-manager
    else
        sudo k3s kubectl create secret generic cloudflare-api-token-secret \
            --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
            -n cert-manager
    fi
    
    # 创建 DNS ClusterIssuer
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-dns-prod-private-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - "$DOMAIN_NAME"
EOF
    else
        sudo k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-dns-prod-private-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - "$DOMAIN_NAME"
EOF
    fi
    
    print_success "Cloudflare DNS 验证已配置"
}

# 生成增强的 ESS 配置
generate_ess_config() {
    print_title "生成 ESS 配置文件"
    
    print_step "生成主机名配置..."
    cat > "${CONFIG_DIR}/hostnames.yaml" << EOF
# ESS Community 主机名配置
# 生成时间: $(date)

global:
  hosts:
    serverName: "$DOMAIN_NAME"
    synapse: "$SYNAPSE_DOMAIN"
    elementWeb: "$WEB_DOMAIN"
    matrixAuthenticationService: "$AUTH_DOMAIN"
    matrixRtcBackend: "$RTC_DOMAIN"
  
  # 服务器配置
  server:
    name: "$DOMAIN_NAME"
    
  # Well-known 委托
  wellKnown:
    enabled: true
    server: "$SYNAPSE_DOMAIN"
    
# 部署标记用于跟踪
deploymentMarkers:
  enabled: true
  version: "$ESS_CHART_VERSION"
  deployedAt: "$(date -Iseconds)"
  deployedBy: "$USER"
EOF
    
    print_step "生成资源配置..."
    cat > "${CONFIG_DIR}/resources.yaml" << EOF
# 资源限制和请求配置
# 为生产部署优化

global:
  resources:
    # 默认资源设置
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

# 服务特定资源配置
synapse:
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "4Gi"
      cpu: "2000m"
  
  # Synapse 特定配置
  config:
    workers:
      enabled: true
      count: 2
    
postgresql:
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
  
  # PostgreSQL 配置
  persistence:
    enabled: true
    size: 10Gi
    storageClass: "local-path"

matrixAuthenticationService:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"

matrixRtcBackend:
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

elementWeb:
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
      cpu: "200m"
EOF
    
    print_step "生成安全配置..."
    cat > "${CONFIG_DIR}/security.yaml" << EOF
# ESS Community 安全配置
# 实施安全最佳实践

global:
  # 所有 Pod 的安全上下文
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  
  # Pod 安全上下文
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  
  # 容器安全上下文
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000
    capabilities:
      drop:
        - ALL

# 网络策略
networkPolicy:
  enabled: true
  ingress:
    enabled: true
  egress:
    enabled: true

# Pod 中断预算
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# 服务网格配置（如果使用 Istio）
serviceMesh:
  enabled: false
  mtls:
    mode: STRICT
EOF
    
    print_step "生成监控配置..."
    cat > "${CONFIG_DIR}/monitoring.yaml" << EOF
# 监控和可观测性配置

# Prometheus 监控
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
  
  # Grafana 仪表板
  grafana:
    enabled: true
    dashboards:
      enabled: true
  
  # 告警规则
  prometheusRule:
    enabled: true
    rules:
      - alert: SynapseDown
        expr: up{job="synapse"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Synapse 已停机"
          description: "Synapse 已停机超过 5 分钟"

# 日志配置
logging:
  enabled: true
  level: INFO
  
  # 日志聚合
  fluentd:
    enabled: false
  
  # 日志保留
  retention:
    days: 30

# 健康检查
healthChecks:
  enabled: true
  livenessProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
  
  readinessProbe:
    enabled: true
    initialDelaySeconds: 5
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 3
  
  startupProbe:
    enabled: true
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30
EOF
    
    secure_config_files
    print_success "ESS 配置文件生成完成"
}

# 配置验证
validate_configuration() {
    print_title "验证配置"
    
    print_step "验证 YAML 语法..."
    for config_file in "${CONFIG_DIR}"/*.yaml; do
        if [[ -f "$config_file" ]]; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                error_exit "配置文件语法错误: $config_file"
            fi
            print_success "$(basename "$config_file"): 有效 ✓"
        fi
    done
    
    print_step "验证 Kubernetes 连接..."
    if [[ $EUID -eq 0 ]]; then
        if ! k3s kubectl cluster-info &>/dev/null; then
            error_exit "Kubernetes 集群不可访问"
        fi
    else
        if ! sudo k3s kubectl cluster-info &>/dev/null; then
            error_exit "Kubernetes 集群不可访问"
        fi
    fi
    print_success "Kubernetes 连接: 正常 ✓"
    
    print_step "验证 Helm 仓库..."
    if ! helm repo list | grep -q jetstack; then
        print_warning "未找到 Jetstack 仓库，正在添加..."
        helm repo add jetstack https://charts.jetstack.io --force-update
    fi
    print_success "Helm 仓库: 正常 ✓"
    
    print_success "配置验证完成"
}

# 增强的 ESS 部署
deploy_ess() {
    print_title "部署 ESS Community"
    
    validate_configuration
    
    print_step "使用 Helm 部署 Matrix Stack..."
    print_info "Chart 版本: $ESS_CHART_VERSION"
    print_info "命名空间: $NAMESPACE"
    
    # 准备包含所有配置文件的 Helm 命令
    local helm_cmd="helm upgrade --install --namespace \"$NAMESPACE\" ess"
    helm_cmd+=" oci://ghcr.io/element-hq/ess-helm/matrix-stack"
    helm_cmd+=" --version \"$ESS_CHART_VERSION\""
    helm_cmd+=" -f \"${CONFIG_DIR}/hostnames.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/tls.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/ports.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/resources.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/security.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/monitoring.yaml\""
    helm_cmd+=" --wait"
    helm_cmd+=" --timeout=20m"
    
    # 使用重试执行部署
    retry_command "$helm_cmd" 2 30
    
    print_step "等待所有 Pod 就绪..."
    local retries=0
    local max_retries=60
    
    while true; do
        local pending_pods
        if [[ $EUID -eq 0 ]]; then
            pending_pods=$(k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
        else
            pending_pods=$(sudo k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
        fi
        
        if [[ $pending_pods -eq 0 ]]; then
            break
        fi
        
        if [[ $retries -ge $max_retries ]]; then
            print_error "等待 Pod 就绪超时"
            if [[ $EUID -eq 0 ]]; then
                k3s kubectl get pods -n "$NAMESPACE"
            else
                sudo k3s kubectl get pods -n "$NAMESPACE"
            fi
            error_exit "部署超时"
        fi
        
        show_progress $retries $max_retries "等待 Pod 就绪... ($pending_pods 个待处理)"
        sleep 5
        ((retries++))
    done
    
    print_success "ESS Community 部署完成"
}

# 增强选项的创建初始用户
create_initial_user() {
    print_title "创建初始用户"
    
    print_info "ESS Community 默认不允许用户注册。"
    print_info "您需要创建一个初始管理员用户。"
    echo
    
    read -p "现在创建初始用户? (Y/n): " create_user
    if [[ "$create_user" =~ ^[Nn]$ ]]; then
        print_info "跳过用户创建。您可以稍后使用以下命令创建用户:"
        if [[ $EUID -eq 0 ]]; then
            print_info "kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
        else
            print_info "sudo k3s kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
        fi
        return 0
    fi
    
    print_step "创建初始用户..."
    print_info "按照提示创建您的管理员用户:"
    
    # 交互式用户创建
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl exec -n "$NAMESPACE" -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
    else
        sudo k3s kubectl exec -n "$NAMESPACE" -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
    fi
    
    print_success "初始用户创建完成"
}

# 备份功能
backup_configuration() {
    print_title "创建配置备份"
    
    local backup_dir="${INSTALL_DIR}/backup/config-$(date +%Y%m%d-%H%M%S)"
    print_step "创建备份目录: $backup_dir"
    
    mkdir -p "$backup_dir"
    cp -r "${CONFIG_DIR}"/* "$backup_dir/"
    
    # 创建备份元数据
    cat > "$backup_dir/backup-info.yaml" << EOF
# 备份信息
backupDate: "$(date -Iseconds)"
scriptVersion: "$SCRIPT_VERSION"
chartVersion: "$ESS_CHART_VERSION"
namespace: "$NAMESPACE"
domains:
  serverName: "$DOMAIN_NAME"
  synapse: "$SYNAPSE_DOMAIN"
  authentication: "$AUTH_DOMAIN"
  rtcBackend: "$RTC_DOMAIN"
  elementWeb: "$WEB_DOMAIN"
EOF
    
    # 设置安全权限
    chmod -R 600 "$backup_dir"
    if [[ $EUID -ne 0 ]]; then
        chown -R "$USER:$USER" "$backup_dir"
    fi
    
    print_success "配置备份已创建: $backup_dir"
}

# 数据库备份功能
backup_database() {
    print_title "创建数据库备份"
    
    local backup_file="${INSTALL_DIR}/backup/postgres-$(date +%Y%m%d-%H%M%S).sql"
    print_step "创建数据库备份: $backup_file"
    
    # 创建数据库备份
    local backup_success=false
    if [[ $EUID -eq 0 ]]; then
        if k3s kubectl exec -n "$NAMESPACE" deployment/ess-postgresql -- pg_dump -U synapse synapse > "$backup_file"; then
            backup_success=true
        fi
    else
        if sudo k3s kubectl exec -n "$NAMESPACE" deployment/ess-postgresql -- pg_dump -U synapse synapse > "$backup_file"; then
            backup_success=true
        fi
    fi
    
    if [[ "$backup_success" == "true" ]]; then
        chmod 600 "$backup_file"
        if [[ $EUID -ne 0 ]]; then
            chown "$USER:$USER" "$backup_file"
        fi
        print_success "数据库备份已创建: $backup_file"
    else
        print_error "数据库备份失败"
        return 1
    fi
}

# 增强的部署验证
verify_deployment() {
    print_title "验证部署"
    
    print_step "检查 Pod 状态..."
    local failed_pods
    if [[ $EUID -eq 0 ]]; then
        failed_pods=$(k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
    else
        failed_pods=$(sudo k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
    fi
    
    if [[ $failed_pods -gt 0 ]]; then
        print_error "一些 Pod 未运行:"
        if [[ $EUID -eq 0 ]]; then
            k3s kubectl get pods -n "$NAMESPACE"
        else
            sudo k3s kubectl get pods -n "$NAMESPACE"
        fi
        return 1
    fi
    print_success "所有 Pod 正在运行 ✓"
    
    print_step "检查服务端点..."
    local services=("ess-synapse" "ess-element-web" "ess-matrix-authentication-service")
    for service in "${services[@]}"; do
        local service_exists
        if [[ $EUID -eq 0 ]]; then
            service_exists=$(k3s kubectl get service "$service" -n "$NAMESPACE" 2>/dev/null || echo "not_found")
        else
            service_exists=$(sudo k3s kubectl get service "$service" -n "$NAMESPACE" 2>/dev/null || echo "not_found")
        fi
        
        if [[ "$service_exists" != "not_found" ]]; then
            print_success "服务 $service: 可用 ✓"
        else
            print_warning "服务 $service: 未找到"
        fi
    done
    
    print_step "检查 Ingress 配置..."
    local ingress_exists
    if [[ $EUID -eq 0 ]]; then
        ingress_exists=$(k3s kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "not_found")
    else
        ingress_exists=$(sudo k3s kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "not_found")
    fi
    
    if [[ "$ingress_exists" != "not_found" ]]; then
        print_success "Ingress 配置: 可用 ✓"
    else
        print_warning "Ingress 配置: 未找到"
    fi
    
    print_step "测试内部连接..."
    # 测试 Synapse 是否响应
    local synapse_health
    if [[ $EUID -eq 0 ]]; then
        synapse_health=$(k3s kubectl exec -n "$NAMESPACE" deployment/ess-synapse -- curl -s http://localhost:8008/health 2>/dev/null || echo "failed")
    else
        synapse_health=$(sudo k3s kubectl exec -n "$NAMESPACE" deployment/ess-synapse -- curl -s http://localhost:8008/health 2>/dev/null || echo "failed")
    fi
    
    if [[ "$synapse_health" != "failed" ]]; then
        print_success "Synapse 健康检查: 正常 ✓"
    else
        print_warning "Synapse 健康检查: 失败"
    fi
    
    print_success "部署验证完成"
}

# 增强的完成信息
show_completion_info() {
    print_title "部署成功完成！"
    
    print_success "ESS Community 已成功部署！"
    echo
    
    print_info "访问信息:"
    print_info "• Element Web 客户端: https://$WEB_DOMAIN"
    print_info "• 服务器名称: $DOMAIN_NAME"
    print_info "• Synapse 服务器: https://$SYNAPSE_DOMAIN"
    print_info "• 认证服务: https://$AUTH_DOMAIN"
    print_info "• RTC 后端: https://$RTC_DOMAIN"
    echo
    
    print_info "管理信息:"
    print_info "• 安装目录: $INSTALL_DIR"
    print_info "• 配置文件: $CONFIG_DIR"
    print_info "• Kubernetes 命名空间: $NAMESPACE"
    print_info "• 日志文件: $LOG_FILE"
    echo
    
    print_info "有用的命令:"
    if [[ $EUID -eq 0 ]]; then
        print_info "• 检查 Pod 状态: kubectl get pods -n $NAMESPACE"
        print_info "• 查看日志: kubectl logs -n $NAMESPACE deployment/ess-synapse"
        print_info "• 创建用户: kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
        print_info "• 备份数据库: kubectl exec -n $NAMESPACE deployment/ess-postgresql -- pg_dump -U synapse synapse > backup.sql"
    else
        print_info "• 检查 Pod 状态: sudo k3s kubectl get pods -n $NAMESPACE"
        print_info "• 查看日志: sudo k3s kubectl logs -n $NAMESPACE deployment/ess-synapse"
        print_info "• 创建用户: sudo k3s kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
        print_info "• 备份数据库: sudo k3s kubectl exec -n $NAMESPACE deployment/ess-postgresql -- pg_dump -U synapse synapse > backup.sql"
    fi
    echo
    
    print_info "下一步:"
    print_info "1. 测试联邦: https://federationtester.matrix.org/"
    print_info "2. 使用服务器配置 Element 客户端: $DOMAIN_NAME"
    print_info "3. 设置监控和告警"
    print_info "4. 配置定期备份"
    echo
    
    print_warning "安全建议:"
    print_info "• 定期更新 ESS Community"
    print_info "• 监控系统资源和日志"
    print_info "• 实施适当的备份策略"
    print_info "• 审查和更新安全配置"
    echo
    
    # 创建完成标记
    echo "$(date -Iseconds)" > "${INSTALL_DIR}/.deployment-completed"
    
    print_success "部署信息已保存。享受您的 Matrix 服务器！"
}

# 环境清理函数
cleanup_environment() {
    print_title "环境清理"
    
    print_warning "这将删除整个 ESS Community 安装！"
    print_warning "此操作无法撤销！"
    echo
    
    read -p "您确定要继续吗？(输入 'yes' 确认): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "清理已取消"
        return 0
    fi
    
    print_step "清理前创建最终备份..."
    backup_configuration
    backup_database
    
    print_step "删除 Helm 部署..."
    helm uninstall ess -n "$NAMESPACE" || true
    
    print_step "删除命名空间..."
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl delete namespace "$NAMESPACE" || true
    else
        sudo k3s kubectl delete namespace "$NAMESPACE" || true
    fi
    
    print_step "删除 cert-manager..."
    helm uninstall cert-manager -n cert-manager || true
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl delete namespace cert-manager || true
    else
        sudo k3s kubectl delete namespace cert-manager || true
    fi
    
    print_step "停止 K3s..."
    if [[ $EUID -eq 0 ]]; then
        systemctl stop k3s || true
    else
        sudo systemctl stop k3s || true
    fi
    
    read -p "完全删除 K3s? (y/N): " remove_k3s
    if [[ "$remove_k3s" =~ ^[Yy]$ ]]; then
        print_step "卸载 K3s..."
        if [[ $EUID -eq 0 ]]; then
            /usr/local/bin/k3s-uninstall.sh || true
        else
            sudo /usr/local/bin/k3s-uninstall.sh || true
        fi
    fi
    
    read -p "删除安装目录? (y/N): " remove_dir
    if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
        print_step "删除安装目录..."
        if [[ $EUID -eq 0 ]]; then
            rm -rf "$INSTALL_DIR"
        else
            sudo rm -rf "$INSTALL_DIR"
        fi
    fi
    
    print_success "环境清理完成"
}

# 重启服务函数
restart_services() {
    print_title "重启服务"
    
    print_step "重启 ESS Community 部署..."
    if [[ $EUID -eq 0 ]]; then
        k3s kubectl rollout restart deployment -n "$NAMESPACE"
        print_step "等待 Pod 就绪..."
        k3s kubectl rollout status deployment -n "$NAMESPACE" --timeout=300s
    else
        sudo k3s kubectl rollout restart deployment -n "$NAMESPACE"
        print_step "等待 Pod 就绪..."
        sudo k3s kubectl rollout status deployment -n "$NAMESPACE" --timeout=300s
    fi
    
    print_success "服务重启成功"
}

# 增强的主菜单
show_main_menu() {
    while true; do
        clear
        print_title "ESS Community 管理菜单"
        print_info "安装目录: $INSTALL_DIR"
        print_info "命名空间: $NAMESPACE"
        print_info "Chart 版本: $ESS_CHART_VERSION"
        echo
        
        print_info "可用选项:"
        print_info "1. 查看部署状态"
        print_info "2. 创建用户账户"
        print_info "3. 备份配置"
        print_info "4. 备份数据库"
        print_info "5. 重启服务"
        print_info "6. 查看日志"
        print_info "7. 更新部署"
        print_info "8. 清理环境"
        print_info "9. 退出"
        echo
        
        read -p "选择选项 (1-9): " choice
        
        case $choice in
            1)
                if [[ $EUID -eq 0 ]]; then
                    k3s kubectl get pods -n "$NAMESPACE"
                    echo
                    k3s kubectl get services -n "$NAMESPACE"
                else
                    sudo k3s kubectl get pods -n "$NAMESPACE"
                    echo
                    sudo k3s kubectl get services -n "$NAMESPACE"
                fi
                echo
                read -p "按 Enter 继续..."
                ;;
            2)
                create_initial_user
                read -p "按 Enter 继续..."
                ;;
            3)
                backup_configuration
                read -p "按 Enter 继续..."
                ;;
            4)
                backup_database
                read -p "按 Enter 继续..."
                ;;
            5)
                restart_services
                read -p "按 Enter 继续..."
                ;;
            6)
                print_info "可用的部署:"
                if [[ $EUID -eq 0 ]]; then
                    k3s kubectl get deployments -n "$NAMESPACE"
                else
                    sudo k3s kubectl get deployments -n "$NAMESPACE"
                fi
                echo
                read -p "输入部署名称以查看日志: " deployment
                if [[ -n "$deployment" ]]; then
                    if [[ $EUID -eq 0 ]]; then
                        k3s kubectl logs -n "$NAMESPACE" deployment/"$deployment" --tail=50
                    else
                        sudo k3s kubectl logs -n "$NAMESPACE" deployment/"$deployment" --tail=50
                    fi
                fi
                read -p "按 Enter 继续..."
                ;;
            7)
                print_warning "更新功能尚未实现"
                read -p "按 Enter 继续..."
                ;;
            8)
                cleanup_environment
                if [[ ! -d "$INSTALL_DIR" ]]; then
                    exit 0
                fi
                ;;
            9)
                print_info "再见！"
                exit 0
                ;;
            *)
                print_error "无效选项。请选择 1-9。"
                sleep 2
                ;;
        esac
    done
}

# 主部署函数
main_deployment() {
    # 首先创建目录以确保日志工作
    create_directories
    
    log "开始 ESS Community 部署 - 脚本版本 $SCRIPT_VERSION"
    
    show_welcome
    check_system
    configure_domains
    check_network_requirements
    configure_ports
    configure_certificates
    configure_installation
    show_configuration_summary
    save_configuration
    install_dependencies
    install_k3s
    configure_k3s_ports
    install_helm
    create_namespace
    install_cert_manager
    configure_cloudflare_dns
    generate_ess_config
    deploy_ess
    create_initial_user
    verify_deployment
    backup_configuration
    show_completion_info
    
    log "ESS Community 部署成功完成"
}

# 主函数
main() {
    # 检查是否已部署
    if [[ -f "${INSTALL_DIR}/config/main.yaml" ]]; then
        local namespace_exists
        if [[ $EUID -eq 0 ]]; then
            namespace_exists=$(k3s kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "not_found")
        else
            namespace_exists=$(sudo k3s kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "not_found")
        fi
        
        if [[ "$namespace_exists" != "not_found" ]]; then
            show_main_menu
        else
            main_deployment
        fi
    else
        main_deployment
    fi
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
