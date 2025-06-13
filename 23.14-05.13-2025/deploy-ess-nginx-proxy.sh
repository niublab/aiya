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
INSTALL_DIR="${INSTALL_DIR:-/opt/matrix-ess}"
NAMESPACE="${NAMESPACE:-ess}"

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

# 调用配置验证
validate_config

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
    print_info "配置防火墙..."
    
    # 允许SSH
    ufw allow ssh
    
    # 允许HTTP/HTTPS端口
    ufw allow $HTTP_PORT/tcp
    ufw allow $HTTPS_PORT/tcp
    ufw allow $FEDERATION_PORT/tcp
    
    # 允许WebRTC端口
    ufw allow 30881/tcp
    ufw allow 30882/udp
    ufw allow 30152:30352/udp
    
    # 启用防火墙
    ufw --force enable
    
    print_success "防火墙配置完成"
}

# 安装K3s
install_k3s() {
    print_info "安装K3s..."
    
    # 创建K3s配置目录
    mkdir -p /var/lib/rancher/k3s/server/manifests
    
    # 创建Traefik配置
    cat > /var/lib/rancher/k3s/server/manifests/traefik-config.yaml << EOF
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
    curl -sfL https://get.k3s.io | sh -
    
    # 配置kubectl
    mkdir -p ~/.kube
    export KUBECONFIG=~/.kube/config
    k3s kubectl config view --raw > "$KUBECONFIG"
    chmod 600 "$KUBECONFIG"
    
    # 等待K3s启动
    print_info "等待K3s启动..."
    sleep 30
    
    print_success "K3s安装完成"
}

# 安装Helm
install_helm() {
    print_info "安装Helm..."
    
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    print_success "Helm安装完成"
}

# 生成SSL证书
generate_ssl_certificates() {
    print_info "生成SSL证书..."

    # 设置默认值
    local cert_type="${CERT_TYPE:-letsencrypt}"
    local test_mode="${TEST_MODE:-false}"
    local cert_email="${CERT_EMAIL:-admin@$DOMAIN}"

    # 如果启用测试模式，自动使用staging证书
    if [[ "$test_mode" == "true" ]]; then
        cert_type="letsencrypt-staging"
        print_warning "测试模式已启用，将使用Let's Encrypt Staging证书"
        print_warning "Staging证书不被浏览器信任，仅用于测试目的"
    fi

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

    print_success "SSL证书配置完成"
}

# 安装DNS验证插件
install_dns_plugins() {
    local dns_provider="${DNS_PROVIDER:-cloudflare}"

    print_info "安装DNS验证插件: $dns_provider"

    case "$dns_provider" in
        "cloudflare")
            if command -v apt &> /dev/null; then
                apt update
                apt install -y python3-certbot-dns-cloudflare
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-cloudflare
            else
                print_error "不支持的包管理器"
                exit 1
            fi
            ;;
        "route53")
            if command -v apt &> /dev/null; then
                apt install -y python3-certbot-dns-route53
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-route53
            fi
            ;;
        "digitalocean")
            if command -v apt &> /dev/null; then
                apt install -y python3-certbot-dns-digitalocean
            elif command -v yum &> /dev/null; then
                yum install -y python3-certbot-dns-digitalocean
            fi
            ;;
        *)
            print_warning "未知的DNS提供商: $dns_provider，跳过插件安装"
            ;;
    esac

    print_success "DNS验证插件安装完成"
}

