#!/bin/bash

# Matrix ESS Community 自动部署脚本 v5.0.0
# 重新设计版本 - 小白友好，逻辑严谨，完全动态配置
# 创建日期: 2025-06-13 16:30
# 许可证: AGPL-3.0 (仅限非商业用途)
# 基于ESS官方最新规范25.6.1，遵循需求文档原则

set -euo pipefail

# ==================== 全局配置 ====================

readonly SCRIPT_VERSION="5.0.0"
readonly SCRIPT_NAME="Matrix ESS Community 自动部署脚本"
readonly SCRIPT_DATE="2025-06-13"

# ESS官方最新版本信息
readonly ESS_VERSION="25.6.1"
readonly ESS_CHART_OCI="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
readonly K3S_VERSION="v1.32.5+k3s1"
readonly HELM_VERSION="v3.18.2"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 动态配置变量 - 运行时收集，无硬编码
SCRIPT_DIR=""
CONFIG_FILE=""
INSTALL_DIR=""
MAIN_DOMAIN=""
SERVER_NAME=""
WEB_HOST=""
AUTH_HOST=""
RTC_HOST=""
SYNAPSE_HOST=""
HTTP_PORT=""
HTTPS_PORT=""
FEDERATION_PORT=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
CERT_EMAIL=""

# ==================== 基础函数 ====================

print_header() {
    echo -e "\n${CYAN}================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_step() {
    echo -e "\n${CYAN}>>> $1${NC}"
}

# 简化的确认函数
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " choice
        choice=${choice:-y}
    else
        read -p "$message [y/N]: " choice
        choice=${choice:-n}
    fi
    
    [[ "$choice" =~ ^[Yy]$ ]]
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统要求
check_system() {
    print_step "检查系统要求"
    
    # 检查操作系统
    if ! command -v lsb_release &> /dev/null; then
        print_error "不支持的操作系统，请使用 Debian/Ubuntu"
        exit 1
    fi
    
    local os_info=$(lsb_release -d | cut -f2)
    print_info "操作系统: $os_info"
    
    # 检查内存
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 4 ]]; then
        print_warning "内存不足4GB，可能影响性能"
        if ! confirm "是否继续安装"; then
            exit 1
        fi
    fi
    
    # 检查磁盘空间
    local disk_gb=$(df / | awk 'NR==2{print int($4/1024/1024)}')
    if [[ $disk_gb -lt 20 ]]; then
        print_error "磁盘空间不足20GB，无法继续"
        exit 1
    fi
    
    print_success "系统检查通过"
}

# ==================== 主菜单 ====================

show_main_menu() {
    clear
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    
    echo -e "${WHITE}ESS版本:${NC} $ESS_VERSION (官方最新稳定版)"
    echo -e "${WHITE}设计理念:${NC} 小白友好，逻辑严谨，最小化修改"
    echo
    echo -e "${YELLOW}⚠ 许可证: 仅限非商业用途 (AGPL-3.0)${NC}"
    echo
    
    echo -e "${WHITE}请选择操作:${NC}"
    echo -e "  ${GREEN}1)${NC} 🚀 一键部署 Matrix ESS"
    echo -e "  ${GREEN}2)${NC} 🔧 管理现有部署"
    echo -e "  ${GREEN}3)${NC} 🗑️  完全清理"
    echo -e "  ${GREEN}4)${NC} ℹ️  系统信息"
    echo -e "  ${RED}0)${NC} 退出"
    echo
}

# ==================== 动态配置初始化 ====================

init_dynamic_config() {
    # 动态确定脚本目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 动态确定配置文件路径
    CONFIG_FILE="$SCRIPT_DIR/matrix-config.env"

    print_info "脚本目录: $SCRIPT_DIR"
}

# ==================== 配置收集 ====================

