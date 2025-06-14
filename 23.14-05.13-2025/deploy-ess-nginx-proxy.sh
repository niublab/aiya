#!/bin/bash

# ESS-Helm外部Nginx反代自动部署脚本
# 支持非标准端口、自定义域名、自定义部署路径

set -euo pipefail

# 加载配置文件 (如果存在)
if [[ -f "ess-config-template.env" ]]; then
    echo "[INFO] 发现配置文件，加载配置..."
    # 只加载未设置的环境变量
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue

        # 移除引号
        value=$(echo "$value" | sed 's/^"//;s/"$//')

        # 只设置未定义的变量
        if [[ -z "${!key:-}" ]]; then
            export "$key"="$value"
        fi
    done < <(grep -E '^[A-Z_]+=.*' ess-config-template.env || true)
fi

# 配置变量 (优先使用环境变量)
DOMAIN="${DOMAIN:-your-domain.com}"
HTTP_PORT="${HTTP_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
FEDERATION_PORT="${FEDERATION_PORT:-8448}"
WEBRTC_TCP_PORT="${WEBRTC_TCP_PORT:-30881}"
WEBRTC_UDP_PORT="${WEBRTC_UDP_PORT:-30882}"
WEBRTC_UDP_RANGE_START="${WEBRTC_UDP_RANGE_START:-30152}"
WEBRTC_UDP_RANGE_END="${WEBRTC_UDP_RANGE_END:-30352}"

# 路径配置 (避免硬编码)
INSTALL_DIR="${INSTALL_DIR:-/opt/matrix-ess}"
NAMESPACE="${NAMESPACE:-ess}"
DATA_DIR="${DATA_DIR:-/var/lib/matrix-ess}"
LOG_DIR="${LOG_DIR:-/var/log/matrix-ess}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/matrix-ess}"
NGINX_CONFIG_DIR="${NGINX_CONFIG_DIR:-/etc/nginx}"
NGINX_SITES_AVAILABLE="${NGINX_SITES_AVAILABLE:-$NGINX_CONFIG_DIR/sites-available}"
NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-$NGINX_CONFIG_DIR/sites-enabled}"
LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-/etc/letsencrypt}"
K3S_CONFIG_DIR="${K3S_CONFIG_DIR:-/etc/rancher/k3s}"
K3S_DATA_DIR="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"

# 子域名配置 (自定义环境)
WEB_SUBDOMAIN="${WEB_SUBDOMAIN:-app}"
AUTH_SUBDOMAIN="${AUTH_SUBDOMAIN:-mas}"
RTC_SUBDOMAIN="${RTC_SUBDOMAIN:-rtc}"
MATRIX_SUBDOMAIN="${MATRIX_SUBDOMAIN:-matrix}"

# 验证关键配置
validate_config() {
    echo "[INFO] 验证配置参数..."

    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        echo "[ERROR] 域名配置无效: $DOMAIN"
        echo "[ERROR] 请设置正确的域名，例如:"
        echo "  export DOMAIN=matrix.example.com"
        echo "  或在ess-config-template.env中修改DOMAIN配置"
        exit 1
    fi

    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        echo "[ERROR] 域名格式无效: $DOMAIN"
        echo "[ERROR] 域名应该是有效的格式，如: matrix.example.com"
        exit 1
    fi

    echo "[SUCCESS] 配置验证通过"
    echo "  域名: $DOMAIN"
    echo "  HTTP端口: $HTTP_PORT"
    echo "  HTTPS端口: $HTTPS_PORT"
    echo "  联邦端口: $FEDERATION_PORT"
}

# 注意: 配置验证将在main函数中调用，确保所有环境变量都已正确设置

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查系统要求
check_requirements() {
    print_info "检查系统要求..."
    
    # 检查操作系统
    if ! command -v apt &> /dev/null; then
        print_error "此脚本仅支持Debian/Ubuntu系统"
        exit 1
    fi
    
    # 检查内存
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 2 ]]; then
        print_warning "系统内存少于2GB，可能影响性能"
    fi
    
    print_success "系统要求检查完成"
}

# 安装依赖
install_dependencies() {
    print_info "安装系统依赖..."
    
    apt update
    apt install -y curl wget nginx certbot python3-certbot-nginx ufw
    
    print_success "依赖安装完成"
}

# 配置防火墙
configure_firewall() {
    local enable_firewall="${ENABLE_FIREWALL:-false}"

    print_info "防火墙配置..."

    if [[ "$enable_firewall" == "true" ]]; then
        print_info "启用UFW防火墙并配置规则..."

        # 设置默认策略
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing

        # 允许SSH (关键 - 防止锁定)
        ufw allow ssh
        ufw allow 22/tcp

        # 允许HTTP/HTTPS端口
        ufw allow $HTTP_PORT/tcp
        ufw allow $HTTPS_PORT/tcp
        ufw allow $FEDERATION_PORT/tcp

        # 允许WebRTC端口
        ufw allow $WEBRTC_TCP_PORT/tcp
        ufw allow $WEBRTC_UDP_PORT/udp
        ufw allow $WEBRTC_UDP_RANGE_START:$WEBRTC_UDP_RANGE_END/udp

        # 启用防火墙
        ufw --force enable

        print_success "UFW防火墙已启用并配置完成"
        ufw status numbered

    else
        print_info "防火墙配置已跳过 (ENABLE_FIREWALL=false)"
        print_warning "注意: 系统防火墙未启用，请确保网络安全"
        print_info "如需启用防火墙，请设置 ENABLE_FIREWALL=true"

        # 检查UFW状态
        if ufw status | grep -q "Status: active"; then
            print_info "检测到UFW已启用，当前状态:"
            ufw status numbered
        else
            print_info "UFW当前未启用"
        fi
    fi
}

