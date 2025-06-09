#!/bin/bash

# AIYA - Matrix服务器一键部署脚本 (修复版)
# 基于Element Server Suite Community版本
# 版本: 3.0-fixed
# 使用方法: bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/aiya-config"
NAMESPACE="matrix"
DOMAIN=""
CERT_EMAIL=""
CERT_MODE="staging"
CERT_ISSUER="letsencrypt-staging"
POSTGRES_PASSWORD=""

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法确定操作系统类型"
        return 1
    fi
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo bash setup.sh"
        return 1
    fi
    
    # 检查内存
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $memory_gb -lt 2 ]]; then
        log_warning "系统内存少于2GB，可能影响性能"
    fi
    
    # 检查磁盘空间
    local disk_space=$(df / | awk 'NR==2{print $4}')
    if [[ $disk_space -lt 10485760 ]]; then  # 10GB in KB
        log_warning "根分区可用空间少于10GB，可能影响部署"
    fi
    
    log_success "系统要求检查完成"
}

# 检查并安装依赖
check_dependencies() {
    log_info "检查系统依赖..."

    local deps=("curl" "wget" "jq" "openssl")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_info "安装缺失的依赖: ${missing_deps[*]}"
        
        # 更新包管理器
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y curl wget jq openssl gnupg2 software-properties-common apt-transport-https ca-certificates
        elif command -v yum &> /dev/null; then
            yum update -y
            yum install -y curl wget jq openssl gnupg2
        elif command -v dnf &> /dev/null; then
            dnf update -y
            dnf install -y curl wget jq openssl gnupg2
        else
            log_error "不支持的包管理器，请手动安装依赖"
            return 1
        fi
    fi

    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_info "安装Docker..."
        install_docker
    else
        log_success "Docker已安装"
    fi

    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_info "安装Docker Compose..."
        install_docker_compose
    else
        log_success "Docker Compose已安装"
    fi

    log_success "所有依赖已满足"
}

# 安装Docker
install_docker() {
    log_info "安装Docker..."
    
    # 卸载旧版本
    if command -v apt-get &> /dev/null; then
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # 添加Docker官方GPG密钥
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # 添加Docker仓库
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # 安装Docker
        apt-get update -qq
        apt-get install -y docker-ce docker-ce-cli containerd.io
    elif command -v yum &> /dev/null; then
        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # 启动Docker服务
    systemctl start docker
    systemctl enable docker
    
    # 验证安装
    if docker --version &> /dev/null; then
        log_success "Docker安装成功"
    else
        log_error "Docker安装失败"
        return 1
    fi
}

# 安装Docker Compose
install_docker_compose() {
    log_info "安装Docker Compose..."
    
    # 获取最新版本
    local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    
    # 下载并安装
    curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # 创建符号链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # 验证安装
    if docker-compose --version &> /dev/null; then
        log_success "Docker Compose安装成功"
    else
        log_error "Docker Compose安装失败"
        return 1
    fi
}

# 配置收集菜单
collect_configuration() {
    log_header "配置收集"

    # 创建配置目录
    mkdir -p "$CONFIG_DIR"

    # 域名配置
    while [[ -z "$DOMAIN" ]]; do
        echo -e "${CYAN}请输入您的域名 (例如: example.com):${NC}"
        read -r DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_error "域名不能为空"
        fi
    done

    # 证书邮箱
    while [[ -z "$CERT_EMAIL" ]]; do
        echo -e "${CYAN}请输入证书申请邮箱:${NC}"
        read -r CERT_EMAIL
        if [[ -z "$CERT_EMAIL" ]]; then
            log_error "证书邮箱不能为空"
        fi
    done

    # 证书模式选择
    echo -e "${CYAN}请选择证书模式:${NC}"
    echo "1) 测试证书 (Let's Encrypt Staging) - 推荐用于测试"
    echo "2) 生产证书 (Let's Encrypt Production) - 用于正式环境"
    read -r cert_choice

    case $cert_choice in
        1)
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            ;;
        2)
            CERT_MODE="production"
            CERT_ISSUER="letsencrypt-prod"
            ;;
        *)
            log_warning "无效选择，使用测试证书"
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            ;;
    esac

    # 生成随机密码
    POSTGRES_PASSWORD=$(openssl rand -base64 32)

    # 保存配置
    save_configuration

    # 显示配置摘要
    show_configuration_summary
}

