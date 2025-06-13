#!/bin/bash

# IP自动更新系统安装脚本
# 版本: 1.0.0

set -euo pipefail

# 配置变量
INSTALL_DIR="/opt/ip-updater"
SERVICE_NAME="ip-update"
TIMER_NAME="ip-update"
SYSTEMD_DIR="/etc/systemd/system"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    if ! command -v systemctl &> /dev/null; then
        print_error "此系统不支持systemd"
        exit 1
    fi
    
    # 检查dig命令
    if ! command -v dig &> /dev/null; then
        print_info "安装dig命令..."
        if command -v apt &> /dev/null; then
            apt update && apt install -y dnsutils
        elif command -v yum &> /dev/null; then
            yum install -y bind-utils
        else
            print_error "无法安装dig命令，请手动安装"
            exit 1
        fi
    fi
    
    print_success "系统要求检查完成"
}

# 创建目录结构
create_directories() {
    print_info "创建目录结构..."
    
    # 创建主目录
    mkdir -p "$INSTALL_DIR"/{bin,config,templates,backup,logs,scripts,metrics}
    
    # 设置权限
    chmod 755 "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"/{config,backup,logs}
    chmod 755 "$INSTALL_DIR"/{bin,templates,scripts,metrics}
    
    print_success "目录结构创建完成"
}

# 安装脚本文件
install_scripts() {
    print_info "安装脚本文件..."
    
    # 复制主脚本
    if [[ -f "ip-update.sh" ]]; then
        cp "ip-update.sh" "$INSTALL_DIR/bin/"
        chmod 755 "$INSTALL_DIR/bin/ip-update.sh"
    else
        print_error "找不到ip-update.sh文件"
        exit 1
    fi
    
    # 复制配置文件
    if [[ -f "ip-update.conf" ]]; then
        cp "ip-update.conf" "$INSTALL_DIR/config/"
        chmod 644 "$INSTALL_DIR/config/ip-update.conf"
    else
        print_warning "找不到ip-update.conf文件，将创建默认配置"
        create_default_config
    fi
    
    print_success "脚本文件安装完成"
}

# 创建默认配置
create_default_config() {
    cat > "$INSTALL_DIR/config/ip-update.conf" << 'EOF'
# IP自动更新系统配置文件
DDNS_DOMAIN="ip.example.com"
UPDATE_INTERVAL="300"
DNS_SERVERS=("8.8.8.8" "1.1.1.1")
SERVICES_TO_RELOAD=("nginx")
BACKUP_ENABLED="true"
LOG_LEVEL="INFO"
NOTIFICATION_ENABLED="true"
NOTIFICATION_METHODS=("syslog")
EOF
    chmod 644 "$INSTALL_DIR/config/ip-update.conf"
}

# 安装systemd服务
install_systemd_service() {
    print_info "安装systemd服务..."
    
    # 安装服务文件
    if [[ -f "ip-update.service" ]]; then
        cp "ip-update.service" "$SYSTEMD_DIR/"
    else
        create_default_service
    fi
    
    # 安装定时器文件
    if [[ -f "ip-update.timer" ]]; then
        cp "ip-update.timer" "$SYSTEMD_DIR/"
    else
        create_default_timer
    fi
    
    # 重载systemd
    systemctl daemon-reload
    
    print_success "systemd服务安装完成"
}

# 创建默认服务文件
create_default_service() {
    cat > "$SYSTEMD_DIR/ip-update.service" << EOF
[Unit]
Description=IP Address Auto Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=$INSTALL_DIR/bin/ip-update.sh --update
WorkingDirectory=$INSTALL_DIR
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# 创建默认定时器文件
create_default_timer() {
    cat > "$SYSTEMD_DIR/ip-update.timer" << EOF
[Unit]
Description=IP Address Auto Update Timer
Requires=ip-update.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

# 创建配置模板
create_templates() {
    print_info "创建配置模板..."
    
    # Nginx配置模板
    cat > "$INSTALL_DIR/templates/nginx.conf.template" << 'EOF'
# Nginx配置模板
# 公网IP: {{PUBLIC_IP}}

server {
    listen 8080;
    server_name your-domain.com;
    return 301 https://$host:8443$request_uri;
}

server {
    listen 8443 ssl http2;
    server_name your-domain.com;
    
    # 设置公网IP变量
    set $public_ip "{{PUBLIC_IP}}";
    
    # SSL配置
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    
    # ESS配置模板
    cat > "$INSTALL_DIR/templates/ess-values.template" << 'EOF'
# ESS配置模板
# 公网IP: {{PUBLIC_IP}}

serverName: "your-domain.com"

# 公网IP配置
publicIP: "{{PUBLIC_IP}}"
externalIP: "{{PUBLIC_IP}}"

ingress:
  tlsEnabled: false

elementWeb:
  ingress:
    host: "app.your-domain.com"

matrixAuthenticationService:
  ingress:
    host: "mas.your-domain.com"

matrixRTC:
  ingress:
    host: "rtc.your-domain.com"
  sfu:
    config:
      rtc:
        external_ip: "{{PUBLIC_IP}}"

synapse:
  ingress:
    host: "matrix.your-domain.com"
EOF
    
    print_success "配置模板创建完成"
}

# 配置日志轮转
setup_log_rotation() {
    print_info "配置日志轮转..."
    
    cat > "/etc/logrotate.d/ip-updater" << EOF
$INSTALL_DIR/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload-or-restart rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "日志轮转配置完成"
}

# 启用服务
enable_service() {
    print_info "启用IP更新服务..."
    
    # 启用并启动定时器
    systemctl enable "$TIMER_NAME.timer"
    systemctl start "$TIMER_NAME.timer"
    
    # 检查状态
    if systemctl is-active --quiet "$TIMER_NAME.timer"; then
        print_success "IP更新定时器启动成功"
    else
        print_error "IP更新定时器启动失败"
        exit 1
    fi
    
    print_success "服务启用完成"
}

# 运行初始测试
run_initial_test() {
    print_info "运行初始测试..."
    
    # 测试配置
    if "$INSTALL_DIR/bin/ip-update.sh" --check-config; then
        print_success "配置检查通过"
    else
        print_warning "配置检查失败，请检查配置文件"
    fi
    
    # 测试IP获取
    if "$INSTALL_DIR/bin/ip-update.sh" --test; then
        print_success "IP获取测试通过"
    else
        print_warning "IP获取测试失败，请检查网络和DNS配置"
    fi
}

# 显示安装信息
show_installation_info() {
    print_success "=== IP自动更新系统安装完成 ==="
    echo
    print_info "安装目录: $INSTALL_DIR"
    print_info "配置文件: $INSTALL_DIR/config/ip-update.conf"
    print_info "日志文件: $INSTALL_DIR/logs/ip-update.log"
    echo
    print_info "管理命令:"
    echo "  查看状态: systemctl status $TIMER_NAME.timer"
    echo "  启动服务: systemctl start $TIMER_NAME.timer"
    echo "  停止服务: systemctl stop $TIMER_NAME.timer"
    echo "  重启服务: systemctl restart $TIMER_NAME.timer"
    echo "  查看日志: journalctl -u $SERVICE_NAME.service -f"
    echo
    print_info "手动执行:"
    echo "  检查配置: $INSTALL_DIR/bin/ip-update.sh --check-config"
    echo "  测试运行: $INSTALL_DIR/bin/ip-update.sh --test"
    echo "  立即更新: $INSTALL_DIR/bin/ip-update.sh --update"
    echo
    print_warning "重要提醒:"
    echo "1. 请编辑配置文件 $INSTALL_DIR/config/ip-update.conf"
    echo "2. 设置正确的DDNS_DOMAIN域名"
    echo "3. 配置需要重载的服务列表"
    echo "4. 重启定时器: systemctl restart $TIMER_NAME.timer"
    echo
    print_info "下一步操作:"
    echo "1. nano $INSTALL_DIR/config/ip-update.conf"
    echo "2. systemctl restart $TIMER_NAME.timer"
    echo "3. systemctl status $TIMER_NAME.timer"
}

# 清理函数
cleanup() {
    if [[ $? -ne 0 ]]; then
        print_error "安装过程中发生错误"
        print_info "清理安装文件..."
        
        # 停止并禁用服务
        systemctl stop "$TIMER_NAME.timer" 2>/dev/null || true
        systemctl disable "$TIMER_NAME.timer" 2>/dev/null || true
        
        # 删除systemd文件
        rm -f "$SYSTEMD_DIR/$SERVICE_NAME.service"
        rm -f "$SYSTEMD_DIR/$TIMER_NAME.timer"
        
        # 重载systemd
        systemctl daemon-reload
        
        print_info "清理完成"
    fi
}

# 主函数
main() {
    print_info "开始安装IP自动更新系统..."
    
    # 设置错误处理
    trap cleanup EXIT
    
    check_root
    check_requirements
    create_directories
    install_scripts
    install_systemd_service
    create_templates
    setup_log_rotation
    enable_service
    run_initial_test
    show_installation_info
    
    # 取消错误处理
    trap - EXIT
    
    print_success "IP自动更新系统安装完成!"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