# 安装K3s
install_k3s() {
    print_info "安装K3s..."

    # 检查是否已安装K3s
    if systemctl is-active --quiet k3s; then
        print_info "K3s已经运行，跳过安装"
        return 0
    fi

    # 创建K3s配置目录
    mkdir -p "$K3S_DATA_DIR/server/manifests"

    # 创建Traefik配置
    cat > "$K3S_DATA_DIR/server/manifests/traefik-config.yaml" << EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        exposedPort: $HTTP_PORT
      websecure:
        exposedPort: $HTTPS_PORT
    service:
      spec:
        externalIPs:
        - "$(hostname -I | awk '{print $1}')"
EOF

    # 安装K3s
    print_info "下载并安装K3s..."
    curl -sfL https://get.k3s.io | sh -

    # 等待K3s服务启动
    print_info "等待K3s服务启动..."
    local retry_count=0
    while ! systemctl is-active --quiet k3s && [[ $retry_count -lt 30 ]]; do
        sleep 2
        ((retry_count++))
        print_info "等待K3s启动... ($retry_count/30)"
    done

    if ! systemctl is-active --quiet k3s; then
        print_error "K3s启动失败"
        systemctl status k3s --no-pager
        exit 1
    fi

    # 配置kubectl
    print_info "配置kubectl..."
    mkdir -p ~/.kube

    # 等待kubeconfig文件生成
    local config_retry=0
    local kubeconfig_file="$K3S_CONFIG_DIR/k3s.yaml"
    while [[ ! -f "$kubeconfig_file" ]] && [[ $config_retry -lt 20 ]]; do
        sleep 3
        ((config_retry++))
        print_info "等待kubeconfig生成... ($config_retry/20)"
    done

    if [[ ! -f "$kubeconfig_file" ]]; then
        print_error "kubeconfig文件未生成: $kubeconfig_file"
        exit 1
    fi

    # 复制配置到用户目录
    cp "$kubeconfig_file" ~/.kube/config
    chmod 600 ~/.kube/config

    # 设置KUBECONFIG环境变量 (优先使用系统配置)
    export KUBECONFIG="$kubeconfig_file"

    # 验证kubectl连接
    print_info "验证kubectl连接..."
    local kubectl_retry=0
    while ! kubectl get nodes &>/dev/null && [[ $kubectl_retry -lt 10 ]]; do
        sleep 3
        ((kubectl_retry++))
        print_info "等待kubectl连接... ($kubectl_retry/10)"
    done

    if ! kubectl get nodes &>/dev/null; then
        print_error "kubectl连接失败"
        print_info "检查K3s状态:"
        systemctl status k3s --no-pager
        print_info "检查kubeconfig:"
        ls -la "$K3S_CONFIG_DIR/k3s.yaml"
        exit 1
    fi

    # 等待所有系统Pod就绪
    print_info "等待系统Pod就绪..."

    # 先检查是否有Pod存在
    local retry_count=0
    while [[ $retry_count -lt 30 ]]; do
        if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q .; then
            print_info "发现系统Pod，等待就绪..."
            break
        fi
        sleep 5
        ((retry_count++))
        print_info "等待系统Pod创建... ($retry_count/30)"
    done

    # 等待Pod就绪，但允许失败
    if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q .; then
        print_info "等待系统Pod就绪 (最多5分钟)..."
        if kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s; then
            print_success "所有系统Pod已就绪"
        else
            print_warning "部分系统Pod可能未就绪，检查状态..."
            kubectl get pods -n kube-system

            # 检查是否有足够的Pod在运行
            local running_pods=$(kubectl get pods -n kube-system --no-headers | grep "Running" | wc -l)
            local total_pods=$(kubectl get pods -n kube-system --no-headers | wc -l)

            print_info "Pod状态: $running_pods/$total_pods 运行中"

            if [[ $running_pods -ge 3 ]]; then
                print_warning "有足够的系统Pod运行，继续部署"
            else
                print_error "系统Pod数量不足，可能影响部署"
                print_info "检查K3s日志: journalctl -u k3s -n 50"

                # 显示详细的Pod状态
                kubectl describe pods -n kube-system | grep -E "(Name:|Status:|Reason:|Message:)" || true
            fi
        fi
    else
        print_warning "未发现系统Pod，跳过等待"
    fi

    print_success "K3s安装完成"

    # 显示详细状态信息
    print_info "K3s集群状态:"
    kubectl get nodes -o wide

    print_info "系统Pod状态:"
    kubectl get pods -n kube-system

    # 检查关键系统组件
    local critical_pods=("coredns" "local-path-provisioner" "metrics-server" "traefik")
    for pod in "${critical_pods[@]}"; do
        if kubectl get pods -n kube-system | grep -q "$pod.*Running"; then
            print_success "$pod 运行正常"
        else
            print_warning "$pod 可能未就绪"
        fi
    done

    # 检查容器运行时状态
    check_container_runtime_status
}

# 检查容器运行时状态
check_container_runtime_status() {
    print_info "检查容器运行时状态..."

    # 检查containerd状态
    if systemctl is-active --quiet containerd 2>/dev/null; then
        print_success "containerd服务运行正常"
    else
        print_warning "containerd服务可能有问题"
    fi

    # 检查K3s容器
    if command -v crictl >/dev/null 2>&1; then
        local running_containers=$(crictl ps -q 2>/dev/null | wc -l)
        print_info "运行中的容器数量: $running_containers"

        if [[ $running_containers -gt 0 ]]; then
            print_success "容器运行时正常"
        else
            print_warning "没有运行中的容器"
        fi

        # 检查容器状态
        print_info "容器状态概览:"
        crictl ps 2>/dev/null | head -10 || print_warning "无法获取容器状态"
    else
        print_warning "crictl命令不可用"
    fi

    # 检查K3s日志中的错误
    print_info "检查K3s服务日志中的错误..."
    local error_count=$(journalctl -u k3s --since "5 minutes ago" | grep -i "error\|failed\|fatal" | wc -l)
    if [[ $error_count -gt 0 ]]; then
        print_warning "发现 $error_count 个错误日志条目"
        print_info "最近的错误日志:"
        journalctl -u k3s --since "5 minutes ago" | grep -i "error\|failed\|fatal" | tail -5
    else
        print_success "K3s日志中无严重错误"
    fi
}

# 修复K3s连接问题
fix_k3s_connection() {
    print_warning "尝试修复K3s连接问题..."

    # 重启K3s服务
    print_info "重启K3s服务..."
    systemctl restart k3s

    # 等待服务启动
    sleep 30

    # 重新设置kubeconfig
    export KUBECONFIG="$K3S_CONFIG_DIR/k3s.yaml"

    # 测试连接
    local fix_retry=0
    while ! kubectl get nodes &>/dev/null && [[ $fix_retry -lt 10 ]]; do
        sleep 5
        ((fix_retry++))
        print_info "等待K3s恢复... ($fix_retry/10)"
    done

    if kubectl get nodes &>/dev/null; then
        print_success "K3s连接已修复"
        return 0
    else
        print_error "K3s连接修复失败"
        return 1
    fi
}

# 安装Helm
install_helm() {
    print_info "检查Helm安装状态..."

    # 检查Helm是否已安装
    if command -v helm >/dev/null 2>&1; then
        local helm_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 | cut -d'v' -f2)
        print_success "Helm已安装，版本: $helm_version"

        # 检查版本是否满足要求 (至少3.0)
        if [[ $(echo "$helm_version" | cut -d'.' -f1) -ge 3 ]]; then
            print_success "Helm版本满足要求"
            return 0
        else
            print_warning "Helm版本过低 ($helm_version)，需要升级"
        fi
    else
        print_info "Helm未安装，开始安装..."
    fi

    # 下载并安装Helm
    print_info "从官方脚本安装Helm..."
    if curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; then
        print_success "Helm安装脚本执行完成"
    else
        print_error "Helm安装脚本执行失败"
        print_info "尝试手动安装方法..."

        # 备用安装方法
        local helm_version="v3.13.3"
        local arch=$(uname -m)
        case $arch in
            x86_64) arch="amd64" ;;
            aarch64) arch="arm64" ;;
            armv7l) arch="arm" ;;
            *) print_error "不支持的架构: $arch"; exit 1 ;;
        esac

        local helm_url="https://get.helm.sh/helm-${helm_version}-linux-${arch}.tar.gz"
        print_info "下载Helm: $helm_url"

        cd /tmp
        if curl -fsSL "$helm_url" -o helm.tar.gz; then
            tar -zxf helm.tar.gz
            mv linux-${arch}/helm /usr/local/bin/helm
            chmod +x /usr/local/bin/helm
            rm -rf helm.tar.gz linux-${arch}
            print_success "Helm手动安装完成"
        else
            print_error "Helm下载失败"
            exit 1
        fi
    fi

    # 验证安装
    if command -v helm >/dev/null 2>&1; then
        local installed_version=$(helm version --short 2>/dev/null | cut -d'+' -f1)
        print_success "Helm安装成功，版本: $installed_version"

        # 添加Helm到PATH (如果需要)
        if ! echo "$PATH" | grep -q "/usr/local/bin"; then
            export PATH="/usr/local/bin:$PATH"
            print_info "已添加/usr/local/bin到PATH"
        fi

        # 初始化Helm仓库
        print_info "初始化Helm仓库..."
        helm repo add stable https://charts.helm.sh/stable 2>/dev/null || true
        helm repo update 2>/dev/null || true

        print_success "Helm配置完成"
    else
        print_error "Helm安装验证失败"
        print_info "请检查以下问题:"
        print_info "1. 网络连接是否正常"
        print_info "2. /usr/local/bin是否在PATH中"
        print_info "3. 是否有足够的磁盘空间"
        exit 1
    fi
}

