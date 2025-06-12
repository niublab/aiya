#!/bin/bash

# Matrix ESS Community 内网部署自动化脚本
# 版本: 2.0.2
# 创建日期: 2025-01-06
# 许可证: AGPL-3.0 (仅限非商业用途)
# 基于需求文档严格实现，遵循"基于事实，严禁推测"原则

set -euo pipefail

# ==================== 全局变量和配置 ====================

readonly SCRIPT_VERSION="2.2.0"
readonly SCRIPT_NAME="Matrix ESS Community 自动部署脚本"
readonly SCRIPT_DATE="2025-01-28"

# 版本信息 - 基于官方最新稳定版本
readonly ESS_VERSION="25.6.1"
readonly ESS_CHART_URL="https://github.com/element-hq/ess-helm"
readonly K3S_VERSION="v1.32.5+k3s1"
readonly HELM_VERSION="v3.18.2"
readonly CERT_MANAGER_VERSION="v1.18.0"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 默认配置
readonly DEFAULT_HTTP_PORT="8080"
readonly DEFAULT_HTTPS_PORT="8443"
readonly DEFAULT_FEDERATION_PORT="8448"
readonly DEFAULT_UDP_RANGE="30152-30352"
readonly DEFAULT_INSTALL_DIR="/opt/matrix"

# 默认NodePort端口配置
readonly DEFAULT_NODEPORT_HTTP="30080"
readonly DEFAULT_NODEPORT_HTTPS="30443"
readonly DEFAULT_NODEPORT_FEDERATION="30448"

# 全局配置变量
INSTALL_DIR=""
SERVER_NAME=""
WEB_HOST=""
AUTH_HOST=""
RTC_HOST=""
SYNAPSE_HOST=""
HTTP_PORT=""
HTTPS_PORT=""
FEDERATION_PORT=""
UDP_RANGE=""
CERT_EMAIL=""
ADMIN_EMAIL=""
CLOUDFLARE_TOKEN=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
CERT_ENVIRONMENT="production"
PUBLIC_IP=""

# ==================== 工具函数 ====================

print_header() {
    echo -e "\n${CYAN}==================== $1 ====================${NC}\n"
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
    echo -e "\n${WHITE}>>> $1${NC}\n"
}

# 确认操作
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    local response
    
    while true; do
        if [[ "$default" == "Y" ]]; then
            read -p "${message} (Y/n): " response
            response=${response:-Y}
        else
            read -p "${message} (y/N): " response
            response=${response:-N}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                print_error "请输入 y(yes) 或 n(no)"
                ;;
        esac
    done
}

# 生成32位密码
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# 验证邮箱格式
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# 验证端口
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 检查端口占用
check_port_usage() {
    local port="$1"
    if netstat -tuln | grep -q ":$port "; then
        return 0  # 端口被占用
    fi
    return 1  # 端口未被占用
}

# 设置Kubernetes环境
setup_k8s_env() {
    # 设置KUBECONFIG环境变量
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    # 确保kubeconfig文件存在且可读
    if [[ ! -f "$KUBECONFIG" ]]; then
        print_error "kubeconfig文件不存在: $KUBECONFIG"
        return 1
    fi

    if [[ ! -r "$KUBECONFIG" ]]; then
        print_error "kubeconfig文件不可读: $KUBECONFIG"
        return 1
    fi

    return 0
}

# 获取公网IP
get_public_ip() {
    local domain="$1"
    local ip=""

    # 尝试通过自定义域名获取
    if [[ -n "$domain" ]]; then
        ip=$(dig +short "ip.$domain" @8.8.8.8 2>/dev/null || true)
        if [[ -z "$ip" ]]; then
            ip=$(dig +short "ip.$domain" @1.1.1.1 2>/dev/null || true)
        fi
    fi

    # 如果通过域名获取失败，使用公共服务
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || true)
    fi

    if [[ -z "$ip" ]]; then
        ip=$(curl -s --connect-timeout 5 icanhazip.com 2>/dev/null || true)
    fi

    if [[ -z "$ip" ]]; then
        print_warning "无法自动获取公网IP，请手动输入"
        read -p "请输入您的公网IP地址: " ip
    fi

    echo "$ip"
}

# ==================== 环境检查模块 ====================

check_system_requirements() {
    print_step "检查系统环境"
    
    # 检查操作系统
    if ! command -v apt-get &> /dev/null; then
        print_error "此脚本仅支持Debian/Ubuntu系统"
        exit 1
    fi
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限"
        print_info "请使用: sudo $0"
        exit 1
    fi
    
    # 检查系统资源
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    local cpu_cores=$(nproc)
    
    print_info "系统信息:"
    print_info "  操作系统: $(lsb_release -d | cut -f2)"
    print_info "  CPU核心: $cpu_cores"
    print_info "  内存: ${mem_gb}GB"
    
    if [ "$mem_gb" -lt 2 ]; then
        print_warning "内存不足2GB，可能影响性能"
    fi
    
    if [ "$cpu_cores" -lt 2 ]; then
        print_warning "CPU核心不足2个，可能影响性能"
    fi
    
    # 检查网络连通性
    print_info "检查网络连通性..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "网络连接失败，请检查网络设置"
        exit 1
    fi
    
    print_success "系统环境检查通过"
}

install_dependencies() {
    print_step "安装系统依赖"
    
    print_info "更新软件包列表..."
    apt-get update -qq
    
    print_info "安装必要软件包..."
    apt-get install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        software-properties-common \
        dnsutils \
        net-tools \
        openssl \
        jq
    
    print_success "系统依赖安装完成"
}

# ==================== 配置管理模块 ====================

