#!/bin/bash

# ESS配置检查脚本
# 用于验证配置是否正确设置

set -euo pipefail

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

# 显示横幅
show_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    ESS配置检查工具                                ║
║                                                                  ║
║  检查ESS部署所需的配置是否正确设置                                 ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 加载配置
load_config() {
    print_info "加载配置..."
    
    # 加载配置文件
    if [[ -f "ess-config-template.env" ]]; then
        print_info "发现配置文件: ess-config-template.env"
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
    
    # 设置默认值
    DOMAIN="${DOMAIN:-your-domain.com}"
    HTTP_PORT="${HTTP_PORT:-8080}"
    HTTPS_PORT="${HTTPS_PORT:-8443}"
    FEDERATION_PORT="${FEDERATION_PORT:-8448}"
    CERT_EMAIL="${CERT_EMAIL:-admin@your-domain.com}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@your-domain.com}"
    DDNS_DOMAIN="${DDNS_DOMAIN:-ip.your-domain.com}"
    ALERT_EMAIL="${ALERT_EMAIL:-alerts@your-domain.com}"
}

# 检查域名配置
check_domain() {
    print_info "检查域名配置..."
    
    local errors=0
    
    # 检查主域名
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        print_error "主域名未设置: $DOMAIN"
        print_info "请设置: DOMAIN=\"matrix.example.com\""
        ((errors++))
    elif [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        print_error "域名格式无效: $DOMAIN"
        ((errors++))
    else
        print_success "主域名: $DOMAIN"
    fi
    
    # 检查邮箱配置
    if [[ "$CERT_EMAIL" == "admin@your-domain.com" ]]; then
        print_warning "证书邮箱使用默认值: $CERT_EMAIL"
        print_info "建议设置: CERT_EMAIL=\"admin@$DOMAIN\""
    else
        print_success "证书邮箱: $CERT_EMAIL"
    fi
    
    if [[ "$ADMIN_EMAIL" == "admin@your-domain.com" ]]; then
        print_warning "管理员邮箱使用默认值: $ADMIN_EMAIL"
    else
        print_success "管理员邮箱: $ADMIN_EMAIL"
    fi
    
    # 检查DDNS域名
    if [[ "$DDNS_DOMAIN" == "ip.your-domain.com" ]]; then
        print_warning "DDNS域名使用默认值: $DDNS_DOMAIN"
        print_info "如果使用IP自动更新，请设置: DDNS_DOMAIN=\"ip.$DOMAIN\""
    else
        print_success "DDNS域名: $DDNS_DOMAIN"
    fi
    
    return $errors
}

# 检查端口配置
check_ports() {
    print_info "检查端口配置..."
    
    print_success "HTTP端口: $HTTP_PORT"
    print_success "HTTPS端口: $HTTPS_PORT"
    print_success "联邦端口: $FEDERATION_PORT"
    
    # 检查端口冲突
    if [[ "$HTTP_PORT" == "$HTTPS_PORT" ]]; then
        print_error "HTTP和HTTPS端口不能相同"
        return 1
    fi
    
    return 0
}

# 检查DNS解析
check_dns() {
    print_info "检查DNS解析..."
    
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        print_warning "跳过DNS检查 - 域名未设置"
        return 0
    fi
    
    local domains=("$DOMAIN" "app.$DOMAIN" "mas.$DOMAIN" "rtc.$DOMAIN" "matrix.$DOMAIN")
    local dns_errors=0
    
    for domain in "${domains[@]}"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            print_success "DNS解析正常: $domain"
        else
            print_warning "DNS解析失败: $domain"
            ((dns_errors++))
        fi
    done
    
    if [[ $dns_errors -gt 0 ]]; then
        print_warning "发现 $dns_errors 个域名DNS解析问题"
        print_info "请确保所有子域名都正确解析到服务器IP"
    fi
    
    return 0
}

# 生成配置建议
generate_suggestions() {
    print_info "生成配置建议..."
    
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        echo
        print_info "快速配置示例 (请替换为您的实际域名):"
        echo
        echo "export DOMAIN=\"matrix.example.com\""
        echo "export CERT_EMAIL=\"admin@matrix.example.com\""
        echo "export ADMIN_EMAIL=\"admin@matrix.example.com\""
        echo "export DDNS_DOMAIN=\"ip.matrix.example.com\""
        echo "export ALERT_EMAIL=\"alerts@matrix.example.com\""
        echo
        print_info "然后运行部署:"
        echo "./deploy-ess-nginx-proxy.sh"
        echo
        print_info "或者使用curl一键部署:"
        echo "DOMAIN=\"matrix.example.com\" AUTO_DEPLOY=3 bash <(curl -fsSL ...)"
    else
        echo
        print_success "配置看起来不错！您可以开始部署了:"
        echo "./deploy-ess-nginx-proxy.sh"
    fi
}

# 主函数
main() {
    show_banner
    
    load_config
    
    local total_errors=0
    
    # 执行各项检查
    if ! check_domain; then
        ((total_errors++))
    fi
    
    if ! check_ports; then
        ((total_errors++))
    fi
    
    check_dns
    
    echo
    print_info "配置检查完成"
    
    if [[ $total_errors -eq 0 ]]; then
        print_success "所有关键配置检查通过！"
    else
        print_error "发现 $total_errors 个配置问题，请修复后重试"
    fi
    
    generate_suggestions
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