# 检查证书是否存在
check_existing_certificate() {
    local domain="$1"

    # 检查证书文件是否存在
    if [[ -f "$LETSENCRYPT_DIR/live/$domain/fullchain.pem" ]]; then
        print_info "发现现有证书: $domain"

        # 检查证书有效期
        local expiry_date=$(openssl x509 -in "$LETSENCRYPT_DIR/live/$domain/fullchain.pem" -noout -enddate | cut -d= -f2)
        local expiry_timestamp=$(date -d "$expiry_date" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))

        print_info "证书有效期还有 $days_until_expiry 天"

        # 检查证书是否包含所有需要的域名
        local cert_domains=$(openssl x509 -in "$LETSENCRYPT_DIR/live/$domain/fullchain.pem" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep DNS | cut -d: -f2 | tr -d ' ')
        local required_domains=("$DOMAIN" "$WEB_SUBDOMAIN.$DOMAIN" "$AUTH_SUBDOMAIN.$DOMAIN" "$RTC_SUBDOMAIN.$DOMAIN" "$MATRIX_SUBDOMAIN.$DOMAIN")
        local missing_domains=()

        for req_domain in "${required_domains[@]}"; do
            if ! echo "$cert_domains" | grep -q "^$req_domain$"; then
                missing_domains+=("$req_domain")
            fi
        done

        if [[ ${#missing_domains[@]} -gt 0 ]]; then
            print_warning "证书缺少域名: ${missing_domains[*]}"
            return 1
        fi

        # 如果证书30天内过期，需要续期
        if [[ $days_until_expiry -lt 30 ]]; then
            print_warning "证书将在30天内过期，需要续期"
            return 1
        fi

        print_success "现有证书有效，跳过申请"
        return 0
    else
        print_info "未找到现有证书: $domain"
        return 1
    fi
}

# 续期证书
renew_certificate() {
    local domain="$1"

    print_info "续期证书: $domain"

    if certbot renew --cert-name "$domain" --force-renewal; then
        print_success "证书续期成功"
        return 0
    else
        print_error "证书续期失败"
        return 1
    fi
}

# 智能证书管理 - 检测并决定操作
smart_certificate_management() {
    local domain="$1"
    local cert_type="${CERT_TYPE:-letsencrypt}"
    local cert_email="${CERT_EMAIL:-admin@$DOMAIN}"
    local test_mode="${TEST_MODE:-false}"

    print_info "智能证书管理: $domain"

    # 如果启用测试模式，自动使用staging证书
    if [[ "$test_mode" == "true" ]]; then
        cert_type="letsencrypt-staging"
        print_warning "测试模式已启用，将使用Let's Encrypt Staging证书"
    fi

    # 检查证书状态
    local cert_status=$(check_certificate_status "$domain")

    case "$cert_status" in
        "skip")
            print_success "证书有效且完整，跳过操作"
            return 0
            ;;
        "renew")
            print_info "证书需要续期"
            if renew_certificate "$domain"; then
                print_success "证书续期成功"
                return 0
            else
                print_warning "证书续期失败，尝试重新申请"
                # 续期失败，删除旧证书重新申请
                rm -rf "$LETSENCRYPT_DIR/live/$domain" || true
                rm -rf "$LETSENCRYPT_DIR/archive/$domain" || true
                rm -rf "$LETSENCRYPT_DIR/renewal/$domain.conf" || true
            fi
            ;;
        "new")
            print_info "需要申请新证书"
            ;;
        *)
            print_warning "证书状态未知，尝试申请新证书"
            ;;
    esac

    # 申请新证书
    case "$cert_type" in
        "letsencrypt")
            generate_letsencrypt_cert "$cert_email" ""
            ;;
        "letsencrypt-staging")
            generate_letsencrypt_cert "$cert_email" "--staging"
            ;;
        "custom")
            use_custom_cert
            ;;
        *)
            print_error "不支持的证书类型: $cert_type"
            print_info "支持的类型: letsencrypt, letsencrypt-staging, custom"
            exit 1
            ;;
    esac
}

# 检查证书状态并决定操作
check_certificate_status() {
    local domain="$1"
    local cert_path="$LETSENCRYPT_DIR/live/$domain/fullchain.pem"
    local key_path="$LETSENCRYPT_DIR/live/$domain/privkey.pem"

    print_info "检查域名 $domain 的证书状态..."

    # 检查证书文件是否存在
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
        print_info "证书文件不存在，需要申请新证书"
        echo "new"
        return
    fi

    print_info "发现现有证书: $cert_path"

    # 检查证书文件完整性
    if ! openssl x509 -in "$cert_path" -noout -text >/dev/null 2>&1; then
        print_warning "证书文件损坏，需要重新申请"
        echo "new"
        return
    fi

    if ! openssl rsa -in "$key_path" -check -noout >/dev/null 2>&1; then
        print_warning "私钥文件损坏，需要重新申请"
        echo "new"
        return
    fi

    # 检查证书有效期
    local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    local current_epoch=$(date +%s)

    if [[ -z "$expiry_epoch" ]]; then
        print_warning "无法解析证书到期时间，需要重新申请"
        echo "new"
        return
    fi

    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

    print_info "证书到期时间: $expiry_date"
    print_info "剩余有效天数: $days_until_expiry 天"

    # 检查证书域名是否匹配
    local cert_domains=$(openssl x509 -in "$cert_path" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep "DNS:" | sed 's/.*DNS://' | tr -d ' ' | sort)
    local required_domains=$(echo -e "$DOMAIN\n$WEB_SUBDOMAIN.$DOMAIN\n$AUTH_SUBDOMAIN.$DOMAIN\n$RTC_SUBDOMAIN.$DOMAIN\n$MATRIX_SUBDOMAIN.$DOMAIN" | sort)

    if [[ "$cert_domains" != "$required_domains" ]]; then
        print_warning "证书域名不匹配当前配置，需要重新申请"
        print_info "证书包含域名:"
        echo "$cert_domains" | sed 's/^/  - /'
        print_info "需要的域名:"
        echo "$required_domains" | sed 's/^/  - /'
        echo "new"
        return
    fi

    # 根据剩余天数决定操作
    if [[ $days_until_expiry -gt 30 ]]; then
        print_success "证书仍然有效且域名匹配，跳过申请"
        echo "skip"
    elif [[ $days_until_expiry -gt 0 ]]; then
        print_warning "证书即将到期 ($days_until_expiry 天)，需要更新"
        echo "renew"
    else
        print_error "证书已过期，需要重新申请"
        echo "new"
    fi
}

# 生成SSL证书 (保持向后兼容)
generate_ssl_certificates() {
    print_info "处理SSL证书..."

    # 使用智能证书管理
    smart_certificate_management "$DOMAIN"

    print_success "SSL证书配置完成"
}

# 安装DNS验证插件
install_dns_plugins() {
    local dns_provider="${DNS_PROVIDER:-cloudflare}"

    print_info "安装DNS验证插件: $dns_provider"

    case "$dns_provider" in
        "cloudflare")
            if command -v apt &> /dev/null; then
                # 检查是否已安装
                if ! dpkg -l | grep -q python3-certbot-dns-cloudflare; then
                    print_info "更新包列表..."
                    apt update
                    print_info "安装Cloudflare DNS插件..."
                    apt install -y python3-certbot-dns-cloudflare
                else
                    print_info "Cloudflare DNS插件已安装"
                fi
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-cloudflare
            elif command -v dnf &> /dev/null; then
                dnf install -y python3-certbot-dns-cloudflare
            else
                print_error "不支持的包管理器"
                exit 1
            fi
            ;;
        "route53")
            if command -v apt &> /dev/null; then
                apt update
                apt install -y python3-certbot-dns-route53
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-route53
            elif command -v dnf &> /dev/null; then
                dnf install -y python3-certbot-dns-route53
            fi
            ;;
        "digitalocean")
            if command -v apt &> /dev/null; then
                apt update
                apt install -y python3-certbot-dns-digitalocean
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-digitalocean
            elif command -v dnf &> /dev/null; then
                dnf install -y python3-certbot-dns-digitalocean
            fi
            ;;
        *)
            print_warning "未知的DNS提供商: $dns_provider，跳过插件安装"
            ;;
    esac

    # 验证插件安装
    case "$dns_provider" in
        "cloudflare")
            if certbot plugins | grep -q dns-cloudflare; then
                print_success "Cloudflare DNS插件安装成功"
            else
                print_error "Cloudflare DNS插件安装失败"
                print_info "尝试手动安装: pip3 install certbot-dns-cloudflare"
                exit 1
            fi
            ;;
        "route53")
            if certbot plugins | grep -q dns-route53; then
                print_success "Route53 DNS插件安装成功"
            else
                print_error "Route53 DNS插件安装失败"
                exit 1
            fi
            ;;
        "digitalocean")
            if certbot plugins | grep -q dns-digitalocean; then
                print_success "DigitalOcean DNS插件安装成功"
            else
                print_error "DigitalOcean DNS插件安装失败"
                exit 1
            fi
            ;;
    esac
}