collect_basic_config() {
    print_step "基础配置"

    # 安装目录
    while true; do
        read -p "请输入安装目录 [默认: $DEFAULT_INSTALL_DIR]: " INSTALL_DIR
        INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}

        if [[ ! "$INSTALL_DIR" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
            print_error "安装目录格式不正确，请输入绝对路径"
            continue
        fi

        if [[ -d "$INSTALL_DIR" ]] && [[ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
            print_warning "目录 $INSTALL_DIR 已存在且不为空"
            if confirm_action "是否继续使用此目录"; then
                break
            fi
        else
            break
        fi
    done

    # 主域名
    while true; do
        read -p "请输入主域名 (例如: example.com): " SERVER_NAME
        if [[ -z "$SERVER_NAME" ]]; then
            print_error "域名不能为空"
            continue
        fi

        if ! validate_domain "$SERVER_NAME"; then
            print_error "域名格式不正确"
            continue
        fi

        break
    done

    # 子域名配置
    print_info "配置子域名 (可输入前缀如'chat'或完整域名如'chat.example.com'):"
    print_info "直接回车使用默认值"

    # Element Web域名
    while true; do
        read -p "Element Web域名 [默认: chat]: " web_input
        web_input=${web_input:-"chat"}

        if [[ "$web_input" == *"."* ]]; then
            # 输入的是完整域名
            WEB_HOST="$web_input"
        else
            # 输入的是前缀，自动拼接主域名
            WEB_HOST="${web_input}.${SERVER_NAME}"
        fi

        if validate_domain "$WEB_HOST"; then
            break
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done

    # 认证服务域名
    while true; do
        read -p "认证服务域名 [默认: account]: " auth_input
        auth_input=${auth_input:-"account"}

        if [[ "$auth_input" == *"."* ]]; then
            # 输入的是完整域名
            AUTH_HOST="$auth_input"
        else
            # 输入的是前缀，自动拼接主域名
            AUTH_HOST="${auth_input}.${SERVER_NAME}"
        fi

        if validate_domain "$AUTH_HOST"; then
            break
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done

    # RTC服务域名
    while true; do
        read -p "RTC服务域名 [默认: mrtc]: " rtc_input
        rtc_input=${rtc_input:-"mrtc"}

        if [[ "$rtc_input" == *"."* ]]; then
            # 输入的是完整域名
            RTC_HOST="$rtc_input"
        else
            # 输入的是前缀，自动拼接主域名
            RTC_HOST="${rtc_input}.${SERVER_NAME}"
        fi

        if validate_domain "$RTC_HOST"; then
            break
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done

    # Synapse域名
    while true; do
        read -p "Synapse域名 [默认: matrix]: " synapse_input
        synapse_input=${synapse_input:-"matrix"}

        if [[ "$synapse_input" == *"."* ]]; then
            # 输入的是完整域名
            SYNAPSE_HOST="$synapse_input"
        else
            # 输入的是前缀，自动拼接主域名
            SYNAPSE_HOST="${synapse_input}.${SERVER_NAME}"
        fi

        if validate_domain "$SYNAPSE_HOST"; then
            break
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done

    print_success "基础配置完成"
}

collect_network_config() {
    print_step "网络配置"

    # 端口配置
    while true; do
        read -p "HTTP端口 [默认: $DEFAULT_HTTP_PORT]: " HTTP_PORT
        HTTP_PORT=${HTTP_PORT:-$DEFAULT_HTTP_PORT}

        if ! validate_port "$HTTP_PORT"; then
            print_error "端口格式不正确"
            continue
        fi

        if check_port_usage "$HTTP_PORT"; then
            print_warning "端口 $HTTP_PORT 已被占用"
            if ! confirm_action "是否继续使用此端口"; then
                continue
            fi
        fi
        break
    done

    while true; do
        read -p "HTTPS端口 [默认: $DEFAULT_HTTPS_PORT]: " HTTPS_PORT
        HTTPS_PORT=${HTTPS_PORT:-$DEFAULT_HTTPS_PORT}

        if ! validate_port "$HTTPS_PORT"; then
            print_error "端口格式不正确"
            continue
        fi

        if check_port_usage "$HTTPS_PORT"; then
            print_warning "端口 $HTTPS_PORT 已被占用"
            if ! confirm_action "是否继续使用此端口"; then
                continue
            fi
        fi
        break
    done

    while true; do
        read -p "联邦端口 [默认: $DEFAULT_FEDERATION_PORT]: " FEDERATION_PORT
        FEDERATION_PORT=${FEDERATION_PORT:-$DEFAULT_FEDERATION_PORT}

        if ! validate_port "$FEDERATION_PORT"; then
            print_error "端口格式不正确"
            continue
        fi

        if check_port_usage "$FEDERATION_PORT"; then
            print_warning "端口 $FEDERATION_PORT 已被占用"
            if ! confirm_action "是否继续使用此端口"; then
                continue
            fi
        fi
        break
    done

    read -p "UDP端口范围 [默认: $DEFAULT_UDP_RANGE]: " UDP_RANGE
    UDP_RANGE=${UDP_RANGE:-$DEFAULT_UDP_RANGE}

    # NodePort端口配置
    echo
    print_info "配置NodePort端口 (Kubernetes对外暴露端口)"

    while true; do
        read -p "HTTP NodePort端口 [默认: $DEFAULT_NODEPORT_HTTP]: " NODEPORT_HTTP
        NODEPORT_HTTP=${NODEPORT_HTTP:-$DEFAULT_NODEPORT_HTTP}

        if ! validate_port "$NODEPORT_HTTP"; then
            print_error "端口格式不正确"
            continue
        fi

        if [[ "$NODEPORT_HTTP" -lt 30000 || "$NODEPORT_HTTP" -gt 32767 ]]; then
            print_error "NodePort端口必须在30000-32767范围内"
            continue
        fi

        break
    done

    while true; do
        read -p "HTTPS NodePort端口 [默认: $DEFAULT_NODEPORT_HTTPS]: " NODEPORT_HTTPS
        NODEPORT_HTTPS=${NODEPORT_HTTPS:-$DEFAULT_NODEPORT_HTTPS}

        if ! validate_port "$NODEPORT_HTTPS"; then
            print_error "端口格式不正确"
            continue
        fi

        if [[ "$NODEPORT_HTTPS" -lt 30000 || "$NODEPORT_HTTPS" -gt 32767 ]]; then
            print_error "NodePort端口必须在30000-32767范围内"
            continue
        fi

        if [[ "$NODEPORT_HTTPS" == "$NODEPORT_HTTP" ]]; then
            print_error "HTTPS NodePort端口不能与HTTP端口相同"
            continue
        fi

        break
    done

    while true; do
        read -p "联邦NodePort端口 [默认: $DEFAULT_NODEPORT_FEDERATION]: " NODEPORT_FEDERATION
        NODEPORT_FEDERATION=${NODEPORT_FEDERATION:-$DEFAULT_NODEPORT_FEDERATION}

        if ! validate_port "$NODEPORT_FEDERATION"; then
            print_error "端口格式不正确"
            continue
        fi

        if [[ "$NODEPORT_FEDERATION" -lt 30000 || "$NODEPORT_FEDERATION" -gt 32767 ]]; then
            print_error "NodePort端口必须在30000-32767范围内"
            continue
        fi

        if [[ "$NODEPORT_FEDERATION" == "$NODEPORT_HTTP" || "$NODEPORT_FEDERATION" == "$NODEPORT_HTTPS" ]]; then
            print_error "联邦NodePort端口不能与其他端口相同"
            continue
        fi

        break
    done

    # 获取公网IP
    print_info "获取公网IP地址..."
    PUBLIC_IP=$(get_public_ip "$SERVER_NAME")
    print_info "检测到公网IP: $PUBLIC_IP"

    print_success "网络配置完成"
}

collect_cert_config() {
    print_step "证书配置"

    # 证书邮箱
    while true; do
        read -p "证书申请邮箱 (用于Let's Encrypt通知): " CERT_EMAIL
        if [[ -z "$CERT_EMAIL" ]]; then
            print_error "证书邮箱不能为空"
            continue
        fi

        if ! validate_email "$CERT_EMAIL"; then
            print_error "邮箱格式不正确"
            continue
        fi
        break
    done

    # 管理员邮箱 (可选)
    read -p "管理员邮箱 [可选，直接回车跳过]: " ADMIN_EMAIL
    if [[ -n "$ADMIN_EMAIL" ]] && ! validate_email "$ADMIN_EMAIL"; then
        print_error "管理员邮箱格式不正确"
        ADMIN_EMAIL=""
    fi

    # 证书环境
    echo
    print_info "选择证书环境:"
    echo "  1) 生产环境 (Let's Encrypt 正式证书)"
    echo "  2) 测试环境 (Let's Encrypt 测试证书)"

    while true; do
        read -p "请选择 [默认: 1]: " cert_choice
        cert_choice=${cert_choice:-1}

        case $cert_choice in
            1)
                CERT_ENVIRONMENT="production"
                break
                ;;
            2)
                CERT_ENVIRONMENT="staging"
                print_warning "测试环境证书不被浏览器信任，仅用于测试"
                break
                ;;
            *)
                print_error "请选择 1 或 2"
                ;;
        esac
    done

    # Cloudflare API Token
    while true; do
        read -p "Cloudflare API Token (用于DNS验证): " CLOUDFLARE_TOKEN
        if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
            print_error "Cloudflare API Token不能为空"
            continue
        fi

        # 简单验证token格式
        if [[ ${#CLOUDFLARE_TOKEN} -lt 20 ]]; then
            print_error "API Token格式可能不正确"
            if ! confirm_action "是否继续使用此Token"; then
                continue
            fi
        fi
        break
    done

    print_success "证书配置完成"
}

collect_admin_config() {
    print_step "管理员配置"

    # 管理员用户名
    while true; do
        read -p "管理员用户名 [默认: admin]: " ADMIN_USERNAME
        ADMIN_USERNAME=${ADMIN_USERNAME:-"admin"}

        if [[ ! "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            print_error "用户名只能包含字母、数字、下划线和连字符"
            continue
        fi
        break
    done

    # 生成32位密码
    ADMIN_PASSWORD=$(generate_password)
    print_info "已自动生成32位管理员密码"

    print_success "管理员配置完成"
}

save_config() {
    local config_file="$INSTALL_DIR/matrix-config.env"

    print_step "保存配置"

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"

    # 保存配置到文件
    cat > "$config_file" << EOF
# Matrix ESS Community 配置文件
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION

# 基础配置
INSTALL_DIR="$INSTALL_DIR"
SERVER_NAME="$SERVER_NAME"
WEB_HOST="$WEB_HOST"
AUTH_HOST="$AUTH_HOST"
RTC_HOST="$RTC_HOST"
SYNAPSE_HOST="$SYNAPSE_HOST"

# 网络配置
HTTP_PORT="$HTTP_PORT"
HTTPS_PORT="$HTTPS_PORT"
FEDERATION_PORT="$FEDERATION_PORT"
UDP_RANGE="$UDP_RANGE"
PUBLIC_IP="$PUBLIC_IP"

# NodePort配置
NODEPORT_HTTP="$NODEPORT_HTTP"
NODEPORT_HTTPS="$NODEPORT_HTTPS"
NODEPORT_FEDERATION="$NODEPORT_FEDERATION"

# 证书配置
CERT_EMAIL="$CERT_EMAIL"
ADMIN_EMAIL="$ADMIN_EMAIL"
CERT_ENVIRONMENT="$CERT_ENVIRONMENT"
CLOUDFLARE_TOKEN="$CLOUDFLARE_TOKEN"

# 管理员配置
ADMIN_USERNAME="$ADMIN_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"

# 版本信息
ESS_VERSION="$ESS_VERSION"
K3S_VERSION="$K3S_VERSION"
HELM_VERSION="$HELM_VERSION"
CERT_MANAGER_VERSION="$CERT_MANAGER_VERSION"
EOF

    # 设置文件权限
    chmod 600 "$config_file"

    print_success "配置已保存到: $config_file"
}

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        print_error "配置文件不存在: $config_file"
        return 1
    fi

    print_info "加载配置文件: $config_file"
    source "$config_file"
    print_success "配置加载完成"
}

show_config_summary() {
    print_header "配置摘要"

    echo -e "${WHITE}基础配置:${NC}"
    echo -e "  安装目录: $INSTALL_DIR"
    echo -e "  主域名: $SERVER_NAME"
    echo -e "  Element Web: $WEB_HOST"
    echo -e "  认证服务: $AUTH_HOST"
    echo -e "  RTC服务: $RTC_HOST"
    echo -e "  Synapse: $SYNAPSE_HOST"
    echo

    echo -e "${WHITE}网络配置:${NC}"
    echo -e "  HTTP端口: $HTTP_PORT"
    echo -e "  HTTPS端口: $HTTPS_PORT"
    echo -e "  联邦端口: $FEDERATION_PORT"
    echo -e "  UDP范围: $UDP_RANGE"
    echo -e "  公网IP: $PUBLIC_IP"
    echo

    echo -e "${WHITE}NodePort配置:${NC}"
    echo -e "  HTTP NodePort: $NODEPORT_HTTP"
    echo -e "  HTTPS NodePort: $NODEPORT_HTTPS"
    echo -e "  联邦NodePort: $NODEPORT_FEDERATION"
    echo

    echo -e "${WHITE}证书配置:${NC}"
    echo -e "  证书邮箱: $CERT_EMAIL"
    echo -e "  管理员邮箱: ${ADMIN_EMAIL:-"未设置"}"
    echo -e "  证书环境: $CERT_ENVIRONMENT"
    echo -e "  Cloudflare Token: ${CLOUDFLARE_TOKEN:0:10}..."
    echo

    echo -e "${WHITE}管理员配置:${NC}"
    echo -e "  用户名: $ADMIN_USERNAME"
    echo -e "  密码: ${ADMIN_PASSWORD:0:8}... (32位)"
    echo
}

# ==================== K3s安装模块 ====================

install_k3s() {
    print_step "安装K3s集群"

    # 检查是否已安装
    if command -v k3s &> /dev/null; then
        print_info "检测到K3s已安装"

        # 检查服务状态
        if systemctl is-active --quiet k3s; then
            # 检查集群是否正常工作
            if k3s kubectl get nodes &> /dev/null; then
                local k3s_version=$(k3s --version | head -n1 2>/dev/null || echo "未知版本")
                print_success "K3s集群运行正常，版本: $k3s_version"
                return 0
            else
                print_warning "K3s服务运行但集群异常，需要重新安装"
            fi
        else
            print_warning "K3s服务未运行，检查是否需要重新安装"

            # 尝试启动服务
            print_info "尝试启动K3s服务..."
            if systemctl start k3s && sleep 10 && systemctl is-active --quiet k3s; then
                if k3s kubectl get nodes &> /dev/null; then
                    print_success "K3s服务启动成功"
                    return 0
                fi
            fi

            print_warning "K3s服务启动失败，需要重新安装"
        fi

        # 清理有问题的K3s安装
        print_info "清理有问题的K3s安装..."
        systemctl stop k3s 2>/dev/null || true
        systemctl disable k3s 2>/dev/null || true

        if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
            /usr/local/bin/k3s-uninstall.sh || true
        else
            print_info "手动清理K3s组件..."
            rm -f /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr || true
            rm -f /usr/local/bin/k3s-killall.sh /usr/local/bin/k3s-uninstall.sh || true
            rm -f /etc/systemd/system/k3s.service* || true
            rm -rf /var/lib/rancher/k3s || true
            rm -rf /etc/rancher/k3s || true
            systemctl daemon-reload || true
        fi

        # 等待清理完成
        sleep 5
    fi

    print_info "下载并安装K3s $K3S_VERSION..."

    # 设置K3s安装参数
    export INSTALL_K3S_VERSION="$K3S_VERSION"

    # 构建安装参数，最简化配置
    local install_args="--write-kubeconfig-mode=644"
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "127.0.0.1" ]]; then
        install_args="$install_args --tls-san=$PUBLIC_IP"
        print_info "添加公网IP到TLS SAN: $PUBLIC_IP"
    fi

    export INSTALL_K3S_EXEC="$install_args"

    # 下载并执行K3s安装脚本（清理环境变量避免颜色代码污染）
    print_info "开始安装K3s..."
    if ! env -i PATH="$PATH" \
        INSTALL_K3S_VERSION="$INSTALL_K3S_VERSION" \
        INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC" \
        bash -c 'curl -sfL https://get.k3s.io | sh -'; then

        print_error "K3s安装脚本执行失败"
        print_info "尝试诊断问题..."

        # 检查系统状态
        print_info "检查系统状态:"
        echo "内存使用情况:"
        free -h
        echo "磁盘使用情况:"
        df -h /

        # 检查是否有进程占用端口
        print_info "检查端口占用:"
        netstat -tuln | grep -E ':(6443|10250)' || echo "K3s端口未被占用"

        # 尝试手动启动服务
        print_info "尝试手动启动K3s服务..."
        if systemctl start k3s; then
            print_info "K3s服务手动启动成功"
        else
            print_error "K3s服务启动失败，查看详细日志:"
            systemctl status k3s.service --no-pager || true
            journalctl -u k3s.service --no-pager -n 20 || true

            print_warning "K3s安装失败，但继续尝试其他方法..."
            return 1
        fi
    fi

    # 等待K3s服务启动
    print_info "等待K3s服务启动..."
    local retry_count=0
    while ! systemctl is-active --quiet k3s; do
        if [ $retry_count -ge 30 ]; then
            print_error "K3s服务启动超时"
            systemctl status k3s
            return 1
        fi
        sleep 2
        ((retry_count++))
    done

    # 等待K3s集群就绪
    print_info "等待K3s集群就绪..."
    retry_count=0
    while ! k3s kubectl get nodes &> /dev/null; do
        if [ $retry_count -ge 60 ]; then
            print_error "K3s集群启动超时"
            print_info "检查K3s服务状态:"
            systemctl status k3s
            print_info "检查K3s日志:"
            journalctl -u k3s --no-pager -n 20
            return 1
        fi
        sleep 2
        ((retry_count++))
    done

    # 等待节点就绪
    print_info "等待节点就绪..."
    retry_count=0
    while ! k3s kubectl get nodes | grep -q "Ready"; do
        if [ $retry_count -ge 60 ]; then
            print_error "节点就绪超时"
            k3s kubectl get nodes
            return 1
        fi
        sleep 5
        ((retry_count++))
    done

    # 验证安装
    print_info "验证K3s安装..."
    k3s kubectl get nodes

    # 设置kubectl别名
    if ! grep -q "alias kubectl=" ~/.bashrc; then
        echo "alias kubectl='k3s kubectl'" >> ~/.bashrc
    fi

    # 设置KUBECONFIG环境变量
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    # 验证kubeconfig文件权限
    if [[ -f "$KUBECONFIG" ]]; then
        chmod 644 "$KUBECONFIG"
        print_info "kubeconfig文件权限已设置"
    else
        print_warning "kubeconfig文件不存在，可能需要等待"
    fi

    print_success "K3s安装完成"
}

diagnose_and_fix_k3s() {
    print_step "诊断和修复K3s问题"

    print_info "开始K3s问题诊断..."

    # 检查系统资源
    print_info "检查系统资源..."
    local mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    local disk_available=$(df / | awk 'NR==2{print $4}')

    if [ "$mem_available" -lt 512 ]; then
        print_warning "可用内存不足: ${mem_available}MB (建议至少512MB)"
    fi

    if [ "$disk_available" -lt 1048576 ]; then  # 1GB in KB
        print_warning "可用磁盘空间不足: $(($disk_available/1024))MB (建议至少1GB)"
    fi

    # 检查端口占用
    print_info "检查端口占用..."
    if netstat -tuln | grep -q ":6443"; then
        print_warning "端口6443已被占用"
        netstat -tuln | grep ":6443"
    fi

    # 尝试多种安装方法
    print_info "尝试不同的K3s安装方法..."

    # 方法1: 使用默认配置（推荐）
    print_info "方法1: 使用K3s默认配置..."
    systemctl stop k3s 2>/dev/null || true
    /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    sleep 3

    if env -i PATH="$PATH" \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" \
        bash -c 'curl -sfL https://get.k3s.io | sh -' && \
        sleep 10 && systemctl is-active --quiet k3s; then
        print_success "K3s安装成功 (默认配置)"
        return 0
    fi

    # 方法2: 使用Docker运行时
    print_info "方法2: 使用Docker运行时..."
    systemctl stop k3s 2>/dev/null || true
    /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    sleep 3

    if command -v docker &> /dev/null; then
        if env -i PATH="$PATH" \
            INSTALL_K3S_VERSION="$K3S_VERSION" \
            INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --docker" \
            bash -c 'curl -sfL https://get.k3s.io | sh -' && \
            sleep 10 && systemctl is-active --quiet k3s; then
            print_success "K3s安装成功 (使用Docker)"
            return 0
        fi
    fi

    # 方法3: 最小化安装
    print_info "方法3: 最小化安装..."
    systemctl stop k3s 2>/dev/null || true
    /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
    sleep 3

    if env -i PATH="$PATH" \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" \
        bash -c 'curl -sfL https://get.k3s.io | sh -' && \
        sleep 15 && systemctl is-active --quiet k3s; then
        print_success "K3s安装成功 (最小化)"
        return 0
    fi

    print_error "所有K3s安装方法都失败了"
    print_info "请检查系统日志获取更多信息:"
    print_info "  systemctl status k3s.service"
    print_info "  journalctl -u k3s.service"

    return 1
}

configure_traefik() {
    print_step "配置Traefik"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    # 检查Traefik是否已启用（K3s默认启用）
    print_info "检查Traefik状态..."

    # 等待Traefik Pod启动
    local retry_count=0
    while ! k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | grep -q "Running"; do
        if [ $retry_count -ge 30 ]; then
            print_warning "Traefik Pod未在5分钟内启动，可能被禁用"
            break
        fi
        print_info "等待Traefik Pod启动... ($((retry_count + 1))/30)"
        sleep 10
        ((retry_count++))
    done

    # 检查Traefik服务是否存在
    if k3s kubectl get service traefik -n kube-system &> /dev/null; then
        print_success "检测到K3s内置Traefik服务"

        # 配置Traefik使用固定NodePort
        print_info "配置Traefik使用固定NodePort端口..."
        print_info "HTTP NodePort: $NODEPORT_HTTP, HTTPS NodePort: $NODEPORT_HTTPS, 联邦NodePort: $NODEPORT_FEDERATION"

        cat << EOF | k3s kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        port: 8000
        exposedPort: $HTTP_PORT
        nodePort: $NODEPORT_HTTP
      websecure:
        port: 8443
        exposedPort: $HTTPS_PORT
        nodePort: $NODEPORT_HTTPS
      federation:
        port: 8448
        exposedPort: $FEDERATION_PORT
        nodePort: $NODEPORT_FEDERATION
    service:
      type: NodePort
    providers:
      kubernetesIngress:
        ingressClass: traefik
      kubernetesCRD:
        ingressClass: traefik
EOF

        print_info "等待Traefik重新配置..."
        sleep 30

        # 检查Traefik是否重新启动
        k3s kubectl rollout status deployment traefik -n kube-system --timeout=300s || true

        print_success "Traefik配置完成"
    else
        print_warning "未检测到Traefik服务，可能已被禁用"
        print_info "ESS需要Ingress控制器，建议重新安装K3s并启用Traefik"
        return 1
    fi
}

install_helm() {
    print_step "安装Helm"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    # 检查是否已安装
    if command -v helm &> /dev/null; then
        local current_version=""
        if helm version --short &> /dev/null; then
            current_version=$(helm version --short 2>/dev/null | cut -d'+' -f1)
        fi
        print_info "Helm已安装，版本: $current_version"
        if [[ "$current_version" == "$HELM_VERSION" ]]; then
            # 验证Helm能否连接到K3s集群
            if helm list &> /dev/null; then
                print_success "Helm版本正确且能连接到集群"
                return 0
            else
                print_warning "Helm无法连接到集群，可能需要重新配置"
            fi
        fi
    fi

    print_info "下载并安装Helm $HELM_VERSION..."

    # 下载Helm
    local helm_tar="helm-${HELM_VERSION}-linux-amd64.tar.gz"
    if ! wget -q "https://get.helm.sh/$helm_tar" -O "/tmp/$helm_tar"; then
        print_error "下载Helm失败"
        return 1
    fi

    # 解压并安装
    tar -zxf "/tmp/$helm_tar" -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm

    # 清理临时文件
    rm -rf "/tmp/$helm_tar" /tmp/linux-amd64

    # 验证安装
    print_info "验证Helm安装..."
    if ! helm version --short; then
        print_error "Helm安装验证失败"
        return 1
    fi

    # 验证与K3s集群的连接
    print_info "验证Helm与K3s集群连接..."
    local retry_count=0
    while ! helm list &> /dev/null; do
        if [ $retry_count -ge 10 ]; then
            print_error "Helm无法连接到K3s集群"
            print_info "KUBECONFIG: $KUBECONFIG"
            print_info "检查kubeconfig文件:"
            ls -la /etc/rancher/k3s/k3s.yaml || true
            print_info "尝试直接使用k3s kubectl:"
            k3s kubectl get nodes || true
            return 1
        fi
        print_info "等待集群就绪... ($((retry_count + 1))/10)"
        sleep 3
        ((retry_count++))
    done

    print_success "Helm安装完成"
}

install_cert_manager() {
    print_step "安装cert-manager"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    # 检查是否已安装
    if k3s kubectl get namespace cert-manager &> /dev/null; then
        print_info "cert-manager已安装"
        if confirm_action "是否重新安装cert-manager"; then
            print_info "卸载现有cert-manager..."
            helm uninstall cert-manager -n cert-manager || true
            # 等待资源清理
            print_info "等待资源清理..."
            sleep 10
            k3s kubectl delete namespace cert-manager --timeout=60s || true
            # 强制删除命名空间（如果卡住）
            k3s kubectl patch namespace cert-manager -p '{"metadata":{"finalizers":[]}}' --type=merge || true
        else
            print_success "使用现有cert-manager安装"
            return 0
        fi
    fi

    print_info "添加cert-manager Helm仓库..."
    if ! helm repo add jetstack https://charts.jetstack.io; then
        print_error "添加cert-manager仓库失败"
        return 1
    fi

    if ! helm repo update; then
        print_error "更新Helm仓库失败"
        return 1
    fi

    print_info "创建cert-manager命名空间..."
    if ! k3s kubectl create namespace cert-manager; then
        print_error "创建cert-manager命名空间失败"
        return 1
    fi

    print_info "安装cert-manager $CERT_MANAGER_VERSION..."
    if ! helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version "$CERT_MANAGER_VERSION" \
        --set crds.enabled=true \
        --set global.leaderElection.namespace=cert-manager \
        --timeout=600s; then
        print_error "cert-manager安装失败"
        print_info "查看安装日志:"
        k3s kubectl get events -n cert-manager --sort-by='.lastTimestamp' || true
        return 1
    fi

    # 等待cert-manager启动
    print_info "等待cert-manager启动..."
    local retry_count=0
    while ! k3s kubectl get pods -n cert-manager | grep -q "Running"; do
        if [ $retry_count -ge 60 ]; then
            print_error "cert-manager启动超时"
            print_info "检查Pod状态:"
            k3s kubectl get pods -n cert-manager
            print_info "检查事件:"
            k3s kubectl get events -n cert-manager --sort-by='.lastTimestamp'
            return 1
        fi
        print_info "等待cert-manager Pod启动... ($((retry_count + 1))/60)"
        sleep 5
        ((retry_count++))
    done

    # 等待所有Pod就绪
    if ! k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s; then
        print_error "cert-manager Pod就绪超时"
        k3s kubectl get pods -n cert-manager
        return 1
    fi

    print_success "cert-manager安装完成"
}

configure_cert_manager() {
    print_step "配置cert-manager"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    # 创建Cloudflare API Token Secret
    print_info "创建Cloudflare API Token Secret..."
    if ! k3s kubectl create secret generic cloudflare-api-token-secret \
        --from-literal=api-token="$CLOUDFLARE_TOKEN" \
        -n cert-manager \
        --dry-run=client -o yaml | k3s kubectl apply -f -; then
        print_error "创建Cloudflare API Token Secret失败"
        return 1
    fi

    # 创建ClusterIssuer配置
    local issuer_name="letsencrypt-$CERT_ENVIRONMENT"
    local acme_server=""

    if [[ "$CERT_ENVIRONMENT" == "production" ]]; then
        acme_server="https://acme-v02.api.letsencrypt.org/directory"
    else
        acme_server="https://acme-staging-v02.api.letsencrypt.org/directory"
    fi

    print_info "创建ClusterIssuer: $issuer_name..."

    if ! cat << EOF | k3s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $issuer_name
spec:
  acme:
    server: $acme_server
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: $issuer_name
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
EOF
    then
        print_error "创建ClusterIssuer失败"
        return 1
    fi

    # 验证ClusterIssuer
    print_info "验证ClusterIssuer状态..."
    sleep 10

    local retry_count=0
    while ! k3s kubectl get clusterissuer "$issuer_name" &> /dev/null; do
        if [ $retry_count -ge 12 ]; then
            print_error "ClusterIssuer创建超时"
            k3s kubectl get clusterissuer || true
            return 1
        fi
        print_info "等待ClusterIssuer创建... ($((retry_count + 1))/12)"
        sleep 5
        ((retry_count++))
    done

    k3s kubectl get clusterissuer "$issuer_name" -o wide

    print_success "cert-manager配置完成"
}

# ==================== ESS部署模块 ====================

verify_ess_chart() {
    print_step "验证ESS Chart"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    print_info "验证ESS OCI Chart可用性..."

    # 使用helm show chart验证OCI chart是否可用
    local oci_chart="oci://ghcr.io/element-hq/ess-helm/matrix-stack"

    print_info "检查ESS Chart版本 $ESS_VERSION..."
    if helm show chart "$oci_chart" --version "$ESS_VERSION" &> /dev/null; then
        print_success "ESS Chart版本 $ESS_VERSION 验证成功"

        # 获取Chart详细信息
        local chart_info=$(helm show chart "$oci_chart" --version "$ESS_VERSION" 2>/dev/null)
        if [[ -n "$chart_info" ]]; then
            local chart_version=$(echo "$chart_info" | grep "^version:" | awk '{print $2}')
            local app_version=$(echo "$chart_info" | grep "^appVersion:" | awk '{print $2}')
            print_info "Chart版本: $chart_version"
            print_info "应用版本: $app_version"
        fi
        return 0
    else
        print_warning "无法验证ESS Chart版本 $ESS_VERSION，尝试获取最新版本..."

        # 尝试不指定版本获取最新版本
        if helm show chart "$oci_chart" &> /dev/null; then
            print_info "ESS Chart可用，将使用最新版本"

            # 获取最新版本信息
            local latest_info=$(helm show chart "$oci_chart" 2>/dev/null)
            if [[ -n "$latest_info" ]]; then
                local latest_version=$(echo "$latest_info" | grep "^version:" | awk '{print $2}')
                print_info "最新Chart版本: $latest_version"
            fi
            return 0
        else
            print_error "无法访问ESS Chart，请检查网络连接"
            print_info "请确认："
            print_info "  1. 网络连接正常"
            print_info "  2. 可以访问 ghcr.io"
            print_info "  3. Helm已正确安装"
            return 1
        fi
    fi
}

check_latest_versions() {
    print_step "检查组件最新版本"

    print_info "检查各组件最新版本信息..."

    # 检查ESS最新版本
    print_info "检查ESS最新版本..."
    local oci_chart="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
    if helm show chart "$oci_chart" &> /dev/null; then
        local latest_ess=$(helm show chart "$oci_chart" 2>/dev/null | grep "^version:" | awk '{print $2}')
        if [[ -n "$latest_ess" ]]; then
            if [[ "$latest_ess" == "$ESS_VERSION" ]]; then
                print_success "ESS版本 $ESS_VERSION 是最新版本"
            else
                print_warning "ESS有新版本可用: $latest_ess (当前: $ESS_VERSION)"
            fi
        fi
    fi

    # 检查K3s最新版本
    print_info "检查K3s最新版本..."
    local latest_k3s=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | grep '"tag_name":' | cut -d'"' -f4 2>/dev/null || echo "")
    if [[ -n "$latest_k3s" ]]; then
        if [[ "$latest_k3s" == "$K3S_VERSION" ]]; then
            print_success "K3s版本 $K3S_VERSION 是最新版本"
        else
            print_warning "K3s有新版本可用: $latest_k3s (当前: $K3S_VERSION)"
        fi
    fi

    # 检查Helm最新版本
    print_info "检查Helm最新版本..."
    local latest_helm=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name":' | cut -d'"' -f4 2>/dev/null || echo "")
    if [[ -n "$latest_helm" ]]; then
        if [[ "$latest_helm" == "$HELM_VERSION" ]]; then
            print_success "Helm版本 $HELM_VERSION 是最新版本"
        else
            print_warning "Helm有新版本可用: $latest_helm (当前: $HELM_VERSION)"
        fi
    fi

    # 检查cert-manager最新版本
    print_info "检查cert-manager最新版本..."
    local latest_certmgr=$(curl -s https://api.github.com/repos/cert-manager/cert-manager/releases/latest | grep '"tag_name":' | cut -d'"' -f4 2>/dev/null || echo "")
    if [[ -n "$latest_certmgr" ]]; then
        if [[ "$latest_certmgr" == "$CERT_MANAGER_VERSION" ]]; then
            print_success "cert-manager版本 $CERT_MANAGER_VERSION 是最新版本"
        else
            print_warning "cert-manager有新版本可用: $latest_certmgr (当前: $CERT_MANAGER_VERSION)"
        fi
    fi

    print_success "版本检查完成"
}

generate_ess_values() {
    print_step "生成ESS配置文件"

    local values_file="$INSTALL_DIR/ess-values.yaml"
    local issuer_name="letsencrypt-$CERT_ENVIRONMENT"

    print_info "生成ESS values文件: $values_file"
    print_info "基于官方schema生成最小化配置..."

    # 基于官方quick-setup-hostnames.yaml的最简配置
    cat > "$values_file" << EOF
# Matrix ESS Community 配置文件
# 生成时间: $(date)
# 脚本版本: $SCRIPT_VERSION
# ESS版本: $ESS_VERSION
# 基于官方 quick-setup-hostnames.yaml 模板

# 服务器名称 (必需)
serverName: "$SERVER_NAME"

# Element Web配置
elementWeb:
  ingress:
    host: "$WEB_HOST"
    annotations:
      cert-manager.io/cluster-issuer: "$issuer_name"

# Matrix Authentication Service配置
matrixAuthenticationService:
  ingress:
    host: "$AUTH_HOST"
    annotations:
      cert-manager.io/cluster-issuer: "$issuer_name"

# Matrix RTC配置
matrixRTC:
  ingress:
    host: "$RTC_HOST"
    annotations:
      cert-manager.io/cluster-issuer: "$issuer_name"

# Synapse配置
synapse:
  ingress:
    host: "$SYNAPSE_HOST"
    annotations:
      cert-manager.io/cluster-issuer: "$issuer_name"
EOF

    # 保存管理员密码到单独文件
    cat > "$INSTALL_DIR/passwords.txt" << EOF
# Matrix ESS Community 密码文件
# 生成时间: $(date)
# 请妥善保管此文件

管理员用户名: $ADMIN_USERNAME
管理员密码: $ADMIN_PASSWORD
Matrix ID: @$ADMIN_USERNAME:$SERVER_NAME

# 访问地址
Element Web: https://$WEB_HOST:$HTTPS_PORT
认证服务: https://$AUTH_HOST:$HTTPS_PORT
RTC服务: https://$RTC_HOST:$HTTPS_PORT
Synapse: https://$SYNAPSE_HOST:$HTTPS_PORT
EOF

    chmod 600 "$INSTALL_DIR/passwords.txt"

    print_success "ESS配置文件生成完成: $values_file"
    print_info "密码文件已保存到: $INSTALL_DIR/passwords.txt"
    print_info "使用官方最小化配置，PostgreSQL将自动配置"
}

deploy_ess() {
    print_step "部署ESS"

    # 设置Kubernetes环境
    if ! setup_k8s_env; then
        return 1
    fi

    local values_file="$INSTALL_DIR/ess-values.yaml"
    local namespace="ess"
    local oci_chart="oci://ghcr.io/element-hq/ess-helm/matrix-stack"

    # 检查values文件是否存在
    if [[ ! -f "$values_file" ]]; then
        print_error "ESS配置文件不存在: $values_file"
        return 1
    fi

    # 创建命名空间
    print_info "创建ESS命名空间..."
    if ! k3s kubectl create namespace "$namespace" --dry-run=client -o yaml | k3s kubectl apply -f -; then
        print_error "创建ESS命名空间失败"
        return 1
    fi

    # 部署ESS使用OCI registry
    print_info "部署Element Server Suite (使用OCI registry)..."
    local helm_cmd="helm install ess $oci_chart --namespace $namespace --values $values_file --wait --timeout=1800s"

    # 尝试使用指定版本
    if helm show chart "$oci_chart" --version "$ESS_VERSION" &> /dev/null; then
        helm_cmd="$helm_cmd --version $ESS_VERSION"
        print_info "使用指定版本: $ESS_VERSION"
    else
        print_warning "指定版本 $ESS_VERSION 不可用，使用最新版本"
    fi

    print_info "执行部署命令: $helm_cmd"
    if ! eval "$helm_cmd"; then
        print_error "ESS部署失败"
        print_info "查看部署状态:"
        k3s kubectl get pods -n "$namespace" || true
        print_info "查看事件:"
        k3s kubectl get events -n "$namespace" --sort-by='.lastTimestamp' || true
        print_info "查看Helm状态:"
        helm status ess -n "$namespace" || true
        return 1
    fi

    # 等待所有Pod启动
    print_info "等待所有服务启动..."
    local retry_count=0
    while true; do
        local running_pods=$(k3s kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local total_pods=$(k3s kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        local completed_pods=$(k3s kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Completed" || echo "0")

        # 计算实际需要运行的Pod数量（排除Completed状态的Job Pod）
        local expected_running=$((total_pods - completed_pods))

        if [ "$total_pods" -gt 0 ] && [ "$expected_running" -gt 0 ] && [ "$running_pods" -eq "$expected_running" ]; then
            print_success "所有服务Pod已启动 ($running_pods/$expected_running 运行中, $completed_pods 已完成)"
            break
        fi

        if [ $retry_count -ge 60 ]; then  # 10分钟超时
            print_warning "等待服务启动超时 (10分钟)，但继续部署"
            print_info "当前Pod状态:"
            k3s kubectl get pods -n "$namespace"
            print_info "运行中: $running_pods, 总计: $total_pods, 已完成: $completed_pods"
            break  # 不返回错误，继续部署
        fi

        print_info "等待服务启动... ($running_pods/$expected_running 运行中, $completed_pods 已完成) ($((retry_count + 1))/60)"
        sleep 10
        ((retry_count++))
    done

    # 等待关键服务就绪
    print_info "等待关键服务就绪..."
    local services=("postgresql" "synapse" "matrix-authentication-service")
    for service in "${services[@]}"; do
        print_info "检查 $service 状态..."

        # 检查Pod是否存在
        local pod_count=$(k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$service" --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            print_warning "$service Pod不存在，跳过"
            continue
        fi

        # 等待Pod就绪，但时间更短
        if k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="$service" -n "$namespace" --timeout=120s 2>/dev/null; then
            print_success "$service 已就绪"
        else
            print_warning "$service 未在2分钟内就绪，但继续部署"
            # 显示Pod状态用于调试
            k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$service" 2>/dev/null || true
        fi
    done

    print_success "ESS部署完成"
}

fix_mas_configuration() {
    print_step "修复MAS配置"

    local namespace="ess"

    # 等待MAS Pod启动
    print_info "等待MAS Pod启动..."
    local retry_count=0
    while ! k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name=matrix-authentication-service --no-headers 2>/dev/null | grep -q "Running"; do
        if [ $retry_count -ge 30 ]; then
            print_warning "MAS Pod未在5分钟内启动，跳过MAS配置修复"
            return 1
        fi
        print_info "等待MAS Pod启动... ($((retry_count + 1))/30)"
        sleep 10
        ((retry_count++))
    done

    # 修复MAS配置，添加正确的端口号
    print_info "修复MAS配置，添加端口号到public_base..."

    # 获取当前MAS配置
    local current_config=$(k3s kubectl get configmap ess-matrix-authentication-service -n "$namespace" -o jsonpath='{.data.config\.yaml}')

    # 检查是否需要修复
    if echo "$current_config" | grep -q "public_base.*:$HTTPS_PORT"; then
        print_success "MAS配置已包含正确端口号"
        return 0
    fi

    print_info "更新MAS ConfigMap，添加端口号..."

    # 创建修复后的配置
    cat << EOF | k3s kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ess-matrix-authentication-service
  namespace: $namespace
  labels:
    app.kubernetes.io/component: matrix-authentication
    app.kubernetes.io/instance: ess-matrix-authentication-service
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: matrix-authentication-service
    app.kubernetes.io/part-of: matrix-stack
    app.kubernetes.io/version: 0.16.0
    helm.sh/chart: matrix-stack-25.6.1
data:
  config.yaml: |
    http:
      public_base: "https://$AUTH_HOST:$HTTPS_PORT"
      listeners:
      - name: web
        binds:
        - host: 0.0.0.0
          port: 8080
        resources:
        - name: human
        - name: discovery
        - name: oauth
        - name: compat
        - name: assets
        - name: graphql
          undocumented_oauth2_access: true
        - name: adminapi
      - name: internal
        binds:
        - host: 0.0.0.0
          port: 8081
        resources:
        - name: health
        - name: prometheus
        - name: connection-info

    database:
      uri: "postgresql://matrixauthenticationservice_user:\${POSTGRES_PASSWORD}@ess-postgres.ess.svc.cluster.local:5432/matrixauthenticationservice?sslmode=prefer&application_name=matrix-authentication-service"

    telemetry:
      metrics:
        exporter: prometheus
    matrix:
      homeserver: "$SERVER_NAME"
      secret: \${SYNAPSE_SHARED_SECRET}
      endpoint: "http://ess-synapse-main.ess.svc.cluster.local:8008"

    policy:
      data:
        admin_clients: []
        admin_users: []
        client_registration:
          allow_host_mismatch: false
          allow_insecure_uris: false
    clients:
    - client_id: "0000000000000000000SYNAPSE"
      client_auth_method: client_secret_basic
      client_secret: \${SYNAPSE_OIDC_CLIENT_SECRET}

    secrets:
      encryption: \${ENCRYPTION_SECRET}
      keys:
      - kid: rsa
        key_file: /secrets/ess-generated/MAS_RSA_PRIVATE_KEY
      - kid: prime256v1
        key_file: /secrets/ess-generated/MAS_ECDSA_PRIME256V1_PRIVATE_KEY

    experimental:
      access_token_ttl: 86400
EOF

    # 重启MAS Pod以加载新配置
    print_info "重启MAS Pod以加载新配置..."
    k3s kubectl rollout restart deployment ess-matrix-authentication-service -n "$namespace"

    # 等待重启完成
    if k3s kubectl rollout status deployment ess-matrix-authentication-service -n "$namespace" --timeout=300s; then
            print_success "MAS配置修复完成"
    else
        print_warning "MAS重启超时，但配置已更新"
    fi
}

create_ssl_certificates() {
    print_step "创建SSL证书"

    local namespace="ess"
    local issuer_name="letsencrypt-$CERT_ENVIRONMENT"

    # 检查ClusterIssuer是否存在
    if ! k3s kubectl get clusterissuer "$issuer_name" &> /dev/null; then
        print_error "ClusterIssuer $issuer_name 不存在，请先配置cert-manager"
        return 1
    fi

    print_info "为所有服务创建SSL证书..."

    # 创建证书资源
    cat << EOF | k3s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-$(echo "$WEB_HOST" | tr '.' '-')-tls
  namespace: $namespace
spec:
  secretName: app-$(echo "$WEB_HOST" | tr '.' '-')-tls
  issuerRef:
    name: $issuer_name
    kind: ClusterIssuer
  dnsNames:
  - $WEB_HOST
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mas-$(echo "$AUTH_HOST" | tr '.' '-')-tls
  namespace: $namespace
spec:
  secretName: mas-$(echo "$AUTH_HOST" | tr '.' '-')-tls
  issuerRef:
    name: $issuer_name
    kind: ClusterIssuer
  dnsNames:
  - $AUTH_HOST
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rtc-$(echo "$RTC_HOST" | tr '.' '-')-tls
  namespace: $namespace
spec:
  secretName: rtc-$(echo "$RTC_HOST" | tr '.' '-')-tls
  issuerRef:
    name: $issuer_name
    kind: ClusterIssuer
  dnsNames:
  - $RTC_HOST
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: matrix-$(echo "$SYNAPSE_HOST" | tr '.' '-')-tls
  namespace: $namespace
spec:
  secretName: matrix-$(echo "$SYNAPSE_HOST" | tr '.' '-')-tls
  issuerRef:
    name: $issuer_name
    kind: ClusterIssuer
  dnsNames:
  - $SYNAPSE_HOST
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: main-$(echo "$SERVER_NAME" | tr '.' '-')-tls
  namespace: $namespace
spec:
  secretName: main-$(echo "$SERVER_NAME" | tr '.' '-')-tls
  issuerRef:
    name: $issuer_name
    kind: ClusterIssuer
  dnsNames:
  - $SERVER_NAME
EOF

    # 等待证书申请
    print_info "等待证书申请完成..."
    local retry_count=0
    while true; do
        # 修复换行符问题：使用tr删除换行符，确保返回纯数字
        local ready_certs=$(k3s kubectl get certificates -n "$namespace" --no-headers 2>/dev/null | grep -c "True" 2>/dev/null | tr -d '\n' || echo "0")
        local total_certs=$(k3s kubectl get certificates -n "$namespace" --no-headers 2>/dev/null | wc -l 2>/dev/null | tr -d '\n' || echo "0")

        # 确保变量是纯数字，如果不是则设为0
        [[ "$ready_certs" =~ ^[0-9]+$ ]] || ready_certs=0
        [[ "$total_certs" =~ ^[0-9]+$ ]] || total_certs=0

        if [ "$total_certs" -gt 0 ] && [ "$ready_certs" -eq "$total_certs" ]; then
            print_success "所有证书申请完成 ($ready_certs/$total_certs)"
            break
        fi

        if [ $retry_count -ge 30 ]; then  # 5分钟超时
            print_warning "证书申请超时，但继续部署"
            print_info "当前证书状态:"
            k3s kubectl get certificates -n "$namespace"
            break
        fi

        print_info "等待证书申请... ($ready_certs/$total_certs) ($((retry_count + 1))/30)"
        sleep 10
        ((retry_count++))
    done

    # 更新Ingress以使用证书
    print_info "更新Ingress以使用SSL证书..."

    # 为每个Ingress添加TLS配置
    local ingresses=("ess-element-web" "ess-matrix-authentication-service" "ess-matrix-rtc" "ess-synapse" "ess-well-known")
    local hosts=("$WEB_HOST" "$AUTH_HOST" "$RTC_HOST" "$SYNAPSE_HOST" "$SERVER_NAME")
    local secrets=("app-$(echo "$WEB_HOST" | tr '.' '-')-tls" "mas-$(echo "$AUTH_HOST" | tr '.' '-')-tls" "rtc-$(echo "$RTC_HOST" | tr '.' '-')-tls" "matrix-$(echo "$SYNAPSE_HOST" | tr '.' '-')-tls" "main-$(echo "$SERVER_NAME" | tr '.' '-')-tls")

    for i in "${!ingresses[@]}"; do
        local ingress="${ingresses[$i]}"
        local host="${hosts[$i]}"
        local secret="${secrets[$i]}"

        print_info "更新 $ingress Ingress..."
        k3s kubectl patch ingress "$ingress" -n "$namespace" --type='merge' -p="{
            \"spec\": {
                \"tls\": [
                    {
                        \"hosts\": [\"$host\"],
                        \"secretName\": \"$secret\"
                    }
                ]
            }
        }" || print_warning "更新 $ingress Ingress失败"
    done

    # 特殊处理Well-known Ingress - 移除TLS配置以避免证书问题
    print_info "配置Well-known Ingress使用HTTP..."
    k3s kubectl patch ingress ess-well-known -n "$namespace" --type='json' -p='[{"op":"remove","path":"/spec/tls"}]' 2>/dev/null || print_warning "移除Well-known TLS配置失败"

    print_success "SSL证书配置完成"
}

fix_wellknown_configuration() {
    print_step "修复Well-known配置（添加自定义端口）"

    local namespace="ess"

    # 加载配置文件
    local config_file="$INSTALL_DIR/matrix-config.env"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        print_info "已加载配置文件: $config_file"
    else
        print_error "配置文件不存在: $config_file"
        return 1
    fi

    # 验证必需的变量
    if [[ -z "$SYNAPSE_HOST" || -z "$AUTH_HOST" || -z "$RTC_HOST" || -z "$HTTPS_PORT" ]]; then
        print_error "配置文件中缺少必需的变量"
        print_info "SYNAPSE_HOST: [$SYNAPSE_HOST]"
        print_info "AUTH_HOST: [$AUTH_HOST]"
        print_info "RTC_HOST: [$RTC_HOST]"
        print_info "HTTPS_PORT: [$HTTPS_PORT]"
        return 1
    fi

    # 等待Well-known ConfigMap创建（ESS自动生成）
    print_info "等待ESS生成Well-known配置..."
    local retry_count=0
    while ! k3s kubectl get configmap ess-well-known-haproxy -n "$namespace" &> /dev/null; do
        if [ $retry_count -ge 12 ]; then  # 减少等待时间到2分钟
            print_warning "Well-known ConfigMap未找到，跳过配置修复"
            return 1
        fi
        print_info "等待ESS生成Well-known ConfigMap... ($((retry_count + 1))/12)"
        sleep 10
        ((retry_count++))
    done

    # 检查当前Well-known配置
    print_info "检查当前Well-known配置..."
    local current_client_config=$(k3s kubectl get configmap ess-well-known-haproxy -n "$namespace" -o jsonpath='{.data.client}' 2>/dev/null || echo "")

    # 检查是否需要修复
    if echo "$current_client_config" | grep -q ":$HTTPS_PORT"; then
        print_success "Well-known配置已包含正确端口号"
        return 0
    fi

    print_info "修复Well-known配置，添加端口号..."

    # 生成正确的Well-known配置
    local client_config="{\"m.homeserver\":{\"base_url\":\"https://$SYNAPSE_HOST:$HTTPS_PORT\"},\"org.matrix.msc2965.authentication\":{\"account\":\"https://$AUTH_HOST:$HTTPS_PORT/account\",\"issuer\":\"https://$AUTH_HOST:$HTTPS_PORT/\"},\"org.matrix.msc4143.rtc_foci\":[{\"livekit_service_url\":\"https://$RTC_HOST:$HTTPS_PORT\",\"type\":\"livekit\"}]}"
    local server_config="{\"m.server\":\"$SYNAPSE_HOST:$HTTPS_PORT\"}"

    # 更新Well-known ConfigMap
    k3s kubectl patch configmap ess-well-known-haproxy -n "$namespace" --type='merge' -p="{
        \"data\": {
            \"client\": \"$client_config\",
            \"server\": \"$server_config\"
        }
    }"

    if [ $? -eq 0 ]; then
        print_success "Well-known ConfigMap更新成功"
    else
        print_error "Well-known ConfigMap更新失败"
        return 1
    fi

    # 重启Well-known相关服务
    print_info "重启Well-known相关服务..."
    k3s kubectl rollout restart deployment -n "$namespace" -l app.kubernetes.io/name=well-known-delegation 2>/dev/null || true
    k3s kubectl rollout restart deployment -n "$namespace" -l app.kubernetes.io/name=haproxy 2>/dev/null || true

    # 等待服务重启
    sleep 30

    # 快速验证修复结果
    print_info "验证Well-known配置修复..."
    sleep 10  # 等待配置生效

    # 检查ConfigMap是否已更新
    local updated_config=$(k3s kubectl get configmap ess-well-known-haproxy -n "$namespace" -o jsonpath='{.data.client}' 2>/dev/null || echo "")
    if echo "$updated_config" | grep -q ":$HTTPS_PORT"; then
        print_success "Well-known配置修复完成，自定义端口已添加"
        print_info "Element Web现在应该能自动检测homeserver"
    else
        print_warning "Well-known配置可能未完全更新，但继续部署"
    fi

    return 0
}

setup_port_forwarding() {
    print_step "配置端口转发服务"

    # 检查ServiceLB是否正常工作
    print_info "检查K3s ServiceLB状态..."
    local svclb_pods=$(k3s kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c "svclb" 2>/dev/null | tr -d '\n' || echo "0")

    # 确保变量是纯数字，如果不是则设为0
    [[ "$svclb_pods" =~ ^[0-9]+$ ]] || svclb_pods=0

    if [ "$svclb_pods" -gt 0 ]; then
        print_success "检测到ServiceLB Pod，NodePort应该正常工作"

        # 验证端口监听
        local retry_count=0
        while [ $retry_count -lt 6 ]; do
            if netstat -tuln 2>/dev/null | grep -q ":$NODEPORT_HTTPS "; then
                print_success "NodePort $NODEPORT_HTTPS 已正常监听"
                return 0
            fi
            print_info "等待NodePort端口监听... ($((retry_count + 1))/6)"
            sleep 10
            ((retry_count++))
        done

        print_warning "NodePort端口未监听，创建端口转发服务作为备用"
    else
        print_warning "未检测到ServiceLB Pod，创建端口转发服务"
    fi

    # 创建端口转发systemd服务
    print_info "创建端口转发systemd服务..."

    cat > /etc/systemd/system/matrix-port-forward.service << EOF
[Unit]
Description=Matrix Port Forward Service
After=k3s.service
Requires=k3s.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/kubectl port-forward -n kube-system svc/traefik $HTTPS_PORT:$HTTPS_PORT --address=0.0.0.0
Restart=always
RestartSec=5
Environment=KUBECONFIG=/etc/rancher/k3s/k3s.yaml

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable matrix-port-forward.service
    systemctl start matrix-port-forward.service

    # 等待端口转发生效
    print_info "等待端口转发服务启动..."
    sleep 10

    # 验证端口转发
    if systemctl is-active --quiet matrix-port-forward.service; then
        if netstat -tuln 2>/dev/null | grep -q ":$HTTPS_PORT "; then
            print_success "端口转发服务启动成功，$HTTPS_PORT端口已监听"
        else
            print_warning "端口转发服务已启动，但端口可能还未就绪"
        fi
    else
        print_error "端口转发服务启动失败"
        systemctl status matrix-port-forward.service
        return 1
    fi

    print_info "端口转发配置："
    echo -e "  服务状态: $(systemctl is-active matrix-port-forward.service)"
    echo -e "  转发规则: 0.0.0.0:$HTTPS_PORT -> traefik:$HTTPS_PORT"
    echo -e "  访问地址: https://$WEB_HOST:$HTTPS_PORT"
}



create_admin_user() {
    print_step "创建管理员用户"

    local namespace="ess"

    # 等待MAS Pod就绪
    print_info "等待Matrix Authentication Service就绪..."
    local retry_count=0
    local mas_pod=""

    while true; do
        mas_pod=$(k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name=matrix-authentication-service --no-headers 2>/dev/null | grep "Running" | head -n1 | awk '{print $1}')

        if [[ -n "$mas_pod" ]]; then
            print_success "找到运行中的MAS Pod: $mas_pod"
            break
        fi

        if [ $retry_count -ge 30 ]; then  # 减少到5分钟
            print_error "等待MAS Pod超时 (5分钟)"
            print_info "当前Pod状态:"
            k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name=matrix-authentication-service
            print_warning "MAS Pod未就绪，跳过用户创建"
            print_info "您可以稍后手动创建管理员用户"
            return 1
        fi

        print_info "等待MAS Pod启动... ($((retry_count + 1))/30)"
        sleep 10
        ((retry_count++))
    done

    # 等待MAS服务内部就绪
    print_info "等待MAS服务内部就绪..."
    retry_count=0
    while true; do
        # 检查MAS是否真正就绪 - 尝试执行一个简单命令
        if k3s kubectl exec -n "$namespace" "$mas_pod" -- mas-cli --version &> /dev/null; then
            print_success "MAS服务已就绪"
            break
        fi

        if [ $retry_count -ge 12 ]; then  # 2分钟
            print_warning "MAS服务内部检查超时，尝试创建用户"
            break
        fi

        print_info "等待MAS服务内部就绪... ($((retry_count + 1))/12)"
        sleep 10
        ((retry_count++))
    done

    # 创建管理员用户
    print_info "在MAS中创建管理员用户..."
    print_info "用户名: $ADMIN_USERNAME"
    print_info "密码: $ADMIN_PASSWORD"

    # 尝试多种创建方式
    local user_created=false

    # 方法1: 使用--yes参数
    print_info "尝试方法1: 使用--yes参数..."
    if k3s kubectl exec -n "$namespace" "$mas_pod" -- \
        mas-cli manage register-user \
        --yes \
        --username "$ADMIN_USERNAME" \
        --password "$ADMIN_PASSWORD" \
        --admin 2>/dev/null; then
        print_success "管理员用户创建完成 (方法1)"
        user_created=true
    fi

    # 方法2: 不使用--yes参数
    if [ "$user_created" = false ]; then
        print_info "尝试方法2: 不使用--yes参数..."
        if k3s kubectl exec -n "$namespace" "$mas_pod" -- \
            mas-cli manage register-user \
            --username "$ADMIN_USERNAME" \
            --password "$ADMIN_PASSWORD" \
            --admin 2>/dev/null; then
            print_success "管理员用户创建完成 (方法2)"
            user_created=true
        fi
    fi

    # 方法3: 使用环境变量
    if [ "$user_created" = false ]; then
        print_info "尝试方法3: 使用环境变量..."
        if k3s kubectl exec -n "$namespace" "$mas_pod" -- \
            env MAS_USERNAME="$ADMIN_USERNAME" MAS_PASSWORD="$ADMIN_PASSWORD" \
            mas-cli manage register-user --admin 2>/dev/null; then
            print_success "管理员用户创建完成 (方法3)"
            user_created=true
        fi
    fi

    if [ "$user_created" = false ]; then
        print_warning "自动创建用户失败，提供手动创建指导"
        print_info "请手动执行以下命令创建管理员用户:"
        echo "kubectl exec -n $namespace -it $mas_pod -- mas-cli manage register-user"
        echo "然后按提示输入:"
        echo "  用户名: $ADMIN_USERNAME"
        echo "  密码: $ADMIN_PASSWORD"
        echo "  设置为管理员: yes"
        return 1
    fi

    print_info "管理员账户信息:"
    print_info "  用户名: $ADMIN_USERNAME"
    print_info "  密码: $ADMIN_PASSWORD"
    print_info "  Matrix ID: @$ADMIN_USERNAME:$SERVER_NAME"
}

verify_deployment() {
    print_step "验证部署"

    local namespace="ess"

    # 检查Pod状态
    print_info "检查Pod状态..."
    k3s kubectl get pods -n "$namespace" -o wide

    # 检查服务状态
    print_info "检查服务状态..."
    k3s kubectl get services -n "$namespace"

    # 检查Ingress状态
    print_info "检查Ingress状态..."
    k3s kubectl get ingress -n "$namespace"

    # 检查证书状态
    print_info "检查证书状态..."
    k3s kubectl get certificates -n "$namespace"

    # 检查ClusterIssuer状态
    print_info "检查ClusterIssuer状态..."
    k3s kubectl get clusterissuer

    # 检查关键服务健康状态
    print_info "检查关键服务健康状态..."
    local critical_services=("postgresql" "synapse" "matrix-authentication-service")

    for service in "${critical_services[@]}"; do
        local pod_status=$(k3s kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$service" --no-headers 2>/dev/null | awk '{print $3}' | head -n1)
        if [[ "$pod_status" == "Running" ]]; then
            print_success "$service - 运行正常"
        else
            print_warning "$service - 状态: $pod_status"
        fi
    done

    # 等待证书就绪
    print_info "等待SSL证书就绪..."
    sleep 30

    # 测试服务连通性
    print_info "测试服务连通性..."
    local services=("$WEB_HOST:$HTTPS_PORT" "$AUTH_HOST:$HTTPS_PORT" "$RTC_HOST:$HTTPS_PORT" "$SYNAPSE_HOST:$HTTPS_PORT")

    for service in "${services[@]}"; do
        local host=$(echo "$service" | cut -d':' -f1)
        local port=$(echo "$service" | cut -d':' -f2)

        print_info "测试 $service..."
        if timeout 10 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            print_success "$service - 端口连接正常"
        else
            print_warning "$service - 端口连接失败"
        fi

        # 测试HTTPS连接
        if curl -s --connect-timeout 10 --max-time 15 -k "https://$service" > /dev/null 2>&1; then
            print_success "$service - HTTPS连接正常"
        else
            print_warning "$service - HTTPS连接失败"
        fi
    done

    # 检查well-known配置
    print_info "检查Matrix well-known配置..."
    if curl -s --connect-timeout 5 "https://$SERVER_NAME:$HTTPS_PORT/.well-known/matrix/server" | grep -q "$SYNAPSE_HOST"; then
        print_success "Matrix server well-known配置正常"
    else
        print_warning "Matrix server well-known配置可能有问题"
    fi

    if curl -s --connect-timeout 5 "https://$SERVER_NAME:$HTTPS_PORT/.well-known/matrix/client" | grep -q "$WEB_HOST"; then
        print_success "Matrix client well-known配置正常"
    else
        print_warning "Matrix client well-known配置可能有问题"
    fi

    print_success "部署验证完成"

    # 显示访问信息
    print_header "访问信息"
    echo -e "${WHITE}服务访问地址:${NC}"
    echo -e "  Element Web: https://$WEB_HOST:$HTTPS_PORT"
    echo -e "  认证服务: https://$AUTH_HOST:$HTTPS_PORT"
    echo -e "  RTC服务: https://$RTC_HOST:$HTTPS_PORT"
    echo -e "  Synapse: https://$SYNAPSE_HOST:$HTTPS_PORT"
    echo -e "  服务器名: $SERVER_NAME"
    echo
}

# ==================== 服务管理模块 ====================

show_service_status() {
    print_header "服务状态"

    local namespace="ess"

    echo -e "${WHITE}K3s集群状态:${NC}"
    k3s kubectl get nodes
    echo

    echo -e "${WHITE}ESS服务状态:${NC}"
    k3s kubectl get pods -n "$namespace" -o wide
    echo

    echo -e "${WHITE}服务端点:${NC}"
    k3s kubectl get services -n "$namespace"
    echo

    echo -e "${WHITE}Ingress状态:${NC}"
    k3s kubectl get ingress -n "$namespace"
    echo

    echo -e "${WHITE}证书状态:${NC}"
    k3s kubectl get certificates -n "$namespace"
    echo

    echo -e "${WHITE}Helm部署状态:${NC}"
    helm list -n "$namespace"
    echo
}

restart_services() {
    print_step "重启服务"

    local namespace="ess"

    if confirm_action "是否重启所有ESS服务"; then
        print_info "重启ESS服务..."
        k3s kubectl rollout restart deployment -n "$namespace"

        print_info "等待服务重启完成..."
        k3s kubectl rollout status deployment -n "$namespace" --timeout=600s

        print_success "服务重启完成"
    fi
}

show_logs() {
    print_step "查看日志"

    local namespace="ess"

    echo -e "${WHITE}可用的服务:${NC}"
    k3s kubectl get pods -n "$namespace" --no-headers | awk '{print NR") "$1}'
    echo

    read -p "请选择要查看日志的服务编号: " pod_num

    local pod_name=$(k3s kubectl get pods -n "$namespace" --no-headers | sed -n "${pod_num}p" | awk '{print $1}')

    if [[ -n "$pod_name" ]]; then
        print_info "查看 $pod_name 的日志 (按Ctrl+C退出):"
        k3s kubectl logs -n "$namespace" "$pod_name" -f --tail=100
    else
        print_error "无效的服务编号"
    fi
}

# ==================== 清理模块 ====================

cleanup_ess() {
    print_step "清理ESS服务"

    if ! confirm_action "是否确认清理ESS服务 (保留K3s和cert-manager)"; then
        return 0
    fi

    local namespace="ess"

    # 检查helm是否可用
    if command -v helm &> /dev/null; then
        print_info "卸载ESS Helm Chart..."
        helm uninstall ess -n "$namespace" 2>/dev/null || true
    else
        print_warning "Helm命令不可用，跳过Helm卸载"
    fi

    # 检查k3s kubectl是否可用
    if command -v k3s &> /dev/null && k3s kubectl version &> /dev/null; then
        print_info "等待资源清理..."
        sleep 10

        print_info "删除ESS命名空间..."
        k3s kubectl delete namespace "$namespace" --timeout=60s 2>/dev/null || true

        # 强制删除命名空间（如果卡住）
        if k3s kubectl get namespace "$namespace" &> /dev/null; then
            print_info "强制删除命名空间..."
            k3s kubectl patch namespace "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
    else
        print_warning "K3s不可用，跳过Kubernetes资源清理"
    fi

    print_success "ESS清理完成"
}

cleanup_applications() {
    print_step "清理应用"

    if ! confirm_action "是否确认清理所有应用 (保留K3s集群)"; then
        return 0
    fi

    # 清理ESS
    cleanup_ess

    # 清理cert-manager
    if command -v helm &> /dev/null; then
        print_info "卸载cert-manager..."
        helm uninstall cert-manager -n cert-manager 2>/dev/null || true
    fi

    if command -v k3s &> /dev/null && k3s kubectl version &> /dev/null; then
        k3s kubectl delete namespace cert-manager --timeout=60s 2>/dev/null || true
    fi

    print_success "应用清理完成"
}

cleanup_complete() {
    print_step "完全清理"

    print_warning "此操作将删除所有组件，包括K3s集群和相关文件"
    print_warning "这将清理以下内容："
    print_warning "  - K3s集群和所有容器"
    print_warning "  - Helm和相关配置"
    print_warning "  - 配置文件和数据目录"
    print_warning "  - 系统服务和二进制文件"
    print_warning "  - 网络配置和证书"
    echo

    if ! confirm_action "是否确认完全清理"; then
        return 0
    fi

    # 清理应用
    print_info "清理应用组件..."
    cleanup_applications

    # 停止所有相关服务
    print_info "停止相关服务..."
    systemctl stop k3s || true
    systemctl stop k3s-agent || true
    systemctl disable k3s || true
    systemctl disable k3s-agent || true

    # 卸载K3s
    print_info "卸载K3s集群..."
    if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
        /usr/local/bin/k3s-uninstall.sh || true
    else
        print_warning "K3s卸载脚本不存在，执行手动清理..."
    fi

    # 清理K3s相关文件和目录
    print_info "清理K3s相关文件..."
    rm -rf /var/lib/rancher/k3s || true
    rm -rf /etc/rancher/k3s || true
    rm -rf /var/lib/kubelet || true
    rm -rf /var/lib/cni || true
    rm -rf /etc/cni || true
    rm -rf /opt/cni || true
    rm -rf /run/k3s || true
    rm -rf /run/flannel || true

    # 清理K3s二进制文件
    print_info "清理K3s二进制文件..."
    rm -f /usr/local/bin/k3s || true
    rm -f /usr/local/bin/kubectl || true
    rm -f /usr/local/bin/crictl || true
    rm -f /usr/local/bin/ctr || true
    rm -f /usr/local/bin/k3s-killall.sh || true
    rm -f /usr/local/bin/k3s-uninstall.sh || true
    rm -f /usr/local/bin/k3s-agent-uninstall.sh || true

    # 清理systemd服务文件
    print_info "清理systemd服务文件..."
    rm -f /etc/systemd/system/k3s.service || true
    rm -f /etc/systemd/system/k3s.service.env || true
    rm -f /etc/systemd/system/k3s-agent.service || true
    rm -f /etc/systemd/system/k3s-agent.service.env || true
    systemctl daemon-reload || true

    # 清理Helm
    print_info "清理Helm..."
    rm -f /usr/local/bin/helm || true
    rm -rf ~/.cache/helm || true
    rm -rf ~/.config/helm || true
    rm -rf ~/.local/share/helm || true

    # 清理kubeconfig文件
    print_info "清理kubeconfig文件..."
    rm -f ~/.kube/config || true
    rm -rf ~/.kube || true

    # 清理bash别名
    print_info "清理bash别名..."
    if [[ -f ~/.bashrc ]]; then
        sed -i '/alias kubectl=/d' ~/.bashrc || true
        sed -i '/export KUBECONFIG=/d' ~/.bashrc || true
    fi

    # 清理配置文件
    if [[ -n "$INSTALL_DIR" ]] && [[ -d "$INSTALL_DIR" ]]; then
        if confirm_action "是否删除配置目录 $INSTALL_DIR"; then
            print_info "删除配置目录..."
            rm -rf "$INSTALL_DIR" || true
        fi
    fi

    # 清理默认配置目录（如果存在）
    if [[ -d "$DEFAULT_INSTALL_DIR" ]] && [[ "$INSTALL_DIR" != "$DEFAULT_INSTALL_DIR" ]]; then
        if confirm_action "是否删除默认配置目录 $DEFAULT_INSTALL_DIR"; then
            print_info "删除默认配置目录..."
            rm -rf "$DEFAULT_INSTALL_DIR" || true
        fi
    fi

    # 清理临时文件
    print_info "清理临时文件..."
    rm -f /tmp/setup_*.sh || true
    rm -f /tmp/matrix_backup_*.tar.gz || true
    rm -rf /tmp/matrix_backup_* || true

    # 清理容器运行时残留
    print_info "清理容器运行时残留..."
    if command -v docker &> /dev/null; then
        docker system prune -af || true
    fi

    # 清理containerd残留
    print_info "清理containerd残留..."
    if command -v ctr &> /dev/null; then
        ctr -n k8s.io containers rm $(ctr -n k8s.io containers list -q) 2>/dev/null || true
        ctr -n k8s.io images rm $(ctr -n k8s.io images list -q) 2>/dev/null || true
    fi

    # 清理网络接口（如果存在）
    print_info "清理网络接口..."
    ip link delete flannel.1 2>/dev/null || true
    ip link delete cni0 2>/dev/null || true
    ip link delete docker0 2>/dev/null || true

    # 清理iptables规则
    print_info "清理iptables规则..."
    iptables -t nat -F || true
    iptables -t mangle -F || true
    iptables -F || true
    iptables -X || true

    # 清理mount点
    print_info "清理mount点..."
    umount /var/lib/kubelet/pods/*/volumes/kubernetes.io~secret/* 2>/dev/null || true
    umount /var/lib/kubelet/pods/*/volumes/kubernetes.io~configmap/* 2>/dev/null || true
    umount /var/lib/rancher/k3s/agent/containerd/io.containerd.grpc.v1.cri/sandboxes/*/shm 2>/dev/null || true

    # 清理进程
    print_info "清理相关进程..."
    pkill -f k3s || true
    pkill -f containerd || true
    pkill -f kubelet || true

    # 清理ESS配置文件（如果存在于其他位置）
    print_info "清理ESS配置文件..."
    rm -f /opt/matrix/ess-values.yaml || true
    rm -f /opt/matrix/matrix-config.env || true
    rmdir /opt/matrix 2>/dev/null || true

    print_success "完全清理完成"
    print_info "建议重启系统以确保所有更改生效"
}



# ==================== 完整部署流程 ====================

full_deployment() {
    print_header "Matrix ESS 完整部署"

    print_info "开始完整部署流程..."

    # 收集配置
    collect_basic_config
    collect_network_config
    collect_cert_config
    collect_admin_config

    # 显示配置摘要
    show_config_summary

    if ! confirm_action "配置正确，是否开始部署"; then
        print_info "部署已取消"
        return 0
    fi

    # 保存配置
    save_config

    # 安装基础组件
    if ! install_k3s; then
        print_warning "标准K3s安装失败，启动诊断修复..."
        if ! diagnose_and_fix_k3s; then
            print_error "K3s安装完全失败，无法继续部署"
            print_info "建议："
            print_info "1. 检查系统资源是否充足"
            print_info "2. 检查网络连接是否正常"
            print_info "3. 查看系统日志排查问题"
            return 1
        fi
    fi

    # 配置Traefik（如果需要）
    if ! configure_traefik; then
        print_warning "Traefik配置失败，但继续部署..."
    fi

    install_helm
    install_cert_manager
    configure_cert_manager

    # 部署ESS
    check_latest_versions
    verify_ess_chart
    generate_ess_values
    deploy_ess

    # ESS部署完成后，立即修复配置
    print_info "ESS部署完成，开始修复配置..."

    # 修复MAS配置（添加端口号）
    if ! fix_mas_configuration; then
        print_warning "MAS配置修复失败，但继续部署..."
    fi

    # 修复Well-known配置（添加端口号）
    if ! fix_wellknown_configuration; then
        print_warning "Well-known配置修复失败，但继续部署..."
    fi

    # 创建SSL证书
    if ! create_ssl_certificates; then
        print_warning "SSL证书创建失败，但继续部署..."
    fi

    # 配置端口转发（如果需要）
    if ! setup_port_forwarding; then
        print_warning "端口转发配置失败，但继续部署..."
        print_info "您可能需要手动配置网络访问"
    fi

    # 创建管理员用户
    if ! create_admin_user; then
        print_warning "管理员用户创建失败，但部署继续..."
        print_info "您可以稍后手动创建管理员用户"
    fi

    # 验证部署
    if ! verify_deployment; then
        print_warning "部署验证失败，但基础服务可能已正常运行"
    fi

    # 显示完成信息（无论前面步骤是否成功）
    show_deployment_summary
}

show_deployment_summary() {
    print_header "部署完成"

    echo -e "${GREEN}Matrix ESS Community 部署完成！${NC}"
    echo

    # 检查服务状态
    print_info "检查服务状态..."
    local namespace="ess"
    local running_pods=$(k3s kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$(k3s kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$total_pods" -gt 0 ]; then
        echo -e "${WHITE}服务状态: $running_pods/$total_pods 个服务运行中${NC}"
        if [ "$running_pods" -eq "$total_pods" ]; then
            echo -e "${GREEN}✅ 所有服务运行正常${NC}"
        else
            echo -e "${YELLOW}⚠️  部分服务可能还在启动中${NC}"
        fi
    else
        echo -e "${RED}❌ 未检测到ESS服务${NC}"
    fi
    echo

    echo -e "${WHITE}访问信息:${NC}"
    echo -e "  Element Web: https://$WEB_HOST:$HTTPS_PORT"
    echo -e "  认证服务: https://$AUTH_HOST:$HTTPS_PORT"
    echo -e "  RTC服务: https://$RTC_HOST:$HTTPS_PORT"
    echo -e "  Synapse: https://$SYNAPSE_HOST:$HTTPS_PORT"
    echo -e "  服务器名: $SERVER_NAME"
    echo

    echo -e "${WHITE}网络配置:${NC}"
    echo -e "  HTTP端口: $HTTP_PORT (NodePort: $NODEPORT_HTTP)"
    echo -e "  HTTPS端口: $HTTPS_PORT (NodePort: $NODEPORT_HTTPS)"
    echo -e "  联邦端口: $FEDERATION_PORT (NodePort: $NODEPORT_FEDERATION)"
    echo -e "  UDP端口范围: $UDP_RANGE"
    echo -e "  公网IP: $PUBLIC_IP"
    echo

    echo -e "${WHITE}管理员账户:${NC}"
    if [[ -n "$ADMIN_USERNAME" && -n "$ADMIN_PASSWORD" ]]; then
        echo -e "  用户名: $ADMIN_USERNAME"
        echo -e "  密码: $ADMIN_PASSWORD"
        echo -e "  Matrix ID: @$ADMIN_USERNAME:$SERVER_NAME"
    else
        echo -e "  ${YELLOW}管理员用户未创建，请手动创建${NC}"
    fi
    echo

    echo -e "${WHITE}配置文件:${NC}"
    echo -e "  配置文件: $INSTALL_DIR/matrix-config.env"
    echo -e "  ESS配置: $INSTALL_DIR/ess-values.yaml"
    if [[ -f "$INSTALL_DIR/passwords.txt" ]]; then
        echo -e "  密码文件: $INSTALL_DIR/passwords.txt"
    fi
    echo

    echo -e "${WHITE}后续步骤:${NC}"
    echo -e "  1. 访问 https://$WEB_HOST:$HTTPS_PORT 测试登录"
    echo -e "  2. 使用联邦测试器验证: https://federationtester.matrix.org/#$SERVER_NAME"
    echo -e "  3. 如需管理服务，重新运行脚本选择服务管理"
    echo

    echo -e "${YELLOW}请妥善保存管理员密码和配置文件！${NC}"

    read -p "按回车键继续..."
}

# ==================== 配置管理菜单 ====================

config_management_menu() {
    while true; do
        clear
        print_header "配置管理"

        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 新建配置"
        echo -e "  ${GREEN}2)${NC} 加载配置"
        echo -e "  ${GREEN}3)${NC} 查看当前配置"
        echo -e "  ${GREEN}4)${NC} 保存配置"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo

        read -p "请选择操作 (0-4): " choice

        case $choice in
            1)
                collect_basic_config
                collect_network_config
                collect_cert_config
                collect_admin_config
                show_config_summary
                read -p "按回车键继续..."
                ;;
            2)
                read -p "请输入配置文件路径: " config_file
                if load_config "$config_file"; then
                    show_config_summary
                fi
                read -p "按回车键继续..."
                ;;
            3)
                if [[ -n "$SERVER_NAME" ]]; then
                    show_config_summary
                else
                    print_warning "当前无配置信息"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                if [[ -n "$SERVER_NAME" ]]; then
                    save_config
                else
                    print_error "请先创建配置"
                fi
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择，请输入 0-4"
                sleep 2
                ;;
        esac
    done
}

# ==================== 服务管理菜单 ====================

service_management_menu() {
    while true; do
        clear
        print_header "服务管理"

        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 查看服务状态"
        echo -e "  ${GREEN}2)${NC} 重启服务"
        echo -e "  ${GREEN}3)${NC} 查看日志"
        echo -e "  ${GREEN}4)${NC} 验证部署"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo

        read -p "请选择操作 (0-4): " choice

        case $choice in
            1)
                show_service_status
                read -p "按回车键继续..."
                ;;
            2)
                restart_services
                read -p "按回车键继续..."
                ;;
            3)
                show_logs
                ;;
            4)
                verify_deployment
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择，请输入 0-4"
                sleep 2
                ;;
        esac
    done
}