# 保存配置
save_configuration() {
    cat > "$CONFIG_DIR/config.env" << EOF
# AIYA Matrix服务器部署配置
# 生成时间: $(date)

DOMAIN="$DOMAIN"
CERT_EMAIL="$CERT_EMAIL"
CERT_MODE="$CERT_MODE"
CERT_ISSUER="$CERT_ISSUER"
NAMESPACE="$NAMESPACE"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
EOF

    log_success "配置已保存到: $CONFIG_DIR/config.env"
}

# 加载配置
load_configuration() {
    if [[ -f "$CONFIG_DIR/config.env" ]]; then
        source "$CONFIG_DIR/config.env"
        log_success "配置已加载"
        return 0
    else
        log_warning "配置文件不存在"
        return 1
    fi
}

# 显示配置摘要
show_configuration_summary() {
    log_header "配置摘要"
    echo -e "${CYAN}域名:${NC} $DOMAIN"
    echo -e "${CYAN}Matrix服务器:${NC} https://$DOMAIN"
    echo -e "${CYAN}Element Web:${NC} https://element.$DOMAIN"
    echo -e "${CYAN}证书模式:${NC} $CERT_MODE"
    echo -e "${CYAN}证书邮箱:${NC} $CERT_EMAIL"
    echo ""
}

# 生成Docker Compose配置
generate_docker_compose() {
    log_info "生成Docker Compose配置..."

    cat > "$CONFIG_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  # PostgreSQL数据库
  postgres:
    image: postgres:15-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - matrix_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Synapse Matrix服务器
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix-synapse
    restart: unless-stopped
    environment:
      SYNAPSE_SERVER_NAME: ${DOMAIN}
      SYNAPSE_REPORT_STATS: "no"
    volumes:
      - synapse_data:/data
      - ./synapse:/config
    networks:
      - matrix_network
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8008:8008"
      - "8448:8448"

  # Element Web客户端
  element:
    image: vectorim/element-web:latest
    container_name: matrix-element
    restart: unless-stopped
    volumes:
      - ./element/config.json:/app/config.json:ro
    networks:
      - matrix_network
    ports:
      - "8080:80"

  # Nginx反向代理
  nginx:
    image: nginx:alpine
    container_name: matrix-nginx
    restart: unless-stopped
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - certbot_data:/var/www/certbot:ro
    networks:
      - matrix_network
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - synapse
      - element

  # Certbot证书管理
  certbot:
    image: certbot/certbot:latest
    container_name: matrix-certbot
    volumes:
      - certbot_data:/var/www/certbot
      - ./nginx/ssl:/etc/letsencrypt
    command: certonly --webroot --webroot-path=/var/www/certbot --email ${CERT_EMAIL} --agree-tos --no-eff-email -d ${DOMAIN} -d element.${DOMAIN}

volumes:
  postgres_data:
  synapse_data:
  certbot_data:

networks:
  matrix_network:
    driver: bridge
EOF

    log_success "Docker Compose配置生成完成"
}

# 生成Synapse配置
generate_synapse_config() {
    log_info "生成Synapse配置..."

    mkdir -p "$CONFIG_DIR/synapse"

    cat > "$CONFIG_DIR/synapse/homeserver.yaml" << EOF
# Synapse配置文件
server_name: "${DOMAIN}"
pid_file: /data/homeserver.pid
web_client_location: https://element.${DOMAIN}
public_baseurl: https://${DOMAIN}

# 监听配置
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [client, federation]
        compress: false

# 数据库配置
database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

# 日志配置
log_config: "/config/log.config"

# 媒体存储
media_store_path: "/data/media_store"
max_upload_size: "100M"
max_image_pixels: "32M"

# 注册配置
enable_registration: true
enable_registration_without_verification: true
registration_requires_token: false
allow_guest_access: false

# 联邦配置
federation_domain_whitelist: []
federation_metrics_domains: []

# 安全配置
suppress_key_server_warning: true
trusted_key_servers:
  - server_name: "matrix.org"

# 签名密钥
signing_key_path: "/data/signing.key"

# 应用服务
app_service_config_files: []

# 推送配置
push:
  include_content: true

# 速率限制
rc_message:
  per_second: 0.2
  burst_count: 10

rc_registration:
  per_second: 0.17
  burst_count: 3

rc_login:
  address:
    per_second: 0.17
    burst_count: 3
  account:
    per_second: 0.17
    burst_count: 3
  failed_attempts:
    per_second: 0.17
    burst_count: 3

# 其他配置
report_stats: false
macaroon_secret_key: "$(openssl rand -base64 32)"
form_secret: "$(openssl rand -base64 32)"
EOF

    # 生成日志配置
    cat > "$CONFIG_DIR/synapse/log.config" << EOF
version: 1

formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'

handlers:
  file:
    class: logging.handlers.TimedRotatingFileHandler
    formatter: precise
    filename: /data/homeserver.log
    when: midnight
    backupCount: 3
    encoding: utf8

  console:
    class: logging.StreamHandler
    formatter: precise

loggers:
    synapse.storage.SQL:
        level: INFO

root:
    level: INFO
    handlers: [file, console]

disable_existing_loggers: false
EOF

    log_success "Synapse配置生成完成"
}