# 配置DNS验证凭据
setup_dns_credentials() {
    local dns_provider="${DNS_PROVIDER:-cloudflare}"
    local creds_dir="$LETSENCRYPT_DIR"

    print_info "配置DNS验证凭据..."

    mkdir -p "$creds_dir"

    case "$dns_provider" in
        "cloudflare")
            if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
                print_error "Cloudflare API Token未设置"
                print_info "请设置环境变量: CLOUDFLARE_API_TOKEN"
                print_info "获取Token: https://dash.cloudflare.com/profile/api-tokens"
                print_info "权限需要: Zone:Zone:Read, Zone:DNS:Edit"
                exit 1
            fi

            cat > "$creds_dir/cloudflare.ini" << EOF
# Cloudflare API Token
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
            chmod 600 "$creds_dir/cloudflare.ini"
            print_success "Cloudflare凭据配置完成"
            ;;
        "route53")
            if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
                print_error "AWS凭据未设置"
                print_info "请设置: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
                exit 1
            fi

            cat > "$creds_dir/route53.ini" << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
            chmod 600 "$creds_dir/route53.ini"
            print_success "Route53凭据配置完成"
            ;;
        "digitalocean")
            if [[ -z "${DO_API_TOKEN:-}" ]]; then
                print_error "DigitalOcean API Token未设置"
                print_info "请设置环境变量: DO_API_TOKEN"
                exit 1
            fi

            cat > "$creds_dir/digitalocean.ini" << EOF
dns_digitalocean_token = $DO_API_TOKEN
EOF
            chmod 600 "$creds_dir/digitalocean.ini"
            print_success "DigitalOcean凭据配置完成"
            ;;
        *)
            print_warning "未知的DNS提供商: $dns_provider"
            ;;
    esac
}

# 预检查DNS配置
precheck_dns_config() {
    local dns_provider="${DNS_PROVIDER:-cloudflare}"

    print_info "预检查DNS配置..."

    case "$dns_provider" in
        "cloudflare")
            if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
                print_error "Cloudflare API Token未设置"
                return 1
            fi

            print_info "测试Cloudflare API连接..."
            if curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" | grep -q '"success":true'; then
                print_success "Cloudflare API连接正常"
            else
                print_error "Cloudflare API连接失败"
                print_info "请检查API Token是否正确"
                return 1
            fi
            ;;
        "route53")
            if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
                print_error "AWS凭据未设置"
                return 1
            fi
            print_info "AWS Route53凭据已设置"
            ;;
        "digitalocean")
            if [[ -z "${DO_API_TOKEN:-}" ]]; then
                print_error "DigitalOcean API Token未设置"
                return 1
            fi
            print_info "DigitalOcean API Token已设置"
            ;;
    esac

    # 检查域名解析
    print_info "检查域名解析..."
    local subdomains=("" "$WEB_SUBDOMAIN." "$AUTH_SUBDOMAIN." "$RTC_SUBDOMAIN." "$MATRIX_SUBDOMAIN.")
    for subdomain in "${subdomains[@]}"; do
        local full_domain="${subdomain}${DOMAIN}"
        if dig +short "$full_domain" @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
            print_success "域名解析正常: $full_domain"
        else
            print_warning "域名解析可能有问题: $full_domain"
        fi
    done

    return 0
}

# 生成Let's Encrypt证书
generate_letsencrypt_cert() {
    local email="$1"
    local staging_flag="$2"
    local challenge="${CERT_CHALLENGE:-dns}"
    local dns_provider="${DNS_PROVIDER:-cloudflare}"

    if [[ -n "$staging_flag" ]]; then
        print_info "生成Let's Encrypt Staging证书..."
    else
        print_info "生成Let's Encrypt生产证书..."
    fi

    # 根据验证方式选择不同的处理
    if [[ "$challenge" == "dns" ]]; then
        # DNS验证
        print_info "使用DNS验证方式: $dns_provider"

        # 预检查DNS配置
        if ! precheck_dns_config; then
            print_error "DNS配置预检查失败"
            exit 1
        fi

        # 安装DNS插件
        install_dns_plugins

        # 配置DNS凭据
        setup_dns_credentials

        # 构建certbot命令数组
        local certbot_args=(
            "certbot" "certonly"
            "--agree-tos"
            "--no-eff-email"
            "--email" "$email"
            "-d" "$DOMAIN"
            "-d" "$WEB_SUBDOMAIN.$DOMAIN"
            "-d" "$AUTH_SUBDOMAIN.$DOMAIN"
            "-d" "$RTC_SUBDOMAIN.$DOMAIN"
            "-d" "$MATRIX_SUBDOMAIN.$DOMAIN"
        )

        # 添加DNS插件参数
        case "$dns_provider" in
            "cloudflare")
                certbot_args+=("--dns-cloudflare")
                certbot_args+=("--dns-cloudflare-credentials" "$LETSENCRYPT_DIR/cloudflare.ini")
                certbot_args+=("--dns-cloudflare-propagation-seconds" "60")
                ;;
            "route53")
                certbot_args+=("--dns-route53")
                certbot_args+=("--dns-route53-credentials" "$LETSENCRYPT_DIR/route53.ini")
                certbot_args+=("--dns-route53-propagation-seconds" "30")
                ;;
            "digitalocean")
                certbot_args+=("--dns-digitalocean")
                certbot_args+=("--dns-digitalocean-credentials" "$LETSENCRYPT_DIR/digitalocean.ini")
                certbot_args+=("--dns-digitalocean-propagation-seconds" "60")
                ;;
            *)
                print_error "不支持的DNS提供商: $dns_provider"
                exit 1
                ;;
        esac

        # 添加staging标志
        if [[ -n "$staging_flag" ]]; then
            certbot_args+=("$staging_flag")
        fi

        # 添加详细输出
        certbot_args+=("--verbose")

        # 如果是调试模式，先进行dry-run
        if [[ "${DEBUG:-false}" == "true" ]]; then
            print_info "调试模式: 先进行dry-run测试..."
            local test_args=("${certbot_args[@]}" "--dry-run")
            print_info "测试命令: ${test_args[*]}"

            if "${test_args[@]}"; then
                print_success "Dry-run测试成功，继续正式申请..."
            else
                print_error "Dry-run测试失败，请检查配置"
                exit 1
            fi
        fi

        print_info "执行DNS验证..."
        print_info "这可能需要几分钟时间等待DNS传播..."
        print_info "执行命令: ${certbot_args[*]}"

    else
        # HTTP验证 (原有方式)
        print_info "使用HTTP验证方式"
        print_warning "需要确保80端口可以从互联网访问"

        # 停止nginx以释放80端口
        systemctl stop nginx || true

        # 构建certbot命令数组
        local certbot_args=(
            "certbot" "certonly"
            "--standalone"
            "--agree-tos"
            "--no-eff-email"
            "--email" "$email"
            "-d" "$DOMAIN"
            "-d" "$WEB_SUBDOMAIN.$DOMAIN"
            "-d" "$AUTH_SUBDOMAIN.$DOMAIN"
            "-d" "$RTC_SUBDOMAIN.$DOMAIN"
            "-d" "$MATRIX_SUBDOMAIN.$DOMAIN"
        )

        # 添加staging标志
        if [[ -n "$staging_flag" ]]; then
            certbot_args+=("$staging_flag")
        fi

        # 添加详细输出
        certbot_args+=("--verbose")

        print_info "执行HTTP验证..."
        print_info "执行命令: ${certbot_args[*]}"
    fi

    # 执行证书生成
    if "${certbot_args[@]}"; then
        print_success "Let's Encrypt证书生成成功"
        if [[ -n "$staging_flag" ]]; then
            print_warning "注意: 这是测试证书，浏览器会显示不安全警告"
        fi

        # 显示证书信息
        print_info "证书信息:"
        openssl x509 -in "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" -text -noout | grep -E "(Subject:|DNS:|Not After)"

    else
        local exit_code=$?
        print_error "Let's Encrypt证书生成失败 (退出码: $exit_code)"

        # 显示详细的错误信息
        print_info "查看详细错误日志:"
        echo "----------------------------------------"
        if [[ -f "/var/log/letsencrypt/letsencrypt.log" ]]; then
            tail -20 /var/log/letsencrypt/letsencrypt.log
        fi
        echo "----------------------------------------"

        print_info "常见问题排查:"
        if [[ "$challenge" == "dns" ]]; then
            print_info "DNS验证问题排查:"
            print_info "1. 检查DNS API凭据:"
            case "$dns_provider" in
                "cloudflare")
                    print_info "   - API Token是否正确: ${CLOUDFLARE_API_TOKEN:0:10}..."
                    print_info "   - 测试API连接:"
                    print_info "     curl -X GET 'https://api.cloudflare.com/client/v4/zones' -H 'Authorization: Bearer $CLOUDFLARE_API_TOKEN'"
                    ;;
                "route53")
                    print_info "   - AWS凭据是否正确"
                    print_info "   - IAM权限是否足够"
                    ;;
                "digitalocean")
                    print_info "   - DO API Token是否正确"
                    ;;
            esac
            print_info "2. 检查域名解析:"
            print_info "   dig $DOMAIN @8.8.8.8"
            print_info "3. 检查DNS插件:"
            print_info "   certbot plugins"
            print_info "4. 手动测试DNS验证:"
            print_info "   certbot certonly --dns-$dns_provider --dns-$dns_provider-credentials $LETSENCRYPT_DIR/$dns_provider.ini --dry-run -d $DOMAIN"
        else
            print_info "HTTP验证问题排查:"
            print_info "1. 检查域名解析:"
            print_info "   dig $DOMAIN @8.8.8.8"
            print_info "2. 检查HTTP端口:"
            print_info "   netstat -tlnp | grep :$HTTP_PORT"
            print_info "3. 检查防火墙:"
            print_info "   ufw status"
            print_info "4. 测试HTTP访问:"
            print_info "   curl -I http://$DOMAIN:$HTTP_PORT/.well-known/acme-challenge/test"
        fi

        print_info "获取更多帮助:"
        print_info "- Let's Encrypt社区: https://community.letsencrypt.org"
        print_info "- 查看完整日志: cat /var/log/letsencrypt/letsencrypt.log"
        print_info "- 重新运行调试: certbot --help"

        exit 1
    fi
}



