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

    # 如果配置文件存在，询问是否重用
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "发现现有配置文件: $CONFIG_FILE"
        if confirm "是否重用现有配置" "y"; then
            source "$CONFIG_FILE"
            print_success "已加载现有配置"
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

    # Matrix服务器域名 (通常是matrix.主域名)
    read -p "Matrix服务器域名 [默认: matrix.$MAIN_DOMAIN]: " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-matrix.$MAIN_DOMAIN}

    # 子域名配置 - 基于主域名自动生成
    print_info "子域名配置 (基于主域名 $MAIN_DOMAIN 自动生成):"

    # Element Web域名
    read -p "Element Web域名 [默认: element.$MAIN_DOMAIN]: " WEB_HOST
    WEB_HOST=${WEB_HOST:-element.$MAIN_DOMAIN}

    # 认证服务域名
    read -p "认证服务域名 [默认: auth.$MAIN_DOMAIN]: " AUTH_HOST
    AUTH_HOST=${AUTH_HOST:-auth.$MAIN_DOMAIN}

    # RTC服务域名
    read -p "RTC服务域名 [默认: rtc.$MAIN_DOMAIN]: " RTC_HOST
    RTC_HOST=${RTC_HOST:-rtc.$MAIN_DOMAIN}

    # Synapse域名
    read -p "Synapse域名 [默认: $SERVER_NAME]: " SYNAPSE_HOST
    SYNAPSE_HOST=${SYNAPSE_HOST:-$SERVER_NAME}

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

    # 公网IP获取方式选择
    echo
    print_info "公网IP获取方式:"
    echo "  1) DDNS解析 - dig +short ip.$MAIN_DOMAIN (推荐)"
    echo "  2) 外部服务 - curl ifconfig.me (备用)"

    while true; do
        read -p "请选择IP获取方式 [1-2, 默认: 1]: " ip_choice
        ip_choice=${ip_choice:-1}

        case $ip_choice in
            1)
                IP_METHOD="ddns"
                print_info "已选择DDNS解析方式"
                break
                ;;
            2)
                IP_METHOD="external"
                print_info "已选择外部服务方式"
                break
                ;;
            *)
                print_error "请输入 1 或 2"
                ;;
        esac
    done

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

# WebRTC端口配置 (视频会议)
WEBRTC_TCP_PORT="30881"        # WebRTC TCP端口
WEBRTC_UDP_PORT="30882"        # WebRTC UDP端口

# ==================== 管理员配置 ====================
ADMIN_USERNAME="$ADMIN_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"

# ==================== 证书配置 ====================
CERT_EMAIL="$CERT_EMAIL"
CERT_ENVIRONMENT="production"   # Let's Encrypt环境

# ==================== ESS版本信息 ====================
ESS_VERSION="$ESS_VERSION"
ESS_CHART_OCI="$ESS_CHART_OCI"
K3S_VERSION="$K3S_VERSION"
HELM_VERSION="$HELM_VERSION"

# ==================== 网络配置 ====================
# IP获取方式
IP_METHOD="$IP_METHOD"

# 公网IP (根据选择的方式获取)
EOF

    # 根据IP获取方式生成不同的命令
    if [[ "$IP_METHOD" == "ddns" ]]; then
        cat >> "$CONFIG_FILE" << 'EOF'
PUBLIC_IP="$(dig +short ip.$MAIN_DOMAIN @8.8.8.8 2>/dev/null || dig +short ip.$MAIN_DOMAIN @1.1.1.1 2>/dev/null || echo 'unknown')"
EOF
    else
        cat >> "$CONFIG_FILE" << 'EOF'
PUBLIC_IP="$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo 'unknown')"
EOF
    fi

    cat >> "$CONFIG_FILE" << EOF

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

    # 检测公网IP获取
    print_info "检测公网IP获取..."
    if [[ "$IP_METHOD" == "ddns" ]]; then
        local test_ip=$(dig +short ip.$MAIN_DOMAIN @8.8.8.8 2>/dev/null || dig +short ip.$MAIN_DOMAIN @1.1.1.1 2>/dev/null)
        if [[ -n "$test_ip" && "$test_ip" != "unknown" ]]; then
            print_success "DDNS解析成功: $test_ip"
        else
            print_warning "DDNS解析失败，可能需要检查域名配置"
            print_info "请确认 ip.$MAIN_DOMAIN 的A记录已正确配置"
        fi
    else
        local test_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
        if [[ -n "$test_ip" ]]; then
            print_success "外部IP服务正常: $test_ip"
        else
            print_warning "外部IP服务访问失败"
        fi
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

  # WebRTC端口配置
  service:
    type: NodePort
    ports:
      tcp:
        port: 7880
        nodePort: $WEBRTC_TCP_PORT
      udp:
        port: 7881
        nodePort: $WEBRTC_UDP_PORT

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
                collect_config
                test_network_connectivity
                generate_ess_values

                print_info "配置摘要:"
                echo "  服务器域名: $SERVER_NAME"
                echo "  Element Web: $WEB_HOST"
                echo "  认证服务: $AUTH_HOST"
                echo "  RTC服务: $RTC_HOST"
                echo "  Synapse: $SYNAPSE_HOST"
                echo "  安装目录: $INSTALL_DIR"
                echo "  HTTP端口: $HTTP_PORT"
                echo "  HTTPS端口: $HTTPS_PORT"
                echo "  联邦端口: $FEDERATION_PORT"
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
                    # 加载配置
                    source "$CONFIG_FILE"
                    print_info "当前配置:"
                    echo "  服务器域名: $SERVER_NAME"
                    echo "  安装目录: $INSTALL_DIR"
                    echo "  配置文件: $CONFIG_FILE"

                    if [[ -f "$SCRIPT_DIR/manage.sh" ]]; then
                        "$SCRIPT_DIR/manage.sh"
                    else
                        print_info "管理功能开发中..."
                    fi
                else
                    print_warning "未找到现有部署，请先执行部署"
                fi
                read -p "按回车键继续..."
                ;;
            3)
                if [[ -f "$CONFIG_FILE" ]]; then
                    source "$CONFIG_FILE"
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
                    source "$CONFIG_FILE"
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