# 生成Element配置
generate_element_config() {
    log_info "生成Element Web配置..."

    mkdir -p "$CONFIG_DIR/element"

    cat > "$CONFIG_DIR/element/config.json" << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${DOMAIN}",
            "server_name": "${DOMAIN}"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "hosting_signup_link": "https://element.io/matrix-services?utm_source=element-web&utm_medium=web",
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "uisi_autorageshake_app": "element-auto-uisi",
    "showLabsSettings": true,
    "piwik": false,
    "roomDirectory": {
        "servers": [
            "${DOMAIN}",
            "matrix.org"
        ]
    },
    "enable_presence_by_hs_url": {
        "https://matrix.org": false,
        "https://matrix-client.matrix.org": false
    },
    "terms_and_conditions_links": [
        {
            "url": "https://element.io/privacy",
            "text": "Privacy Policy"
        },
        {
            "url": "https://element.io/terms-of-service",
            "text": "Terms of Service"
        }
    ],
    "hostSignup": {
        "brand": "Element Home",
        "cookiePolicyUrl": "https://element.io/cookie-policy",
        "domains": [
            "matrix.org"
        ],
        "privacyPolicyUrl": "https://element.io/privacy",
        "termsOfServiceUrl": "https://element.io/terms-of-service",
        "url": "https://ems.element.io/element-home/in-app-loader"
    },
    "sentry": {
        "dsn": "https://029a0eb289f942508ae0fb17935bd8c5@sentry.matrix.org/6",
        "environment": "develop"
    },
    "posthog": {
        "projectApiKey": "phc_Jzsm6DTm6V2705zeU5dcNvQDlonOR68XvX2sh1sEOHO",
        "apiHost": "https://posthog.element.io"
    },
    "features": {
        "feature_spotlight": true,
        "feature_video_rooms": true,
        "feature_element_call_video_rooms": true,
        "feature_group_calls": true
    },
    "element_call": {
        "url": "https://call.element.io",
        "use_exclusively": false,
        "participant_limit": 8,
        "brand": "Element Call"
    },
    "map_style_url": "https://api.maptiler.com/maps/streets/style.json?key=fU3vlMsMn4Jb6dnEIFsx"
}
EOF

    log_success "Element Web配置生成完成"
}

# 生成Nginx配置
generate_nginx_config() {
    log_info "生成Nginx配置..."

    mkdir -p "$CONFIG_DIR/nginx"

    cat > "$CONFIG_DIR/nginx/nginx.conf" << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # 基本设置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # HTTP重定向到HTTPS
    server {
        listen 80;
        server_name ${DOMAIN} element.${DOMAIN};
        
        # Let's Encrypt验证
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        # 重定向到HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    # Matrix服务器 (${DOMAIN})
    server {
        listen 443 ssl http2;
        server_name ${DOMAIN};

        # SSL配置
        ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # 安全头
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        add_header X-XSS-Protection "1; mode=block";

        # Matrix客户端API
        location ~ ^(/_matrix|/_synapse/client) {
            proxy_pass http://synapse:8008;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Host \$host;
            proxy_buffering off;
        }

        # Matrix联邦API
        location ~ ^(/_matrix/federation|/_matrix/key) {
            proxy_pass http://synapse:8008;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Host \$host;
            proxy_buffering off;
        }

        # 健康检查
        location /health {
            return 200 "OK";
            add_header Content-Type text/plain;
        }
    }

    # Element Web客户端 (element.${DOMAIN})
    server {
        listen 443 ssl http2;
        server_name element.${DOMAIN};

        # SSL配置
        ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # 安全头
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-XSS-Protection "1; mode=block";
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://${DOMAIN}; media-src 'self'; object-src 'none'; frame-src 'self'";

        # Element Web
        location / {
            proxy_pass http://element:80;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Host \$host;
            proxy_buffering off;
        }
    }
}
EOF

    log_success "Nginx配置生成完成"
}