# 使用自定义证书
use_custom_cert() {
    print_info "使用自定义证书..."

    local custom_cert="${CUSTOM_CERT_PATH:-/etc/ssl/certs/$DOMAIN.crt}"
    local custom_key="${CUSTOM_KEY_PATH:-/etc/ssl/private/$DOMAIN.key}"
    local cert_dir="$LETSENCRYPT_DIR/live/$DOMAIN"

    # 检查证书文件是否存在
    if [[ ! -f "$custom_cert" ]]; then
        print_error "自定义证书文件不存在: $custom_cert"
        exit 1
    fi

    if [[ ! -f "$custom_key" ]]; then
        print_error "自定义私钥文件不存在: $custom_key"
        exit 1
    fi

    # 创建证书目录
    mkdir -p "$cert_dir"

    # 复制证书文件
    cp "$custom_cert" "$cert_dir/fullchain.pem"
    cp "$custom_key" "$cert_dir/privkey.pem"

    # 设置权限
    chmod 600 "$cert_dir/privkey.pem"
    chmod 644 "$cert_dir/fullchain.pem"

    print_success "自定义证书配置完成"
}

# 配置Nginx
configure_nginx() {
    print_info "配置Nginx反向代理..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 生成Nginx配置
    cat > "$NGINX_SITES_AVAILABLE/matrix-ess" << EOF
# HTTP重定向到HTTPS
server {
    listen $HTTP_PORT;
    server_name $DOMAIN $WEB_SUBDOMAIN.$DOMAIN $AUTH_SUBDOMAIN.$DOMAIN $RTC_SUBDOMAIN.$DOMAIN $MATRIX_SUBDOMAIN.$DOMAIN;
    return 301 https://\$host:$HTTPS_PORT\$request_uri;
}

# 主HTTPS服务
server {
    listen $HTTPS_PORT ssl http2;
    server_name $DOMAIN $WEB_SUBDOMAIN.$DOMAIN $AUTH_SUBDOMAIN.$DOMAIN $RTC_SUBDOMAIN.$DOMAIN $MATRIX_SUBDOMAIN.$DOMAIN;

    # SSL配置
    ssl_certificate $LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key $LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # 代理到K3s Traefik
    location / {
        proxy_pass http://127.0.0.1:$HTTP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        # WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # 文件上传大小
        client_max_body_size 50M;
    }
}

# Matrix联邦端口
server {
    listen $FEDERATION_PORT ssl http2;
    server_name $DOMAIN $MATRIX_SUBDOMAIN.$DOMAIN;

    ssl_certificate $LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key $LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$HTTP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # 启用站点
    ln -sf "$NGINX_SITES_AVAILABLE/matrix-ess" "$NGINX_SITES_ENABLED/"
    
    # 删除默认站点
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试配置
    nginx -t
    
    # 启动nginx
    systemctl enable nginx
    systemctl start nginx
    
    print_success "Nginx配置完成"
}

# 生成ESS配置
generate_ess_config() {
    print_info "生成ESS配置..."
    
    cat > "$INSTALL_DIR/ess-values.yaml" << EOF
# ESS外部Nginx反代配置
serverName: "$DOMAIN"

# 全局Ingress配置 - 禁用TLS (由外部Nginx处理)
ingress:
  tlsEnabled: false
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"

# Element Web配置
elementWeb:
  ingress:
    host: "$WEB_SUBDOMAIN.$DOMAIN"
    tlsEnabled: false

# Matrix Authentication Service配置
matrixAuthenticationService:
  ingress:
    host: "$AUTH_SUBDOMAIN.$DOMAIN"
    tlsEnabled: false

# Matrix RTC配置
matrixRTC:
  ingress:
    host: "$RTC_SUBDOMAIN.$DOMAIN"
    tlsEnabled: false
  sfu:
    exposedServices:
      rtcTcp:
        enabled: true
        portType: NodePort
        port: $WEBRTC_TCP_PORT
      rtcMuxedUdp:
        enabled: true
        portType: NodePort
        port: $WEBRTC_UDP_PORT

# Synapse配置
synapse:
  ingress:
    host: "$MATRIX_SUBDOMAIN.$DOMAIN"
    tlsEnabled: false

# Well-known配置
wellKnownDelegation:
  enabled: true
  ingress:
    host: "$DOMAIN"
    tlsEnabled: false
EOF
    
    print_success "ESS配置生成完成"
}

# 后处理ESS配置文件 (修复端口问题)
post_process_ess_config() {
    print_info "后处理ESS配置文件..."

    # 等待Pod完全启动
    local retry=0
    while [[ $retry -lt 20 ]]; do
        local running_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ $running_pods -ge 3 ]]; then
            print_success "ESS Pod已启动 ($running_pods 个Pod运行中)"
            break
        fi
        sleep 15
        ((retry++))
        print_info "等待ESS Pod启动... ($retry/20) - 当前运行: $running_pods 个Pod"
    done

    if [[ $retry -eq 20 ]]; then
        print_warning "等待Pod启动超时，继续执行配置修复"
        kubectl get pods -n "$NAMESPACE"
    fi

    # 修复MAS配置中的重定向URL
    fix_mas_redirect_urls

    # 修复Synapse配置中的well-known URL
    fix_synapse_wellknown_urls

    # 修复Element Web配置中的服务器URL
    fix_element_web_config

    # 修复Nginx well-known配置
    fix_nginx_wellknown_config

    # 修复其他可能的配置文件
    fix_additional_configs

    # 重启相关服务以应用配置更改
    restart_ess_services

    # 验证配置修复效果
    verify_config_fixes

    # 最终检查硬编码端口
    check_hardcoded_ports

    print_success "ESS配置文件后处理完成"
}

# 修复MAS重定向URL
fix_mas_redirect_urls() {
    print_info "修复MAS重定向URL..."

    # 获取MAS ConfigMap
    local mas_config_name=$(kubectl get configmap -n "$NAMESPACE" -o name | grep mas | head -1)
    if [[ -n "$mas_config_name" ]]; then
        # 备份原配置
        kubectl get "$mas_config_name" -n "$NAMESPACE" -o yaml > "$INSTALL_DIR/mas-config-backup.yaml"

        # 提取配置内容
        kubectl get "$mas_config_name" -n "$NAMESPACE" -o jsonpath='{.data.config\.yaml}' > "$INSTALL_DIR/mas-config.yaml"

        # 修复重定向URL中的端口
        sed -i "s|https://$AUTH_SUBDOMAIN\\.$DOMAIN/|https://$AUTH_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/|g" "$INSTALL_DIR/mas-config.yaml"
        sed -i "s|https://$WEB_SUBDOMAIN\\.$DOMAIN/|https://$WEB_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/|g" "$INSTALL_DIR/mas-config.yaml"
        sed -i "s|https://$DOMAIN/|https://$DOMAIN:$HTTPS_PORT/|g" "$INSTALL_DIR/mas-config.yaml"

        # 修复任何硬编码的标准端口
        sed -i "s|:443/|:$HTTPS_PORT/|g" "$INSTALL_DIR/mas-config.yaml"
        sed -i "s|:80/|:$HTTP_PORT/|g" "$INSTALL_DIR/mas-config.yaml"

        # 更新ConfigMap
        kubectl create configmap "${mas_config_name#configmap/}" \
            --from-file=config.yaml="$INSTALL_DIR/mas-config.yaml" \
            --dry-run=client -o yaml | kubectl apply -n "$NAMESPACE" -f -

        print_success "MAS重定向URL已修复"
    else
        print_warning "未找到MAS ConfigMap"
    fi
}

# 修复Synapse well-known URL
fix_synapse_wellknown_urls() {
    print_info "修复Synapse well-known URL..."

    # 获取Synapse ConfigMap
    local synapse_config_name=$(kubectl get configmap -n "$NAMESPACE" -o name | grep synapse | head -1)
    if [[ -n "$synapse_config_name" ]]; then
        # 备份原配置
        kubectl get "$synapse_config_name" -n "$NAMESPACE" -o yaml > "$INSTALL_DIR/synapse-config-backup.yaml"

        # 提取配置内容
        kubectl get "$synapse_config_name" -n "$NAMESPACE" -o jsonpath='{.data.homeserver\.yaml}' > "$INSTALL_DIR/synapse-config.yaml"

        # 修复well-known URL中的端口
        sed -i "s|https://$MATRIX_SUBDOMAIN\\.$DOMAIN/|https://$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/|g" "$INSTALL_DIR/synapse-config.yaml"
        sed -i "s|https://$DOMAIN/|https://$DOMAIN:$HTTPS_PORT/|g" "$INSTALL_DIR/synapse-config.yaml"

        # 修复联邦端口配置 (替换任何硬编码的8448端口)
        sed -i "s|:8448|:$FEDERATION_PORT|g" "$INSTALL_DIR/synapse-config.yaml"

        # 修复任何硬编码的标准端口
        sed -i "s|:443/|:$HTTPS_PORT/|g" "$INSTALL_DIR/synapse-config.yaml"
        sed -i "s|:80/|:$HTTP_PORT/|g" "$INSTALL_DIR/synapse-config.yaml"

        # 更新ConfigMap
        kubectl create configmap "${synapse_config_name#configmap/}" \
            --from-file=homeserver.yaml="$INSTALL_DIR/synapse-config.yaml" \
            --dry-run=client -o yaml | kubectl apply -n "$NAMESPACE" -f -

        print_success "Synapse well-known URL已修复"
    else
        print_warning "未找到Synapse ConfigMap"
    fi
}

# 修复Element Web配置
fix_element_web_config() {
    print_info "修复Element Web配置..."

    # 获取Element Web ConfigMap
    local element_config_name=$(kubectl get configmap -n "$NAMESPACE" -o name | grep element | head -1)
    if [[ -n "$element_config_name" ]]; then
        # 备份原配置
        kubectl get "$element_config_name" -n "$NAMESPACE" -o yaml > "$INSTALL_DIR/element-config-backup.yaml"

        # 提取配置内容
        kubectl get "$element_config_name" -n "$NAMESPACE" -o jsonpath='{.data.config\.json}' > "$INSTALL_DIR/element-config.json"

        # 修复服务器URL中的端口
        sed -i "s|\"https://$MATRIX_SUBDOMAIN\\.$DOMAIN/\"|\"https://$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/\"|g" "$INSTALL_DIR/element-config.json"
        sed -i "s|\"https://$AUTH_SUBDOMAIN\\.$DOMAIN/\"|\"https://$AUTH_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/\"|g" "$INSTALL_DIR/element-config.json"
        sed -i "s|\"https://$DOMAIN/\"|\"https://$DOMAIN:$HTTPS_PORT/\"|g" "$INSTALL_DIR/element-config.json"

        # 修复任何硬编码的标准端口
        sed -i "s|\":443/\"|\":$HTTPS_PORT/\"|g" "$INSTALL_DIR/element-config.json"
        sed -i "s|\":80/\"|\":$HTTP_PORT/\"|g" "$INSTALL_DIR/element-config.json"

        # 更新ConfigMap
        kubectl create configmap "${element_config_name#configmap/}" \
            --from-file=config.json="$INSTALL_DIR/element-config.json" \
            --dry-run=client -o yaml | kubectl apply -n "$NAMESPACE" -f -

        print_success "Element Web配置已修复"
    else
        print_warning "未找到Element Web ConfigMap"
    fi
}

# 修复Nginx well-known配置
fix_nginx_wellknown_config() {
    print_info "修复Nginx well-known配置..."

    local nginx_config="$NGINX_SITES_AVAILABLE/matrix-ess"

    if [[ -f "$nginx_config" ]]; then
        # 备份原配置
        local backup_suffix=$(date +%Y%m%d_%H%M%S)
        cp "$nginx_config" "$nginx_config.backup.$backup_suffix"

        # 创建临时配置文件
        local temp_config="/tmp/nginx-matrix-ess-temp"

        # 修复well-known重定向中的端口
        sed "s|https://$MATRIX_SUBDOMAIN\\.$DOMAIN/|https://$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT/|g" "$nginx_config" > "$temp_config"
        sed -i "s|https://$DOMAIN/|https://$DOMAIN:$HTTPS_PORT/|g" "$temp_config"

        # 确保联邦端口正确 (替换任何硬编码的8448端口)
        sed -i "s|:8448|:$FEDERATION_PORT|g" "$temp_config"

        # 修复任何硬编码的标准端口
        sed -i "s|:443/|:$HTTPS_PORT/|g" "$temp_config"
        sed -i "s|:80/|:$HTTP_PORT/|g" "$temp_config"

        # 添加特殊的well-known处理 (如果不存在)
        if ! grep -q "location.*well-known.*matrix" "$temp_config"; then
            # 在server块中添加well-known处理
            sed -i '/location \/ {/i\
    # Matrix well-known endpoints\
    location /.well-known/matrix/server {\
        return 200 '\''{"m.server": "'"$MATRIX_SUBDOMAIN.$DOMAIN:$FEDERATION_PORT"'"}'\'';\
        add_header Content-Type application/json;\
        add_header Access-Control-Allow-Origin *;\
    }\