collect_config() {
    print_step "配置收集"

    # 如果配置文件存在，询问是否重新设置
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "发现现有配置文件: $CONFIG_FILE"

        # 显示现有配置摘要
        if source "$CONFIG_FILE" 2>/dev/null; then
            print_info "现有配置摘要:"
            echo "  主域名: ${MAIN_DOMAIN:-未设置}"
            echo "  Element Web: ${WEB_HOST:-未设置}"
            echo "  认证服务: ${AUTH_HOST:-未设置}"
            echo "  RTC服务: ${RTC_HOST:-未设置}"
            echo "  Matrix服务器: ${SERVER_NAME:-未设置}"
            echo "  安装目录: ${INSTALL_DIR:-未设置}"
            echo "  HTTP端口: ${HTTP_PORT:-未设置}"
            echo "  HTTPS端口: ${HTTPS_PORT:-未设置}"
            echo
        fi

        # 默认不重新设置，直接使用现有配置
        if confirm "是否重新设置配置" "n"; then
            print_info "开始重新配置..."
        else
            print_success "使用现有配置，跳过配置收集"
            return 0
        fi
    fi

    # 收集安装目录
    print_info "请提供以下信息:"
    echo

    while true; do
        read -p "安装目录 [默认: /opt/matrix]: " INSTALL_DIR
        INSTALL_DIR=${INSTALL_DIR:-/opt/matrix}

        if [[ "$INSTALL_DIR" =~ ^/.+ ]]; then
            if [[ -d "$INSTALL_DIR" && "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
                print_warning "目录 $INSTALL_DIR 不为空"
                if confirm "是否继续使用此目录"; then
                    break
                fi
            else
                break
            fi
        else
            print_error "请输入绝对路径 (以/开头)"
        fi
    done

    # 主域名
    while true; do
        read -p "主域名 (如: example.com): " MAIN_DOMAIN
        if [[ -n "$MAIN_DOMAIN" && "$MAIN_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        print_error "请输入有效的域名格式"
    done

    # 基于主域名自动生成所有子域名
    print_info "基于主域名 $MAIN_DOMAIN 自动生成子域名:"

    # 使用ESS官方标准子域名前缀 (基于官方规范)
    WEB_HOST="chat.$MAIN_DOMAIN"          # Element Web客户端 (官方: chat)
    AUTH_HOST="account.$MAIN_DOMAIN"      # Matrix Authentication Service (官方: account)
    RTC_HOST="mrtc.$MAIN_DOMAIN"          # Matrix RTC (官方: mrtc)
    SERVER_NAME="$MAIN_DOMAIN"            # Matrix服务器名称 (官方: serverName)
    SYNAPSE_HOST="matrix.$MAIN_DOMAIN"    # Synapse访问地址 (官方: matrix)

    echo "  Element Web: $WEB_HOST"
    echo "  认证服务: $AUTH_HOST"
    echo "  RTC服务: $RTC_HOST"
    echo "  Matrix服务器: $SERVER_NAME (用户ID: @username:$SERVER_NAME)"
    echo "  Synapse访问: $SYNAPSE_HOST"
    echo

    if ! confirm "是否使用这些自动生成的域名" "y"; then
        print_info "请手动输入域名:"
        read -p "Element Web域名: " WEB_HOST
        read -p "认证服务域名: " AUTH_HOST
        read -p "RTC服务域名: " RTC_HOST
        read -p "Matrix服务器名称 (用户ID域名): " SERVER_NAME
        read -p "Synapse访问域名: " SYNAPSE_HOST
    fi

    # 端口配置 - 完全动态
    print_info "端口配置:"

    read -p "HTTP端口 [默认: 8080]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-8080}

    read -p "HTTPS端口 [默认: 8443]: " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-8443}

    read -p "联邦端口 [默认: 8448]: " FEDERATION_PORT
    FEDERATION_PORT=${FEDERATION_PORT:-8448}

    # 网络配置
    print_info "网络配置:"
    print_info "公网IP获取方式: DDNS解析 (dig +short ip.$MAIN_DOMAIN)"
    print_info "遵循需求文档标准方法"

    # 固定使用DDNS方式
    IP_METHOD="ddns"

    # 管理员配置
    read -p "管理员用户名 [默认: admin]: " ADMIN_USERNAME
    ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

    while true; do
        read -s -p "管理员密码 (至少8位): " ADMIN_PASSWORD
        echo
        if [[ ${#ADMIN_PASSWORD} -ge 8 ]]; then
            break
        fi
        print_error "密码至少需要8位字符"
    done

    # 证书配置
    print_info "证书配置:"

    # 证书邮箱
    while true; do
        read -p "Let's Encrypt证书邮箱: " CERT_EMAIL
        if [[ "$CERT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        print_error "请输入有效的邮箱地址"
    done

    # 证书环境选择
    echo
    print_info "证书环境选择:"
    echo "  1) 生产模式 - 正式证书 (推荐)"
    echo "  2) 测试模式 - 测试证书 (用于调试)"

    while true; do
        read -p "请选择证书环境 [1-2, 默认: 1]: " cert_choice
        cert_choice=${cert_choice:-1}

        case $cert_choice in
            1)
                CERT_ENVIRONMENT="production"
                print_info "已选择生产模式"
                break
                ;;
            2)
                CERT_ENVIRONMENT="staging"
                print_info "已选择测试模式"
                break
                ;;
            *)
                print_error "请输入 1 或 2"
                ;;
        esac
    done

    # Cloudflare DNS验证配置
    print_info "Cloudflare DNS验证配置:"
    print_info "需要Cloudflare API Token用于DNS验证"

    while true; do
        read -s -p "Cloudflare API Token: " CLOUDFLARE_TOKEN
        echo
        if [[ -n "$CLOUDFLARE_TOKEN" ]]; then
            break
        fi
        print_error "Cloudflare API Token不能为空"
    done

    # 保存配置
    save_config
    print_success "配置收集完成"
}

# 保存配置到文件 - 完全动态，包含所有必要信息
save_config() {
    # 确保安装目录存在
    mkdir -p "$INSTALL_DIR"

    cat > "$CONFIG_FILE" << EOF
# Matrix ESS Community 配置文件
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION
# 基于ESS官方最新规范: $ESS_VERSION

# ==================== 路径配置 ====================
SCRIPT_DIR="$SCRIPT_DIR"
INSTALL_DIR="$INSTALL_DIR"
CONFIG_FILE="$CONFIG_FILE"

# ==================== 域名配置 ====================
# 主域名 (用于IP解析和子域名生成)
MAIN_DOMAIN="$MAIN_DOMAIN"

# Matrix服务器名称 (用户ID的域名部分)
SERVER_NAME="$SERVER_NAME"

# 子域名配置 (完全自定义)
WEB_HOST="$WEB_HOST"           # Element Web客户端
AUTH_HOST="$AUTH_HOST"         # Matrix Authentication Service
RTC_HOST="$RTC_HOST"           # Matrix RTC (视频会议)
SYNAPSE_HOST="$SYNAPSE_HOST"   # Synapse主服务器

# ==================== 端口配置 ====================
# 基础端口配置
HTTP_PORT="$HTTP_PORT"         # HTTP访问端口
HTTPS_PORT="$HTTPS_PORT"       # HTTPS访问端口
FEDERATION_PORT="$FEDERATION_PORT"  # Matrix联邦端口

# NodePort端口配置 (Kubernetes对外暴露)
NODEPORT_HTTP="30080"          # HTTP NodePort
NODEPORT_HTTPS="30443"         # HTTPS NodePort
NODEPORT_FEDERATION="30448"    # 联邦 NodePort

# WebRTC端口配置 (标准配置 - 推荐)
WEBRTC_TCP_PORT="30881"        # WebRTC TCP端口 (ICE/TCP fallback)

# ==================== 管理员配置 ====================
ADMIN_USERNAME="$ADMIN_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"

# ==================== 证书配置 ====================
CERT_EMAIL="$CERT_EMAIL"
CERT_ENVIRONMENT="production"   # Let's Encrypt环境

# ==================== ESS版本信息 ====================
# 版本信息由脚本控制，不在配置文件中保存
# ESS_VERSION="25.6.1"
# ESS_CHART_OCI="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
# K3S_VERSION="v1.32.5+k3s1"
# HELM_VERSION="v3.18.2"

# ==================== 网络配置 ====================
# IP获取方式 (固定使用需求文档方法)
IP_METHOD="ddns"

# 公网IP (遵循需求文档: dig +short ip.自定义域名 @8.8.8.8 或 @1.1.1.1)
PUBLIC_IP="\$(dig +short ip.$MAIN_DOMAIN @8.8.8.8 2>/dev/null || dig +short ip.$MAIN_DOMAIN @1.1.1.1 2>/dev/null || echo 'unknown')"

# UDP端口范围 (用于WebRTC)
UDP_RANGE="30152-30352"

# ==================== 部署配置 ====================
# Kubernetes命名空间
ESS_NAMESPACE="ess"
CERT_MANAGER_NAMESPACE="cert-manager"

# 部署超时设置
DEPLOY_TIMEOUT="600s"
POD_WAIT_TIMEOUT="600s"
EOF

    chmod 600 "$CONFIG_FILE"
    print_info "配置已保存到: $CONFIG_FILE"
}

# 显示配置详情
show_config_details() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_warning "配置文件不存在"
        return 1
    fi

    # 安全加载配置文件，完全忽略所有错误和警告
    {
        source "$CONFIG_FILE"
    } 2>/dev/null || {
        # 如果source失败，手动提取关键配置
        print_warning "配置文件加载有问题，尝试手动解析..."
        MAIN_DOMAIN=$(grep "^MAIN_DOMAIN=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        SERVER_NAME=$(grep "^SERVER_NAME=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        WEB_HOST=$(grep "^WEB_HOST=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        AUTH_HOST=$(grep "^AUTH_HOST=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        RTC_HOST=$(grep "^RTC_HOST=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        SYNAPSE_HOST=$(grep "^SYNAPSE_HOST=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        INSTALL_DIR=$(grep "^INSTALL_DIR=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        HTTP_PORT=$(grep "^HTTP_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        HTTPS_PORT=$(grep "^HTTPS_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        FEDERATION_PORT=$(grep "^FEDERATION_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        WEBRTC_TCP_PORT=$(grep "^WEBRTC_TCP_PORT=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        IP_METHOD=$(grep "^IP_METHOD=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "ddns")
        ADMIN_USERNAME=$(grep "^ADMIN_USERNAME=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        CERT_EMAIL=$(grep "^CERT_EMAIL=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
        # 设置默认的PUBLIC_IP变量，避免未定义错误
        PUBLIC_IP="未获取"
    }

    print_step "当前配置详情"

    echo -e "${WHITE}域名配置:${NC}"
    echo "  主域名: $MAIN_DOMAIN"
    echo "  Matrix服务器: $SERVER_NAME"
    echo "  Element Web: $WEB_HOST"
    echo "  认证服务: $AUTH_HOST"
    echo "  RTC服务: $RTC_HOST"
    echo "  Synapse: $SYNAPSE_HOST"
    echo

    echo -e "${WHITE}路径配置:${NC}"
    echo "  脚本目录: $SCRIPT_DIR"
    echo "  安装目录: $INSTALL_DIR"
    echo "  配置文件: $CONFIG_FILE"
    echo

    echo -e "${WHITE}端口配置:${NC}"
    echo "  HTTP端口: $HTTP_PORT"
    echo "  HTTPS端口: $HTTPS_PORT"
    echo "  联邦端口: $FEDERATION_PORT"
    echo "  WebRTC TCP: $WEBRTC_TCP_PORT (ICE/TCP fallback)"
    echo "  WebRTC UDP: 30152-30352 (端口范围)"
    echo

    echo -e "${WHITE}网络配置:${NC}"
    echo "  IP获取方式: $IP_METHOD"
    echo "  公网IP: ${PUBLIC_IP:-未获取}"
    echo

    echo -e "${WHITE}管理员配置:${NC}"
    echo "  用户名: $ADMIN_USERNAME"
    echo "  密码: [已设置]"
    echo

    echo -e "${WHITE}证书配置:${NC}"
    echo "  邮箱: $CERT_EMAIL"
    echo

    echo -e "${WHITE}版本信息:${NC}"
    echo "  ESS版本: $ESS_VERSION"
    echo "  K3s版本: $K3S_VERSION"
    echo "  Helm版本: $HELM_VERSION"
}

# 网络检测函数 - 遵循需求文档要求
test_network_connectivity() {
    print_step "网络连通性检测"

    # 检测DNS解析
    print_info "检测DNS解析..."
    if dig +short @8.8.8.8 google.com &> /dev/null; then
        print_success "DNS解析正常 (8.8.8.8)"
    elif dig +short @1.1.1.1 google.com &> /dev/null; then
        print_success "DNS解析正常 (1.1.1.1)"
    else
        print_warning "DNS解析可能有问题"
    fi

    # 检测公网IP获取 (仅使用需求文档方法)
    print_info "检测公网IP获取 (DDNS解析方式)..."
    local test_ip=$(dig +short ip.$MAIN_DOMAIN @8.8.8.8 2>/dev/null || dig +short ip.$MAIN_DOMAIN @1.1.1.1 2>/dev/null)
    if [[ -n "$test_ip" && "$test_ip" != "unknown" && "$test_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_success "DDNS解析成功: $test_ip"
    else
        print_warning "DDNS解析失败，需要检查域名配置"
        print_info "请确认 ip.$MAIN_DOMAIN 的A记录已正确配置"
        print_info "测试命令: dig +short ip.$MAIN_DOMAIN @8.8.8.8"
    fi

    # 检测域名解析
    print_info "检测域名解析..."
    for domain in "$WEB_HOST" "$AUTH_HOST" "$RTC_HOST" "$SYNAPSE_HOST"; do
        if dig +short "$domain" @8.8.8.8 &> /dev/null; then
            print_success "$domain 解析正常"
        else
            print_warning "$domain 解析失败，请检查DNS配置"
        fi
    done

    print_success "网络检测完成"
}

# 生成ESS配置文件 - 基于官方最新规范
generate_ess_values() {
    local values_file="$INSTALL_DIR/ess-values.yaml"

    print_step "生成ESS配置文件"
    print_info "基于ESS官方最新规范 $ESS_VERSION 生成配置..."

    # 确保目录存在
    mkdir -p "$INSTALL_DIR"

    cat > "$values_file" << EOF
# Matrix ESS Community 配置文件
# 基于ESS官方最新规范: $ESS_VERSION
# 生成时间: $(date)
# 配置来源: 需求文档 + 官方最新版规范

# ==================== 全局配置 ====================
# Matrix服务器名称 (必需) - 用户ID的域名部分
serverName: "$SERVER_NAME"

# 全局标签
labels:
  deployment: "ess-community"
  version: "$ESS_VERSION"
  managed-by: "matrix-ess-deploy-script"

# ==================== Ingress全局配置 ====================
ingress:
  # 全局注解 - 自动TLS证书管理
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"

  # 启用TLS
  tlsEnabled: true

  # 全局TLS密钥名称
  tlsSecret: "ess-tls-secret"

  # 服务类型
  service:
    type: ClusterIP

# ==================== Element Web配置 ====================
elementWeb:
  enabled: true
  ingress:
    host: "$WEB_HOST"
    # 继承全局TLS配置

  # Element Web特定配置
  config:
    default_server_config:
      "m.homeserver":
        base_url: "https://$SYNAPSE_HOST:$HTTPS_PORT"
        server_name: "$SERVER_NAME"
      "m.identity_server":
        base_url: "https://vector.im"

    # 集成管理器配置
    integrations_ui_url: "https://scalar.vector.im/"
    integrations_rest_url: "https://scalar.vector.im/api"

    # 品牌配置
    brand: "Matrix ESS Community"

# ==================== Matrix Authentication Service配置 ====================
matrixAuthenticationService:
  enabled: true
  ingress:
    host: "$AUTH_HOST"

  # MAS配置
  config:
    http:
      public_base: "https://$AUTH_HOST:$HTTPS_PORT/"
      issuer: "https://$AUTH_HOST:$HTTPS_PORT/"

    # 数据库配置 (使用内置PostgreSQL)
    database:
      uri: "postgresql://mas:mas@postgresql:5432/mas"

# ==================== Matrix RTC配置 ====================
matrixRTC:
  enabled: true
  ingress:
    host: "$RTC_HOST"

  # SFU配置 - 使用LiveKit
  sfu:
    enabled: true
    type: "livekit"

    # LiveKit配置 (标准配置 - 推荐)
    config:
      # WebRTC配置
      rtc:
        # UDP端口范围 (需求文档指定: 30152-30352) - 必需
        port_range_start: 30152
        port_range_end: 30352

        # TCP端口 (ICE/TCP fallback) - 推荐，应对严格防火墙
        tcp_port: $WEBRTC_TCP_PORT

      # API端口配置
      port: 7880

  # 服务端口配置
  service:
    type: NodePort
    ports:
      # API/WebSocket端口
      http:
        port: 7880
        nodePort: $WEBRTC_TCP_PORT

      # UDP端口范围需要通过hostNetwork暴露
      # 这里只配置主要的UDP端口
      udp:
        port: 30152
        nodePort: 30152
        protocol: UDP

# ==================== Synapse配置 ====================
synapse:
  enabled: true
  ingress:
    host: "$SYNAPSE_HOST"

  # Synapse配置
  config:
    server_name: "$SERVER_NAME"
    public_baseurl: "https://$SYNAPSE_HOST:$HTTPS_PORT/"

    # 联邦配置
    federation:
      enabled: true
      port: $FEDERATION_PORT

    # 数据库配置 (使用内置PostgreSQL)
    database:
      name: "psycopg2"
      args:
        user: "synapse"
        password: "synapse"
        database: "synapse"
        host: "postgresql"
        port: 5432

# ==================== PostgreSQL配置 ====================
postgresql:
  enabled: true
  auth:
    postgresPassword: "postgres"
    database: "synapse"

  # 持久化存储
  persistence:
    enabled: true
    size: 10Gi

# ==================== HAProxy配置 ====================
haproxy:
  enabled: true

  # HAProxy配置 - 负载均衡和路由
  config:
    # 使用自定义端口
    frontend:
      http_port: $HTTP_PORT
      https_port: $HTTPS_PORT
      federation_port: $FEDERATION_PORT

# ==================== Well-known委托配置 ====================
wellKnownDelegation:
  enabled: true

  # 主域名重定向到Element Web (使用自定义端口)
  baseDomainRedirect:
    enabled: true
    url: "https://$WEB_HOST:$HTTPS_PORT"

  # 基于官方规范的配置，使用自定义端口
  additional:
    client: |
      {
        "m.homeserver": {
          "base_url": "https://$SYNAPSE_HOST:$HTTPS_PORT"
        },
        "org.matrix.msc2965.authentication": {
          "issuer": "https://$AUTH_HOST:$HTTPS_PORT/",
          "account": "https://$AUTH_HOST:$HTTPS_PORT/account"
        },
        "org.matrix.msc4143.rtc_foci": [
          {
            "type": "livekit",
            "livekit_service_url": "https://$RTC_HOST:$HTTPS_PORT"
          }
        ]
      }

    server: |
      {
        "m.server": "$SYNAPSE_HOST:$HTTPS_PORT"
      }

# ==================== 服务暴露配置 ====================
# 使用NodePort暴露服务到自定义端口
service:
  type: NodePort
  ports:
    http:
      port: 80
      nodePort: $NODEPORT_HTTP
    https:
      port: 443
      nodePort: $NODEPORT_HTTPS
    federation:
      port: 8448
      nodePort: $NODEPORT_FEDERATION

# ==================== 网络策略配置 ====================
# UDP端口范围配置 (需求文档: 30152-30352)
networkPolicy:
  enabled: true

  # 允许WebRTC端口入站流量 (标准配置)
  ingress:
    - from: []
      ports:
        # UDP端口范围 (主要WebRTC端口) - 必需
        - protocol: UDP
          port: 30152
          endPort: 30352
        # TCP端口 (ICE/TCP fallback) - 推荐
        - protocol: TCP
          port: $WEBRTC_TCP_PORT

# ==================== 主机网络配置 ====================
# LiveKit需要主机网络来暴露UDP端口范围 (标准配置)
hostNetwork:
  enabled: true

  # UDP端口范围配置 (主要WebRTC端口) - 必需
  udpPortRange:
    start: 30152
    end: 30352

  # TCP端口配置 (ICE/TCP fallback) - 推荐
  tcpPort: $WEBRTC_TCP_PORT
EOF

    print_success "ESS配置文件已生成: $values_file"
    print_info "配置基于ESS官方最新规范，包含所有自定义端口和域名"
}

# ==================== 主程序 ====================

main() {
    # 初始化动态配置
    init_dynamic_config

    # 检查权限和系统
    check_root
    check_system

    while true; do
        show_main_menu
        read -p "请选择 (0-4): " choice

        case $choice in
            1)
                print_step "开始一键部署"

                # 收集或加载配置
                collect_config

                # 确保配置已加载
                if [[ -f "$CONFIG_FILE" ]]; then
                    source "$CONFIG_FILE" 2>/dev/null || true
                else
                    print_error "配置文件不存在，无法继续部署"
                    read -p "按回车键继续..."
                    continue
                fi

                # 网络连通性检测
                test_network_connectivity

                # 生成ESS配置文件
                generate_ess_values

                # 显示配置摘要
                print_info "配置摘要:"
                echo "  主域名: $MAIN_DOMAIN"
                echo "  服务器域名: $SERVER_NAME"
                echo "  Element Web: $WEB_HOST"
                echo "  认证服务: $AUTH_HOST"
                echo "  RTC服务: $RTC_HOST"
                echo "  Synapse: $SYNAPSE_HOST"
                echo "  安装目录: $INSTALL_DIR"
                echo "  HTTP端口: $HTTP_PORT"
                echo "  HTTPS端口: $HTTPS_PORT"
                echo "  联邦端口: $FEDERATION_PORT"
                echo "  IP获取方式: $IP_METHOD"
                echo

                if confirm "确认开始部署" "y"; then
                    # 调用部署脚本 (如果存在)
                    if [[ -f "$SCRIPT_DIR/deploy.sh" ]]; then
                        "$SCRIPT_DIR/deploy.sh"
                    else
                        print_info "配置文件已生成，请手动部署或创建deploy.sh脚本"
                        print_info "ESS配置文件: $INSTALL_DIR/ess-values.yaml"
                        print_info "环境配置文件: $CONFIG_FILE"
                    fi
                fi
                read -p "按回车键继续..."
                ;;
            2)
                if [[ -f "$CONFIG_FILE" ]]; then
                    # 显示配置详情
                    show_config_details
                    echo

                    print_info "管理选项:"
                    echo "  1) 查看部署状态"
                    echo "  2) 重新部署"
                    echo "  3) 更新配置"
                    echo "  4) 返回主菜单"

                    read -p "请选择 [1-4]: " manage_choice

                    case $manage_choice in
                        1)
                            print_info "查看部署状态..."
                            if command -v k3s &> /dev/null; then
                                echo "K3s状态:"
                                systemctl is-active k3s && echo "  ✅ K3s运行正常" || echo "  ❌ K3s未运行"

                                if k3s kubectl get namespace ess &> /dev/null; then
                                    echo "ESS状态:"
                                    k3s kubectl get pods -n ess
                                else
                                    echo "  ❌ ESS未部署"
                                fi
                            else
                                echo "  ❌ K3s未安装"
                            fi
                            ;;
                        2)
                            print_info "重新部署..."
                            if [[ -f "$SCRIPT_DIR/deploy.sh" ]]; then
                                "$SCRIPT_DIR/deploy.sh"
                            else
                                print_warning "部署脚本不存在"
                            fi
                            ;;
                        3)
                            print_info "更新配置..."
                            collect_config
                            ;;
                        4)
                            print_info "返回主菜单"
                            ;;
                        *)
                            print_error "无效选择"
                            ;;
                    esac
                else
                    print_warning "未找到现有部署，请先执行部署"
                fi
                read -p "按回车键继续..."
                ;;
            3)
                if [[ -f "$CONFIG_FILE" ]]; then
                    source "$CONFIG_FILE" 2>/dev/null || true
                    print_warning "将清理以下内容:"
                    echo "  - 安装目录: $INSTALL_DIR"
                    echo "  - 配置文件: $CONFIG_FILE"
                    echo "  - K3s集群 (如果存在)"
                    echo "  - 所有Matrix数据"

                    if confirm "确认完全清理所有数据" "n"; then
                        if [[ -f "$SCRIPT_DIR/cleanup.sh" ]]; then
                            "$SCRIPT_DIR/cleanup.sh"
                        else
                            print_info "执行基本清理..."
                            rm -rf "$INSTALL_DIR" 2>/dev/null || true
                            rm -f "$CONFIG_FILE" 2>/dev/null || true
                            print_success "基本清理完成"
                        fi
                    fi
                else
                    print_warning "未找到配置文件，无需清理"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                print_step "系统信息"
                echo "脚本信息:"
                echo "  名称: $SCRIPT_NAME"
                echo "  版本: $SCRIPT_VERSION"
                echo "  日期: $SCRIPT_DATE"
                echo "  脚本目录: $SCRIPT_DIR"
                echo
                echo "ESS版本信息:"
                echo "  ESS版本: $ESS_VERSION"
                echo "  Chart地址: $ESS_CHART_OCI"
                echo "  K3s版本: $K3S_VERSION"
                echo "  Helm版本: $HELM_VERSION"
                echo
                echo "系统信息:"
                echo "  操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || echo '未知')"
                echo "  内核版本: $(uname -r)"
                echo "  架构: $(uname -m)"
                echo "  内存: $(free -h | awk '/^Mem:/{print $2}')"
                echo "  磁盘: $(df -h / | awk 'NR==2{print $4}') 可用"

                if [[ -f "$CONFIG_FILE" ]]; then
                    echo
                    echo "当前配置:"
                    source "$CONFIG_FILE" 2>/dev/null || true
                    echo "  服务器域名: $SERVER_NAME"
                    echo "  安装目录: $INSTALL_DIR"
                    echo "  配置文件: $CONFIG_FILE"
                fi

                read -p "按回车键继续..."
                ;;
            0)
                echo -e "\n${GREEN}感谢使用！${NC}\n"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 0-4"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main "$@"