# 部署Matrix服务器
deploy_matrix_server() {
    log_header "部署Matrix服务器"

    # 切换到配置目录
    cd "$CONFIG_DIR"

    # 生成Synapse签名密钥
    if [[ ! -f "$CONFIG_DIR/synapse/signing.key" ]]; then
        log_info "生成Synapse签名密钥..."
        docker run --rm -v "$CONFIG_DIR/synapse:/data" matrixdotorg/synapse:latest generate
    fi

    # 启动服务
    log_info "启动Matrix服务器..."
    docker-compose up -d postgres

    # 等待数据库启动
    log_info "等待PostgreSQL启动..."
    sleep 30

    # 启动Synapse
    docker-compose up -d synapse

    # 等待Synapse启动
    log_info "等待Synapse启动..."
    sleep 30

    # 启动Element Web
    docker-compose up -d element

    # 启动Nginx
    docker-compose up -d nginx

    log_success "Matrix服务器部署完成"
}

# 申请SSL证书
setup_ssl_certificates() {
    log_info "申请SSL证书..."

    cd "$CONFIG_DIR"

    # 首次申请证书
    if [[ "$CERT_MODE" == "production" ]]; then
        docker-compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "$CERT_EMAIL" --agree-tos --no-eff-email -d "$DOMAIN" -d "element.$DOMAIN"
    else
        docker-compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "$CERT_EMAIL" --agree-tos --no-eff-email --staging -d "$DOMAIN" -d "element.$DOMAIN"
    fi

    # 重启Nginx以加载证书
    docker-compose restart nginx

    log_success "SSL证书配置完成"
}

# 创建管理员用户
create_admin_user() {
    log_header "创建管理员用户"

    echo -e "${CYAN}请输入管理员用户名:${NC}"
    read -r admin_username

    echo -e "${CYAN}请输入管理员密码:${NC}"
    read -s admin_password

    cd "$CONFIG_DIR"

    # 创建管理员用户
    docker-compose exec synapse register_new_matrix_user -u "$admin_username" -p "$admin_password" -a -c /config/homeserver.yaml http://localhost:8008

    log_success "管理员用户创建完成"
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."

    cd "$CONFIG_DIR"

    # 检查服务状态
    local failed_services=$(docker-compose ps --services --filter "status=exited")

    if [[ -z "$failed_services" ]]; then
        log_success "所有服务运行正常"
    else
        log_warning "以下服务状态异常: $failed_services"
        docker-compose ps
    fi

    # 检查端口
    if netstat -tuln | grep -q ":443"; then
        log_success "HTTPS端口(443)正常监听"
    else
        log_warning "HTTPS端口(443)未监听"
    fi

    if netstat -tuln | grep -q ":80"; then
        log_success "HTTP端口(80)正常监听"
    else
        log_warning "HTTP端口(80)未监听"
    fi
}

# 显示访问信息
show_access_information() {
    log_header "访问信息"
    echo -e "${CYAN}Matrix服务器:${NC} https://$DOMAIN"
    echo -e "${CYAN}Element Web客户端:${NC} https://element.$DOMAIN"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "1. 请确保防火墙允许80和443端口的访问"
    echo "2. 请确保域名DNS解析指向您的服务器IP"
    echo "3. 证书可能需要几分钟时间完成申请和验证"
    echo "4. 如果无法访问，请检查服务状态："
    echo "   cd $CONFIG_DIR && docker-compose ps"
    echo "   docker-compose logs"
    echo ""
}