# 配置DNS验证凭据
setup_dns_credentials() {
    local dns_provider="${DNS_PROVIDER:-cloudflare}"
    local creds_dir="/etc/letsencrypt"

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

        # 安装DNS插件
        install_dns_plugins

        # 配置DNS凭据
        setup_dns_credentials

        # 构建certbot命令
        local certbot_cmd="certbot certonly --agree-tos --no-eff-email"
        certbot_cmd="$certbot_cmd --email \"$email\""
        certbot_cmd="$certbot_cmd -d \"$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"app.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"mas.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"rtc.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"matrix.$DOMAIN\""

        # 添加DNS插件参数
        case "$dns_provider" in
            "cloudflare")
                certbot_cmd="$certbot_cmd --dns-cloudflare"
                certbot_cmd="$certbot_cmd --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini"
                ;;
            "route53")
                certbot_cmd="$certbot_cmd --dns-route53"
                certbot_cmd="$certbot_cmd --dns-route53-credentials /etc/letsencrypt/route53.ini"
                ;;
            "digitalocean")
                certbot_cmd="$certbot_cmd --dns-digitalocean"
                certbot_cmd="$certbot_cmd --dns-digitalocean-credentials /etc/letsencrypt/digitalocean.ini"
                ;;
            *)
                print_error "不支持的DNS提供商: $dns_provider"
                exit 1
                ;;
        esac

        if [[ -n "$staging_flag" ]]; then
            certbot_cmd="$certbot_cmd $staging_flag"
        fi

        print_info "执行DNS验证..."
        print_info "这可能需要几分钟时间等待DNS传播..."

    else
        # HTTP验证 (原有方式)
        print_info "使用HTTP验证方式"
        print_warning "需要确保80端口可以从互联网访问"

        # 停止nginx以释放80端口
        systemctl stop nginx || true

        # 构建certbot命令
        local certbot_cmd="certbot certonly --standalone --agree-tos --no-eff-email"
        certbot_cmd="$certbot_cmd --email \"$email\""
        certbot_cmd="$certbot_cmd -d \"$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"app.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"mas.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"rtc.$DOMAIN\""
        certbot_cmd="$certbot_cmd -d \"matrix.$DOMAIN\""

        if [[ -n "$staging_flag" ]]; then
            certbot_cmd="$certbot_cmd $staging_flag"
        fi
    fi

    # 执行证书生成
    if eval "$certbot_cmd"; then
        print_success "Let's Encrypt证书生成成功"
        if [[ -n "$staging_flag" ]]; then
            print_warning "注意: 这是测试证书，浏览器会显示不安全警告"
        fi

        # 显示证书信息
        print_info "证书信息:"
        openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -text -noout | grep -E "(Subject:|DNS:|Not After)"

    else
        print_error "Let's Encrypt证书生成失败"
        print_info "请检查:"
        if [[ "$challenge" == "dns" ]]; then
            print_info "1. DNS API凭据是否正确"
            print_info "2. API Token权限是否足够"
            print_info "3. 域名是否在DNS提供商管理"
        else
            print_info "1. 域名是否正确解析到此服务器"
            print_info "2. 80端口是否可以从互联网访问"
            print_info "3. 防火墙是否阻止了连接"
        fi
        exit 1
    fi
}



# 使用自定义证书
use_custom_cert() {
    print_info "使用自定义证书..."

    local custom_cert="${CUSTOM_CERT_PATH:-/etc/ssl/certs/$DOMAIN.crt}"
    local custom_key="${CUSTOM_KEY_PATH:-/etc/ssl/private/$DOMAIN.key}"
    local cert_dir="/etc/letsencrypt/live/$DOMAIN"

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
    cat > /etc/nginx/sites-available/matrix-ess << EOF
# HTTP重定向到HTTPS
server {
    listen $HTTP_PORT;
    server_name $DOMAIN app.$DOMAIN mas.$DOMAIN rtc.$DOMAIN matrix.$DOMAIN;
    return 301 https://\$host:$HTTPS_PORT\$request_uri;
}

# 主HTTPS服务
server {
    listen $HTTPS_PORT ssl http2;
    server_name $DOMAIN app.$DOMAIN mas.$DOMAIN rtc.$DOMAIN matrix.$DOMAIN;

    # SSL配置
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
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
    server_name $DOMAIN matrix.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

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
    ln -sf /etc/nginx/sites-available/matrix-ess /etc/nginx/sites-enabled/
    
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
    host: "app.$DOMAIN"
    tlsEnabled: false

# Matrix Authentication Service配置
matrixAuthenticationService:
  ingress:
    host: "mas.$DOMAIN"
    tlsEnabled: false

# Matrix RTC配置
matrixRTC:
  ingress:
    host: "rtc.$DOMAIN"
    tlsEnabled: false
  sfu:
    exposedServices:
      rtcTcp:
        enabled: true
        portType: NodePort
        port: 30881
      rtcMuxedUdp:
        enabled: true
        portType: NodePort
        port: 30882

# Synapse配置
synapse:
  ingress:
    host: "matrix.$DOMAIN"
    tlsEnabled: false

# Well-known配置
wellKnownDelegation:
  ingress:
    host: "$DOMAIN"
    tlsEnabled: false
EOF
    
    print_success "ESS配置生成完成"
}

# 部署ESS
deploy_ess() {
    print_info "部署ESS..."
    
    # 创建命名空间
    kubectl create namespace "$NAMESPACE" || true
    
    # 部署ESS
    helm upgrade --install --namespace "$NAMESPACE" ess \
        oci://ghcr.io/element-hq/ess-helm/matrix-stack \
        -f "$INSTALL_DIR/ess-values.yaml" \
        --wait --timeout=10m
    
    print_success "ESS部署完成"
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
    
    print_success "部署验证完成"
}

# 显示访问信息
show_access_info() {
    print_success "=== ESS部署完成 ==="
    echo
    print_info "访问地址:"
    echo "  Element Web: https://app.$DOMAIN:$HTTPS_PORT"
    echo "  认证服务:    https://mas.$DOMAIN:$HTTPS_PORT"
    echo "  Matrix服务器: https://matrix.$DOMAIN:$HTTPS_PORT"
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
    echo "  30881 -> 服务器IP:30881"
    echo "  30882 -> 服务器IP:30882"
    echo "  30152-30352 -> 服务器IP:30152-30352"
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

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