\
    location /.well-known/matrix/client {\
        return 200 '\''{"m.homeserver": {"base_url": "https://'"$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"'/"}, "m.identity_server": {"base_url": "https://vector.im"}}'\'';\
        add_header Content-Type application/json;\
        add_header Access-Control-Allow-Origin *;\
    }\
' "$temp_config"
        fi

        # 应用修改后的配置
        mv "$temp_config" "$nginx_config"

        # 测试Nginx配置
        if nginx -t; then
            # 重新加载Nginx配置
            systemctl reload nginx
            print_success "Nginx well-known配置已修复并重新加载"
        else
            print_error "Nginx配置测试失败，恢复备份"
            mv "$nginx_config.backup.$backup_suffix" "$nginx_config"
            systemctl reload nginx
        fi
    else
        print_warning "未找到Nginx配置文件: $nginx_config"
    fi
}

# 修复其他可能的配置文件
fix_additional_configs() {
    print_info "检查并修复其他配置文件..."

    # 修复所有Secret中可能包含的URL
    fix_secrets_urls

    # 修复所有Service中的端口配置
    fix_service_ports

    # 修复Ingress配置 (如果存在)
    fix_ingress_configs

    print_success "其他配置文件检查完成"
}

# 修复Secret中的URL
fix_secrets_urls() {
    print_info "修复Secret中的URL..."

    # 获取所有包含URL的Secret
    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o name)

    for secret in $secrets; do
        # 检查Secret是否包含URL配置
        if kubectl get "$secret" -n "$NAMESPACE" -o yaml | grep -q "https://"; then
            print_info "检查Secret: $secret"

            # 备份Secret
            kubectl get "$secret" -n "$NAMESPACE" -o yaml > "$INSTALL_DIR/$(basename $secret)-backup.yaml"

            # 提取并修复Secret数据 (这里需要小心处理base64编码)
            # 注意: 实际实现中需要解码、修改、重新编码
            print_info "Secret $secret 可能需要手动检查"
        fi
    done
}

# 修复Service端口配置
fix_service_ports() {
    print_info "检查Service端口配置..."

    # 检查是否有Service使用了错误的端口
    local services=$(kubectl get svc -n "$NAMESPACE" -o name)

    for service in $services; do
        # 检查Service端口配置
        local service_ports=$(kubectl get "$service" -n "$NAMESPACE" -o jsonpath='{.spec.ports[*].port}')
        print_info "Service $service 端口: $service_ports"
    done
}

# 修复Ingress配置
fix_ingress_configs() {
    print_info "检查Ingress配置..."

    # 获取所有Ingress
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" -o name 2>/dev/null || true)

    if [[ -n "$ingresses" ]]; then
        for ingress in $ingresses; do
            print_info "检查Ingress: $ingress"

            # 备份Ingress配置
            kubectl get "$ingress" -n "$NAMESPACE" -o yaml > "$INSTALL_DIR/$(basename $ingress)-backup.yaml"

            # 检查是否需要修复主机名或端口
            local hosts=$(kubectl get "$ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[*].host}')
            print_info "Ingress $ingress 主机: $hosts"
        done
    else
        print_info "未找到Ingress配置"
    fi
}

# 重启ESS服务以应用配置更改
restart_ess_services() {
    print_info "重启ESS服务以应用配置更改..."

    # 重启MAS
    if kubectl get deployment -n "$NAMESPACE" | grep -q mas; then
        kubectl rollout restart deployment -n "$NAMESPACE" -l app.kubernetes.io/component=matrix-authentication-service
        print_info "已重启MAS服务"
    fi

    # 重启Synapse
    if kubectl get deployment -n "$NAMESPACE" | grep -q synapse; then
        kubectl rollout restart deployment -n "$NAMESPACE" -l app.kubernetes.io/component=synapse
        print_info "已重启Synapse服务"
    fi

    # 重启Element Web
    if kubectl get deployment -n "$NAMESPACE" | grep -q element; then
        kubectl rollout restart deployment -n "$NAMESPACE" -l app.kubernetes.io/component=element-web
        print_info "已重启Element Web服务"
    fi

    # 等待服务重启完成
    print_info "等待服务重启完成..."
    sleep 30

    # 验证服务状态
    kubectl get pods -n "$NAMESPACE"

    print_success "ESS服务重启完成"
}

# 验证配置修复效果
verify_config_fixes() {
    print_info "验证配置修复效果..."

    # 测试well-known端点
    test_wellknown_endpoints

    # 测试重定向URL
    test_redirect_urls

    # 检查服务健康状态
    check_service_health

    print_success "配置修复验证完成"
}

# 测试well-known端点
test_wellknown_endpoints() {
    print_info "测试well-known端点..."

    # 测试Matrix服务器发现
    local server_response=$(curl -s -k "https://localhost:$HTTPS_PORT/.well-known/matrix/server" 2>/dev/null || echo "")
    if [[ "$server_response" == *"$MATRIX_SUBDOMAIN.$DOMAIN:$FEDERATION_PORT"* ]]; then
        print_success "Matrix服务器发现端点正确"
    else
        print_warning "Matrix服务器发现端点可能有问题"
        print_info "响应: $server_response"
    fi

    # 测试Matrix客户端配置
    local client_response=$(curl -s -k "https://localhost:$HTTPS_PORT/.well-known/matrix/client" 2>/dev/null || echo "")
    if [[ "$client_response" == *"$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"* ]]; then
        print_success "Matrix客户端配置端点正确"
    else
        print_warning "Matrix客户端配置端点可能有问题"
        print_info "响应: $client_response"
    fi
}

# 测试重定向URL
test_redirect_urls() {
    print_info "测试重定向URL..."

    # 测试HTTP到HTTPS重定向
    local redirect_response=$(curl -s -I "http://localhost:$HTTP_PORT" 2>/dev/null | head -1 || echo "")
    if [[ "$redirect_response" == *"301"* ]] || [[ "$redirect_response" == *"302"* ]]; then
        print_success "HTTP重定向正常"
    else
        print_warning "HTTP重定向可能有问题"
    fi

    # 测试各子域名访问
    for subdomain in "$WEB_SUBDOMAIN" "$AUTH_SUBDOMAIN" "$MATRIX_SUBDOMAIN"; do
        local response=$(curl -s -k -I "https://localhost:$HTTPS_PORT" -H "Host: $subdomain.$DOMAIN" 2>/dev/null | head -1 || echo "")
        if [[ "$response" == *"200"* ]] || [[ "$response" == *"301"* ]] || [[ "$response" == *"302"* ]]; then
            print_success "$subdomain.$DOMAIN 访问正常"
        else
            print_warning "$subdomain.$DOMAIN 访问可能有问题"
        fi
    done
}

# 检查服务健康状态
check_service_health() {
    print_info "检查服务健康状态..."

    # 检查Pod状态
    local running_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep Running | wc -l)
    local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)

    print_info "运行中的Pod: $running_pods/$total_pods"

    if [[ $running_pods -eq $total_pods ]]; then
        print_success "所有Pod运行正常"
    else
        print_warning "部分Pod可能有问题"
        kubectl get pods -n "$NAMESPACE"
    fi

    # 检查服务端点
    kubectl get endpoints -n "$NAMESPACE"
}