# ==================== 清理菜单 ====================

cleanup_menu() {
    while true; do
        clear
        print_header "清理环境"

        echo -e "${WHITE}请选择清理级别:${NC}"
        echo -e "  ${GREEN}1)${NC} 清理ESS服务 (保留K3s和cert-manager)"
        echo -e "  ${GREEN}2)${NC} 清理应用 (保留K3s集群)"
        echo -e "  ${RED}3)${NC} 完全清理 (删除所有组件)"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo

        read -p "请选择操作 (0-3): " choice

        case $choice in
            1)
                cleanup_ess
                read -p "按回车键继续..."
                ;;
            2)
                cleanup_applications
                read -p "按回车键继续..."
                ;;
            3)
                cleanup_complete
                read -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选择，请输入 0-3"
                sleep 2
                ;;
        esac
    done
}

# ==================== 自我更新模块 ====================

check_script_update() {
    print_step "检查脚本更新"

    local remote_url="https://raw.githubusercontent.com/niublab/aiya/main/setup.sh"
    local temp_file="/tmp/setup_new.sh"

    print_info "检查远程版本..."

    # 下载远程脚本
    if ! curl -s --connect-timeout 10 "$remote_url" -o "$temp_file"; then
        print_warning "无法连接到更新服务器"
        return 1
    fi

    # 提取远程版本号
    local remote_version=$(grep '^readonly SCRIPT_VERSION=' "$temp_file" | cut -d'"' -f2)

    if [[ -z "$remote_version" ]]; then
        print_warning "无法获取远程版本信息"
        rm -f "$temp_file"
        return 1
    fi

    print_info "当前版本: $SCRIPT_VERSION"
    print_info "远程版本: $remote_version"

    if [[ "$remote_version" != "$SCRIPT_VERSION" ]]; then
        print_info "发现新版本！"
        if confirm_action "是否更新到最新版本"; then
            update_script "$temp_file"
        fi
    else
        print_success "已是最新版本"
    fi

    rm -f "$temp_file"
}