# 清理部署
cleanup_deployment() {
    log_header "清理部署环境"

    echo -e "${YELLOW}警告: 此操作将删除所有Matrix相关的部署和数据!${NC}"
    echo -e "${CYAN}确认要继续吗? (输入 'YES' 确认):${NC}"
    read -r confirmation

    if [[ "$confirmation" != "YES" ]]; then
        log_info "操作已取消"
        return 0
    fi

    log_info "开始清理部署..."

    # 停止并删除容器
    if [[ -f "$CONFIG_DIR/docker-compose.yml" ]]; then
        cd "$CONFIG_DIR"
        docker-compose down -v
        docker-compose rm -f
    fi

    # 删除镜像
    echo -e "${CYAN}是否删除Docker镜像? (y/n):${NC}"
    read -r delete_images

    if [[ "$delete_images" =~ ^[Yy]$ ]]; then
        docker rmi matrixdotorg/synapse:latest vectorim/element-web:latest nginx:alpine postgres:15-alpine certbot/certbot:latest 2>/dev/null || true
    fi

    # 询问是否删除配置文件
    echo -e "${CYAN}是否删除配置文件? (y/n):${NC}"
    read -r delete_config

    if [[ "$delete_config" =~ ^[Yy]$ ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            log_info "删除配置目录: $CONFIG_DIR"
            rm -rf "$CONFIG_DIR"
        fi
    fi

    log_success "清理完成!"
}

# 显示服务状态
show_service_status() {
    log_header "服务状态"

    if ! load_configuration; then
        log_error "配置文件不存在"
        return 0
    fi

    if [[ ! -f "$CONFIG_DIR/docker-compose.yml" ]]; then
        log_error "Docker Compose配置不存在，可能尚未部署"
        return 0
    fi

    cd "$CONFIG_DIR"

    echo -e "${CYAN}=== 容器状态 ===${NC}"
    docker-compose ps

    echo -e "\n${CYAN}=== 服务日志 (最近20行) ===${NC}"
    docker-compose logs --tail=20

    echo -e "\n${CYAN}=== 系统资源使用 ===${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
}

# 主菜单
show_main_menu() {
    clear
    log_header "AIYA - Matrix服务器部署工具 (修复版)"
    echo ""
    echo "1) 配置部署参数"
    echo "2) 开始部署"
    echo "3) 查看当前配置"
    echo "4) 查看服务状态"
    echo "5) 创建管理员用户"
    echo "6) 清理部署"
    echo "0) 退出"
    echo ""
    echo -e "${CYAN}请选择操作 [0-6]:${NC}"
}

# 主函数
main() {
    # 检查系统要求
    check_system_requirements || exit 1

    # 检查依赖
    check_dependencies || exit 1

    # 如果有参数，直接执行自动部署
    if [[ $# -gt 0 && "$1" == "auto" ]]; then
        log_header "自动部署模式"

        # 配置收集
        collect_configuration

        # 生成配置文件
        generate_docker_compose
        generate_synapse_config
        generate_element_config
        generate_nginx_config

        # 部署Matrix服务器
        deploy_matrix_server || exit 1

        # 设置SSL证书
        setup_ssl_certificates || exit 1

        # 验证部署
        verify_deployment

        # 显示访问信息
        show_access_information

        log_success "AIYA Matrix服务器自动部署完成!"
        return 0
    fi

    # 交互式菜单
    while true; do
        show_main_menu
        read -r choice

        case $choice in
            1)
                collect_configuration || true
                ;;
            2)
                if load_configuration; then
                    generate_docker_compose
                    generate_synapse_config
                    generate_element_config
                    generate_nginx_config
                    deploy_matrix_server || continue
                    setup_ssl_certificates || continue
                    verify_deployment
                    show_access_information
                else
                    log_error "请先配置部署参数"
                fi
                read -p "按回车键继续..."
                ;;
            3)
                if load_configuration; then
                    show_configuration_summary
                else
                    log_error "配置文件不存在"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                show_service_status
                read -p "按回车键继续..."
                ;;
            5)
                if load_configuration; then
                    create_admin_user
                else
                    log_error "请先完成部署"
                fi
                read -p "按回车键继续..."
                ;;
            6)
                cleanup_deployment
                read -p "按回车键继续..."
                ;;
            0)
                log_info "退出部署工具"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi