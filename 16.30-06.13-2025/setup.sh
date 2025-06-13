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
    # 检测安装方式
    if [[ "${BASH_SOURCE[0]}" == "/dev/fd/"* ]] || [[ "${BASH_SOURCE[0]}" == "/proc/self/fd/"* ]]; then
        # curl方式安装
        INSTALL_METHOD="curl"
        SCRIPT_DIR="/opt/matrix-ess-setup"
        print_info "检测到curl安装方式"
        print_info "将在 $SCRIPT_DIR 目录下载和运行脚本"

        # 创建工作目录
        mkdir -p "$SCRIPT_DIR"
        cd "$SCRIPT_DIR"

        # 下载所有必要的脚本文件
        download_scripts
    else
        # 本地文件安装
        INSTALL_METHOD="local"
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        print_info "检测到本地文件安装方式"
        print_info "脚本目录: $SCRIPT_DIR"
    fi

    # 动态确定配置文件路径
    CONFIG_FILE="$SCRIPT_DIR/matrix-config.env"
}

# ==================== 脚本下载 ====================

download_scripts() {
    print_step "下载必要的脚本文件"

    local base_url="https://raw.githubusercontent.com/niublab/aiya/main/16.30-06.13-2025"
    local scripts=("deploy.sh" "cleanup.sh" "fix-config.sh")

    for script in "${scripts[@]}"; do
        print_info "下载 $script..."
        if curl -fsSL "$base_url/$script" -o "$script"; then
            chmod +x "$script"
            print_success "下载完成: $script"
        else
            print_warning "下载失败: $script (将在需要时重试)"
        fi
    done

    print_success "脚本下载完成"
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
        print_info "请手动输入域名 (可输入完整域名或仅子域名前缀):"

        read -p "Element Web域名 [如: app 或 app.$MAIN_DOMAIN]: " input_web
        read -p "认证服务域名 [如: mas 或 mas.$MAIN_DOMAIN]: " input_auth
        read -p "RTC服务域名 [如: rtc 或 rtc.$MAIN_DOMAIN]: " input_rtc
        read -p "Matrix服务器名称 (用户ID域名) [如: $MAIN_DOMAIN]: " input_server
        read -p "Synapse访问域名 [如: matrix 或 matrix.$MAIN_DOMAIN]: " input_synapse

        # 智能补全域名：如果输入不包含点号，则自动添加主域名
        if [[ "$input_web" == *.* ]]; then
            WEB_HOST="$input_web"
        else
            WEB_HOST="$input_web.$MAIN_DOMAIN"
        fi

        if [[ "$input_auth" == *.* ]]; then
            AUTH_HOST="$input_auth"
        else
            AUTH_HOST="$input_auth.$MAIN_DOMAIN"
        fi

        if [[ "$input_rtc" == *.* ]]; then
            RTC_HOST="$input_rtc"
        else
            RTC_HOST="$input_rtc.$MAIN_DOMAIN"
        fi

        if [[ "$input_server" == *.* ]]; then
            SERVER_NAME="$input_server"
        else
            SERVER_NAME="$input_server.$MAIN_DOMAIN"
        fi

        if [[ "$input_synapse" == *.* ]]; then
            SYNAPSE_HOST="$input_synapse"
        else
            SYNAPSE_HOST="$input_synapse.$MAIN_DOMAIN"
        fi

        # 显示最终的域名配置
        print_info "最终域名配置:"
        echo "  Element Web: $WEB_HOST"
        echo "  认证服务: $AUTH_HOST"
        echo "  RTC服务: $RTC_HOST"
        echo "  Matrix服务器: $SERVER_NAME (用户ID: @username:$SERVER_NAME)"
        echo "  Synapse访问: $SYNAPSE_HOST"
        echo
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
CERT_ENVIRONMENT="$CERT_ENVIRONMENT"   # Let's Encrypt环境
CLOUDFLARE_TOKEN="$CLOUDFLARE_TOKEN"   # Cloudflare API Token

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
        CERT_ENVIRONMENT=$(grep "^CERT_ENVIRONMENT=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "production")
        CLOUDFLARE_TOKEN=$(grep "^CLOUDFLARE_TOKEN=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "未设置")
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
        print_info "当前服务器公网IP: $test_ip"
    else
        print_warning "DDNS解析失败，需要检查域名配置"
        print_info "请确认 ip.$MAIN_DOMAIN 的A记录已正确配置"
        print_info "测试命令: dig +short ip.$MAIN_DOMAIN @8.8.8.8"

        # 尝试其他方式获取公网IP作为参考
        print_info "尝试其他方式获取公网IP作为参考..."
        local fallback_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "无法获取")
        if [[ "$fallback_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_info "参考公网IP: $fallback_ip (请确保DNS指向此IP)"
        else
            print_warning "无法获取公网IP，请手动检查网络配置"
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
# 严格基于ESS官方schema: $ESS_VERSION
# 生成时间: $(date)

# ==================== 全局配置 ====================
# Matrix服务器名称 (必需) - 用户ID的域名部分
serverName: "$SERVER_NAME"

# 全局标签
labels:
  deployment: "ess-community"
  version: "$ESS_VERSION"
  managed-by: "matrix-ess-deploy-script"

# ==================== 证书管理器配置 ====================
EOF

# 根据是否使用外部反向代理决定证书配置
if [[ "$HTTP_PORT" != "80" ]] || [[ "$HTTPS_PORT" != "443" ]]; then
    # 外部反向代理模式 - 禁用ESS内部证书管理
    cat >> "$values_file" << EOF
# 外部反向代理模式 - 禁用内部证书和TLS
ingress:
  # 不使用cert-manager注解，避免重复申请证书
  annotations: {}

  # 禁用TLS，由外部Nginx处理
  tlsEnabled: false

  # 服务类型
  service:
    type: ClusterIP
EOF
else
    # 标准模式 - 使用ESS内部证书管理
    cat >> "$values_file" << EOF
# 标准模式 - 使用ESS内部证书管理
certManager:
  clusterIssuer: "letsencrypt-production"

ingress:
  # 使用cert-manager自动申请证书
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"

  # 启用TLS
  tlsEnabled: true

  # 服务类型
  service:
    type: ClusterIP
EOF
fi

cat >> "$values_file" << EOF

# ==================== Element Web配置 ====================
elementWeb:
  enabled: true
  ingress:
    host: "$WEB_HOST"

# ==================== Matrix Authentication Service配置 ====================
matrixAuthenticationService:
  enabled: true
  ingress:
    host: "$AUTH_HOST"

# ==================== Matrix RTC配置 ====================
matrixRTC:
  enabled: true
  ingress:
    host: "$RTC_HOST"

  # SFU配置 - 使用LiveKit
  sfu:
    enabled: true
    # 主机网络模式用于UDP端口范围
    hostNetwork: false

    # 暴露的服务配置
    exposedServices:
      rtcTcp:
        enabled: true
        portType: NodePort
        port: $WEBRTC_TCP_PORT
      rtcMuxedUdp:
        enabled: true
        portType: NodePort
        port: 30882
      rtcUdp:
        enabled: true
        portType: NodePort
        portRange:
          startPort: 30152
          endPort: 30352

# ==================== Synapse配置 ====================
synapse:
  enabled: true
  ingress:
    host: "$SYNAPSE_HOST"

# ==================== Well-known委托配置 ====================
wellKnownDelegation:
  enabled: true

  # 主域名重定向到Element Web
  baseDomainRedirect:
    enabled: true
    url: "https://$WEB_HOST"

  # 基于官方规范的配置
  additional:
    client: '{"m.homeserver":{"base_url":"https://$SYNAPSE_HOST"},"org.matrix.msc2965.authentication":{"issuer":"https://$AUTH_HOST/","account":"https://$AUTH_HOST/account"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://$RTC_HOST"}]}'
    server: '{"m.server":"$SYNAPSE_HOST:443"}'
EOF

    print_success "ESS配置文件已生成: $values_file"
    print_info "配置基于ESS官方最新规范，包含所有自定义端口和域名"

    # 如果用户配置了自定义端口，按ESS官方推荐方式配置外部反向代理
    if [[ "$HTTP_PORT" != "80" ]] || [[ "$HTTPS_PORT" != "443" ]]; then
        setup_external_reverse_proxy
    fi
}

# ==================== 主程序 ====================

main() {
    # 显示安装信息
    print_header "Matrix ESS Community 部署脚本"
    print_info "版本: $SCRIPT_VERSION"
    print_info "ESS版本: $ESS_VERSION"
    echo

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

                # 显示当前公网IP
                local current_ip=$(dig +short ip.$MAIN_DOMAIN @8.8.8.8 2>/dev/null || dig +short ip.$MAIN_DOMAIN @1.1.1.1 2>/dev/null)
                if [[ -n "$current_ip" && "$current_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "  当前公网IP: $current_ip"
                else
                    echo "  当前公网IP: 未获取到 (请检查DNS配置)"
                fi
                echo

                if confirm "确认开始部署" "y"; then
                    # 调用部署脚本
                    local deploy_script="$SCRIPT_DIR/deploy.sh"

                    # 确保部署脚本存在
                    if [[ ! -f "$deploy_script" ]]; then
                        if [[ "$INSTALL_METHOD" == "curl" ]]; then
                            print_info "部署脚本不存在，重新下载..."
                            local base_url="https://raw.githubusercontent.com/niublab/aiya/main/16.30-06.13-2025"
                            if curl -fsSL "$base_url/deploy.sh" -o "$deploy_script"; then
                                chmod +x "$deploy_script"
                                print_success "部署脚本下载完成"
                            else
                                print_error "无法下载部署脚本"
                                print_info "请检查网络连接或手动下载"
                                return 1
                            fi
                        else
                            print_error "未找到部署脚本: $deploy_script"
                            return 1
                        fi
                    fi

                    print_success "开始自动部署..."
                    print_info "部署脚本: $deploy_script"
                    print_info "工作目录: $SCRIPT_DIR"

                    # 切换到脚本目录执行，确保路径正确
                    cd "$SCRIPT_DIR"
                    ./deploy.sh
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

# ==================== ESS官方推荐的外部反向代理配置 ====================

setup_external_reverse_proxy() {
    print_step "配置外部反向代理 (ESS官方推荐方式)"

    print_info "ESS官方推荐架构:"
    echo "  Internet (自定义端口) → Nginx (SSL终止) → Traefik (标准端口) → ESS Services"
    echo

    # 安装Nginx
    install_nginx_for_ess

    # 生成Nginx配置
    generate_nginx_reverse_proxy_config

    # 配置Nginx
    configure_nginx_for_ess

    print_info "外部反向代理配置完成"
    print_warning "注意: ESS配置已自动调整为外部SSL模式 (tlsEnabled: false)"
}

install_nginx_for_ess() {
    print_info "安装Nginx (ESS外部反向代理)..."

    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        local os_id=$ID
    else
        print_error "无法检测操作系统"
        return 1
    fi

    # 安装Nginx
    case $os_id in
        ubuntu|debian)
            apt-get update
            apt-get install -y nginx openssl
            ;;
        centos|rhel|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y nginx openssl
            else
                yum install -y nginx openssl
            fi
            ;;
        *)
            print_error "不支持的操作系统: $os_id"
            return 1
            ;;
    esac

    print_success "Nginx安装完成"
}



generate_nginx_reverse_proxy_config() {
    print_info "生成Nginx反向代理配置 (ESS官方推荐)..."

    local nginx_config="$INSTALL_DIR/nginx-ess-reverse-proxy.conf"

    cat > "$nginx_config" << EOF
# ESS官方推荐的Nginx反向代理配置
# 架构: Internet → Nginx (SSL终止) → Traefik (8080) → ESS Services
# 生成时间: $(date)

# HTTP重定向到HTTPS
server {
    listen $HTTP_PORT;
    listen [::]:$HTTP_PORT;
    server_name $WEB_HOST $AUTH_HOST $RTC_HOST $SYNAPSE_HOST $SERVER_NAME;

    # 重定向到HTTPS (保持自定义端口)
    return 301 https://\$host:$HTTPS_PORT\$request_uri;
}

# HTTPS反向代理主配置 (SSL终止)
server {
    listen $HTTPS_PORT ssl http2;
    listen [::]:$HTTPS_PORT ssl http2;

    server_name $WEB_HOST $AUTH_HOST $RTC_HOST $SYNAPSE_HOST $SERVER_NAME;

    # SSL配置选项 (用户可选择)
    # 选项1: 使用Let's Encrypt证书 (如果已申请) - 推荐
    # ssl_certificate /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$SERVER_NAME/privkey.pem;

    # 选项2: 使用自定义证书
    # ssl_certificate /etc/ssl/certs/ess-custom.crt;
    # ssl_certificate_key /etc/ssl/private/ess-custom.key;

    # 选项3: 使用临时自签名证书 (默认)
    ssl_certificate /etc/nginx/ssl/ess-selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/ess-selfsigned.key;

    # SSL安全配置 (ESS官方推荐)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头 (Matrix推荐)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 日志配置
    access_log /var/log/nginx/ess-access.log;
    error_log /var/log/nginx/ess-error.log;

    # 反向代理到Traefik (ESS官方推荐方式)
    location / {
        # 转发到K3s Traefik HTTP端口 (官方推荐)
        proxy_pass http://127.0.0.1:8080;

        # 代理头设置 (ESS官方示例)
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port $HTTPS_PORT;

        # WebSocket支持 (Element Web需要)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时和缓冲设置 (ESS官方推荐)
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 86400s;  # 长连接支持
        proxy_buffering off;
        proxy_request_buffering off;

        # Matrix文件上传限制
        client_max_body_size 50M;
    }
}

# Matrix联邦端口配置 (如果使用自定义端口)
server {
    listen $FEDERATION_PORT ssl http2;
    listen [::]:$FEDERATION_PORT ssl http2;

    server_name $SYNAPSE_HOST $SERVER_NAME;

    # 使用相同的SSL证书
    ssl_certificate /etc/nginx/ssl/ess-selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/ess-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    # 联邦流量转发到Traefik
    location / {
        # 转发到Traefik，依赖Traefik路由到正确的联邦端点
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # 联邦超时设置
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

    print_success "Nginx反向代理配置生成: $nginx_config"
}

configure_nginx_for_ess() {
    print_info "配置Nginx反向代理..."

    # 创建SSL目录
    mkdir -p /etc/nginx/ssl

    # 生成临时自签名证书 (如果不存在)
    if [[ ! -f /etc/nginx/ssl/ess-selfsigned.crt ]]; then
        print_info "生成临时自签名SSL证书..."
        print_warning "注意: 这是临时证书，建议后续配置正式证书"

        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/ess-selfsigned.key \
            -out /etc/nginx/ssl/ess-selfsigned.crt \
            -subj "/C=US/ST=State/L=City/O=Matrix ESS Community/CN=$SERVER_NAME" \
            -extensions v3_req \
            -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C=US
ST=State
L=City
O=Matrix ESS Community
CN=$SERVER_NAME

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $SERVER_NAME
DNS.2 = $WEB_HOST
DNS.3 = $AUTH_HOST
DNS.4 = $RTC_HOST
DNS.5 = $SYNAPSE_HOST
EOF
)
        print_success "临时SSL证书生成完成"
    fi

    # 备份原配置
    if [[ -f /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # 复制ESS反向代理配置
    cp "$INSTALL_DIR/nginx-ess-reverse-proxy.conf" /etc/nginx/sites-available/ess-reverse-proxy 2>/dev/null || \
    cp "$INSTALL_DIR/nginx-ess-reverse-proxy.conf" /etc/nginx/conf.d/ess-reverse-proxy.conf

    # 启用站点 (Ubuntu/Debian)
    if [[ -d /etc/nginx/sites-enabled ]]; then
        ln -sf /etc/nginx/sites-available/ess-reverse-proxy /etc/nginx/sites-enabled/
        # 禁用默认站点以避免冲突
        rm -f /etc/nginx/sites-enabled/default
    fi

    # 测试配置
    if nginx -t; then
        print_success "Nginx配置测试通过"
    else
        print_error "Nginx配置测试失败"
        return 1
    fi

    # 启动Nginx服务
    systemctl enable nginx
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        print_success "Nginx反向代理启动成功"

        # 显示配置信息
        show_reverse_proxy_info

        # 记录配置状态
        echo "NGINX_REVERSE_PROXY=true" >> "$CONFIG_FILE"
        echo "NGINX_CONFIG_PATH=/etc/nginx/sites-available/ess-reverse-proxy" >> "$CONFIG_FILE"
        echo "ESS_EXTERNAL_SSL=true" >> "$CONFIG_FILE"
    else
        print_error "Nginx反向代理启动失败"
        return 1
    fi
}

show_reverse_proxy_info() {
    echo
    print_success "ESS外部反向代理配置完成！"
    echo
    print_info "架构说明 (ESS官方推荐):"
    echo "  Internet → Nginx (端口 $HTTP_PORT/$HTTPS_PORT) → Traefik (端口 8080/8443) → ESS Services"
    echo
    print_info "访问地址:"
    echo "  Element Web: https://$WEB_HOST:$HTTPS_PORT"
    echo "  认证服务: https://$AUTH_HOST:$HTTPS_PORT"
    echo "  RTC服务: https://$RTC_HOST:$HTTPS_PORT"
    echo "  Synapse: https://$SYNAPSE_HOST:$HTTPS_PORT"
    echo
    print_info "SSL证书配置:"
    echo "  当前使用: 临时自签名证书"
    echo "  推荐配置: Let's Encrypt或自定义证书"
    echo
    print_warning "SSL证书选项 (编辑 /etc/nginx/sites-available/ess-reverse-proxy):"
    echo "  1. Let's Encrypt: 取消注释 letsencrypt 行"
    echo "  2. 自定义证书: 取消注释 custom 行并配置路径"
    echo "  3. 保持当前: 使用临时自签名证书"
    echo
    print_success "✅ 如果已有Let's Encrypt证书，可以直接使用，无需删除！"
    echo "     只需编辑配置文件，取消注释对应的ssl_certificate行即可"
    echo
    print_info "配置文件位置:"
    echo "  Nginx配置: /etc/nginx/sites-available/ess-reverse-proxy"
    echo "  ESS外部SSL: $INSTALL_DIR/ess-external-ssl.yaml"
}

# 运行主程序
main "$@"