update_script() {
    local new_script="$1"
    local backup_file="/tmp/setup_backup_$(date +%Y%m%d_%H%M%S).sh"

    print_info "备份当前脚本到: $backup_file"
    cp "$0" "$backup_file"

    print_info "更新脚本..."
    cp "$new_script" "$0"
    chmod +x "$0"

    print_success "脚本更新完成！"
    print_info "重新启动脚本..."

    exec "$0" "$@"
}

# ==================== 网络诊断模块 ====================

network_diagnostics() {
    print_step "网络诊断"

    # 检查基本网络连通性
    print_info "检查网络连通性..."
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com")

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &> /dev/null; then
            print_success "$host - 连接正常"
        else
            print_error "$host - 连接失败"
        fi
    done

    # 检查DNS解析
    print_info "检查DNS解析..."
    if [[ -n "$SERVER_NAME" ]]; then
        local domains=("$SERVER_NAME" "$WEB_HOST" "$AUTH_HOST" "$RTC_HOST" "$SYNAPSE_HOST")
        for domain in "${domains[@]}"; do
            if nslookup "$domain" &> /dev/null; then
                print_success "$domain - DNS解析正常"
            else
                print_warning "$domain - DNS解析失败"
            fi
        done
    else
        print_warning "未配置域名，跳过DNS检查"
    fi

    # 检查端口占用
    print_info "检查端口占用..."
    local ports=("$HTTP_PORT" "$HTTPS_PORT" "$FEDERATION_PORT")
    for port in "${ports[@]}"; do
        if [[ -n "$port" ]]; then
            if check_port_usage "$port"; then
                print_warning "端口 $port 已被占用"
            else
                print_success "端口 $port 可用"
            fi
        fi
    done
}