# 检查硬编码端口
check_hardcoded_ports() {
    print_info "检查配置文件中的硬编码端口..."

    local hardcoded_found=0
    local check_files=(
        "$INSTALL_DIR/mas-config.yaml"
        "$INSTALL_DIR/synapse-config.yaml"
        "$INSTALL_DIR/element-config.json"
        "$NGINX_SITES_AVAILABLE/matrix-ess"
    )

    # 检查本地配置文件
    for file in "${check_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_info "检查文件: $file"

            # 检查常见的硬编码端口
            local hardcoded_ports=(":80/" ":443/" ":8080/" ":8443/" ":8448/")
            for port in "${hardcoded_ports[@]}"; do
                if grep -q "$port" "$file" 2>/dev/null; then
                    # 排除我们自己配置的端口
                    if [[ "$port" == ":$HTTP_PORT/" ]] || [[ "$port" == ":$HTTPS_PORT/" ]] || [[ "$port" == ":$FEDERATION_PORT/" ]]; then
                        continue
                    fi
                    print_warning "发现硬编码端口 $port 在文件 $file"
                    ((hardcoded_found++))
                fi
            done
        fi
    done

    # 检查Kubernetes ConfigMap
    print_info "检查Kubernetes ConfigMap..."
    local configmaps=$(kubectl get configmap -n "$NAMESPACE" -o name 2>/dev/null || true)

    for cm in $configmaps; do
        # 检查ConfigMap中的硬编码端口
        local cm_content=$(kubectl get "$cm" -n "$NAMESPACE" -o yaml 2>/dev/null || echo "")

        # 检查是否包含不应该存在的硬编码端口
        if echo "$cm_content" | grep -E ":80[^0-9]|:443[^0-9]|:8080[^0-9]|:8443[^0-9]|:8448[^0-9]" | grep -v ":$HTTP_PORT\|:$HTTPS_PORT\|:$FEDERATION_PORT" >/dev/null 2>&1; then
            print_warning "ConfigMap $cm 可能包含硬编码端口"
            ((hardcoded_found++))
        fi
    done

    if [[ $hardcoded_found -eq 0 ]]; then
        print_success "未发现硬编码端口，所有配置正确使用变量"
    else
        print_warning "发现 $hardcoded_found 个可能的硬编码端口问题"
        print_info "请检查上述文件和ConfigMap"
    fi

    return $hardcoded_found
}

# 部署ESS
deploy_ess() {
    print_info "部署ESS..."

    # 确保使用正确的kubeconfig
    local kubeconfig_file="$K3S_CONFIG_DIR/k3s.yaml"
    export KUBECONFIG="$kubeconfig_file"

    # 验证kubeconfig文件存在
    if [[ ! -f "$kubeconfig_file" ]]; then
        print_error "K3s kubeconfig文件不存在: $kubeconfig_file"
        print_info "检查K3s安装状态:"
        systemctl status k3s --no-pager
        exit 1
    fi

    # 验证kubectl连接
    print_info "验证kubectl连接..."
    local kubectl_retry=0
    while ! kubectl get nodes &>/dev/null && [[ $kubectl_retry -lt 10 ]]; do
        sleep 5
        ((kubectl_retry++))
        print_info "等待kubectl连接... ($kubectl_retry/10)"
        export KUBECONFIG="$K3S_CONFIG_DIR/k3s.yaml"
    done

    if ! kubectl get nodes &>/dev/null; then
        print_warning "kubectl连接失败，尝试修复..."

        if fix_k3s_connection; then
            print_success "K3s连接已修复，继续部署"
        else
            print_error "kubectl无法连接到Kubernetes集群"
            print_info "诊断信息:"
            print_info "KUBECONFIG: $KUBECONFIG"
            print_info "K3s服务状态:"
            systemctl status k3s --no-pager
            print_info "K3s进程:"
            ps aux | grep k3s | grep -v grep || echo "未找到K3s进程"
            print_info "API服务器端口:"
            netstat -tlnp | grep :6443 || echo "6443端口未监听"
            exit 1
        fi
    fi

    # 显示集群信息
    print_info "Kubernetes集群信息:"
    kubectl get nodes
    kubectl get namespaces

    # 创建命名空间
    print_info "创建命名空间: $NAMESPACE"
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_info "命名空间 $NAMESPACE 已存在"
    else
        kubectl create namespace "$NAMESPACE"
        print_success "命名空间 $NAMESPACE 创建成功"
    fi

    # 验证Helm
    if ! command -v helm &>/dev/null; then
        print_error "Helm未安装"
        exit 1
    fi

    print_info "Helm版本:"
    helm version

    # 验证配置文件
    if [[ ! -f "$INSTALL_DIR/ess-values.yaml" ]]; then
        print_error "ESS配置文件不存在: $INSTALL_DIR/ess-values.yaml"
        exit 1
    fi

    print_info "ESS配置文件内容:"
    cat "$INSTALL_DIR/ess-values.yaml"

    # 部署ESS
    print_info "开始部署ESS到命名空间: $NAMESPACE"
    print_info "使用配置文件: $INSTALL_DIR/ess-values.yaml"

    if helm upgrade --install --namespace "$NAMESPACE" ess \
        oci://ghcr.io/element-hq/ess-helm/matrix-stack \
        -f "$INSTALL_DIR/ess-values.yaml" \
        --wait --timeout=15m \
        --debug; then
        print_success "ESS部署完成"

        # 等待配置文件生成
        print_info "等待ESS配置文件生成..."
        sleep 30

        # 后处理ESS配置文件
        post_process_ess_config
    else
        print_error "ESS部署失败"
        print_info "检查部署状态:"
        kubectl get pods -n "$NAMESPACE"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp'
        print_info "检查Helm状态:"
        helm list -n "$NAMESPACE"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    print_info "验证部署..."

    # 检查Pod状态
    kubectl get pods -n "$NAMESPACE"

    # 检查服务状态
    kubectl get svc -n "$NAMESPACE"

    # 检查Nginx状态
    systemctl status nginx --no-pager

    # 测试HTTP重定向 (可选)
    print_info "测试HTTP重定向..."
    if curl -s -I "http://localhost:$HTTP_PORT" | grep -q "301\|302"; then
        print_success "HTTP重定向正常"
    else
        print_warning "HTTP重定向可能有问题，请检查Nginx配置"
    fi

    # 测试HTTPS访问 (可选)
    print_info "测试HTTPS访问..."
    if curl -s -k -I "https://localhost:$HTTPS_PORT" | grep -q "200\|301\|302"; then
        print_success "HTTPS访问正常"
    else
        print_warning "HTTPS访问可能有问题，请检查SSL证书和Nginx配置"
    fi

    print_success "部署验证完成"
}

# 显示访问信息
show_access_info() {
    print_success "=== ESS部署完成 ==="
    echo
    print_info "访问地址:"
    echo "  Element Web: https://$WEB_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"
    echo "  认证服务:    https://$AUTH_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"
    echo "  Matrix服务器: https://$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"
    echo
    print_info "管理命令:"
    echo "  查看Pod状态: kubectl get pods -n $NAMESPACE"
    echo "  查看日志:    kubectl logs -n $NAMESPACE deployment/ess-synapse"
    echo "  创建用户:    kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
    echo
    print_warning "请确保路由器已配置端口映射:"
    echo "  $HTTP_PORT -> 服务器IP:$HTTP_PORT"
    echo "  $HTTPS_PORT -> 服务器IP:$HTTPS_PORT"
    echo "  $FEDERATION_PORT -> 服务器IP:$FEDERATION_PORT"
    echo "  $WEBRTC_TCP_PORT -> 服务器IP:$WEBRTC_TCP_PORT"
    echo "  $WEBRTC_UDP_PORT -> 服务器IP:$WEBRTC_UDP_PORT"
    echo "  $WEBRTC_UDP_RANGE_START-$WEBRTC_UDP_RANGE_END -> 服务器IP:$WEBRTC_UDP_RANGE_START-$WEBRTC_UDP_RANGE_END"
}

# 主函数
main() {
    print_info "开始ESS外部Nginx反代部署..."

    # 首先验证配置
    validate_config

    check_root
    check_requirements
    install_dependencies
    configure_firewall
    install_k3s
    install_helm
    generate_ssl_certificates
    configure_nginx
    generate_ess_config
    deploy_ess
    verify_deployment
    show_access_info

    print_success "ESS外部Nginx反代部署完成!"
}

# 脚本入口 - 直接执行主函数 (支持bash <(curl)方式)
main "$@"