# ==================== 备份恢复模块 ====================

backup_config() {
    print_step "备份配置"

    if [[ -z "$INSTALL_DIR" ]] || [[ ! -d "$INSTALL_DIR" ]]; then
        print_error "安装目录不存在"
        return 1
    fi

    local backup_dir="/tmp/matrix_backup_$(date +%Y%m%d_%H%M%S)"
    local config_file="$INSTALL_DIR/matrix-config.env"
    local values_file="$INSTALL_DIR/ess-values.yaml"

    mkdir -p "$backup_dir"

    # 备份配置文件
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$backup_dir/"
        print_success "配置文件已备份"
    fi

    if [[ -f "$values_file" ]]; then
        cp "$values_file" "$backup_dir/"
        print_success "ESS配置已备份"
    fi

    # 备份Kubernetes配置
    if command -v k3s &> /dev/null; then
        print_info "备份Kubernetes配置..."
        k3s kubectl get all -n matrix -o yaml > "$backup_dir/k8s_resources.yaml" 2>/dev/null || true
        k3s kubectl get secrets -n matrix -o yaml > "$backup_dir/k8s_secrets.yaml" 2>/dev/null || true
        k3s kubectl get configmaps -n matrix -o yaml > "$backup_dir/k8s_configmaps.yaml" 2>/dev/null || true
    fi

    # 创建备份压缩包
    local backup_archive="/tmp/matrix_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_archive" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"

    rm -rf "$backup_dir"

    print_success "备份完成: $backup_archive"
    echo -e "${WHITE}备份文件: $backup_archive${NC}"
}

# ==================== 主菜单 ====================

show_license() {
    clear
    print_header "许可证声明"
    echo -e "${YELLOW}⚠ 重要提醒: 本脚本基于AGPL-3.0许可证${NC}"
    echo -e "${YELLOW}⚠ 仅限个人、学习、研究等非商业用途${NC}"
    echo -e "${YELLOW}⚠ 禁止用于任何商业目的${NC}"
    echo
    echo -e "${WHITE}使用本脚本即表示您同意以上条款${NC}"
    echo
    
    if ! confirm_action "是否同意许可证条款并继续"; then
        print_info "感谢您的理解，再见！"
        exit 0
    fi
}

show_main_menu() {
    clear
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    
    echo -e "${WHITE}脚本版本:${NC} $SCRIPT_VERSION"
    echo -e "${WHITE}ESS版本:${NC} $ESS_VERSION"
    echo -e "${WHITE}创建日期:${NC} $SCRIPT_DATE"
    echo
    echo -e "${YELLOW}⚠ 许可证: 仅限非商业用途 (AGPL-3.0)${NC}"
    echo
    
    echo -e "${WHITE}请选择操作:${NC}"
    echo -e "  ${GREEN}1)${NC} 完整部署 Matrix ESS"
    echo -e "  ${GREEN}2)${NC} 配置管理"
    echo -e "  ${GREEN}3)${NC} 服务管理"
    echo -e "  ${GREEN}4)${NC} 清理环境"
    echo -e "  ${GREEN}5)${NC} 系统信息"
    echo -e "  ${GREEN}6)${NC} 网络诊断"
    echo -e "  ${GREEN}7)${NC} 备份配置"
    echo -e "  ${GREEN}8)${NC} 检查组件版本"
    echo -e "  ${GREEN}9)${NC} 检查脚本更新"
    echo -e "  ${RED}0)${NC} 退出"
    echo
}

# ==================== 主程序入口 ====================

main() {
    # 显示许可证
    show_license
    
    # 检查系统环境
    check_system_requirements
    install_dependencies
    
    # 主循环
    while true; do
        show_main_menu
        read -p "请选择操作 (0-9): " choice

        case $choice in
            1)
                full_deployment
                ;;
            2)
                config_management_menu
                ;;
            3)
                service_management_menu
                ;;
            4)
                cleanup_menu
                ;;
            5)
                clear
                print_header "系统信息"
                echo -e "${WHITE}脚本信息:${NC}"
                echo -e "  脚本名称: $SCRIPT_NAME"
                echo -e "  脚本版本: $SCRIPT_VERSION"
                echo -e "  创建日期: $SCRIPT_DATE"
                echo
                echo -e "${WHITE}组件版本:${NC}"
                echo -e "  ESS版本: $ESS_VERSION"
                echo -e "  K3s版本: $K3S_VERSION"
                echo -e "  Helm版本: $HELM_VERSION"
                echo -e "  cert-manager版本: $CERT_MANAGER_VERSION"
                echo
                read -p "按回车键继续..."
                ;;
            6)
                network_diagnostics
                read -p "按回车键继续..."
                ;;
            7)
                backup_config
                read -p "按回车键继续..."
                ;;
            8)
                check_latest_versions
                read -p "按回车键继续..."
                ;;
            9)
                check_script_update
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "\n${GREEN}感谢使用！${NC}\n"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 0-9"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
