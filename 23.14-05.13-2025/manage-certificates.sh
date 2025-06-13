#!/bin/bash

# SSL证书管理脚本

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 列出所有证书
list_certificates() {
    print_info "=== 已安装的证书 ==="
    
    if command -v certbot &>/dev/null; then
        certbot certificates
    else
        print_error "certbot未安装"
        return 1
    fi
}

# 查看证书详情
show_certificate_details() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        read -p "请输入域名: " domain
    fi
    
    print_info "=== 证书详情: $domain ==="
    
    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    
    if [[ -f "$cert_path" ]]; then
        # 证书基本信息
        print_info "证书路径: $cert_path"
        
        # 有效期
        local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        local expiry_timestamp=$(date -d "$expiry_date" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
        
        print_info "有效期: $expiry_date"
        print_info "剩余天数: $days_until_expiry 天"
        
        # 域名列表
        print_info "包含的域名:"
        openssl x509 -in "$cert_path" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep DNS | cut -d: -f2 | sed 's/^ */  - /'
        
        # 颁发者
        local issuer=$(openssl x509 -in "$cert_path" -noout -issuer | cut -d= -f2-)
        print_info "颁发者: $issuer"
        
        # 证书类型判断
        if echo "$issuer" | grep -q "Fake LE"; then
            print_warning "这是Let's Encrypt Staging证书 (测试证书)"
        elif echo "$issuer" | grep -q "Let's Encrypt"; then
            print_success "这是Let's Encrypt生产证书"
        else
            print_info "这是自定义证书"
        fi
        
    else
        print_error "证书文件不存在: $cert_path"
        return 1
    fi
}

# 续期证书
renew_certificate() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        read -p "请输入要续期的域名: " domain
    fi
    
    print_info "续期证书: $domain"
    
    if certbot renew --cert-name "$domain" --force-renewal; then
        print_success "证书续期成功"
        
        # 重启相关服务
        print_info "重启相关服务..."
        systemctl reload nginx 2>/dev/null || true
        
    else
        print_error "证书续期失败"
        return 1
    fi
}

# 撤销证书
revoke_certificate() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        read -p "请输入要撤销的域名: " domain
    fi
    
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [[ ! -f "$cert_path" ]]; then
        print_error "证书文件不存在: $cert_path"
        return 1
    fi
    
    print_warning "即将撤销证书: $domain"
    print_warning "撤销后证书将立即失效，无法恢复！"
    
    read -p "确定要撤销证书吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "取消撤销"
        return 0
    fi
    
    print_info "撤销证书: $domain"
    
    if certbot revoke --cert-path "$cert_path"; then
        print_success "证书撤销成功"
        
        # 删除证书文件
        print_info "删除证书文件..."
        certbot delete --cert-name "$domain"
        
    else
        print_error "证书撤销失败"
        return 1
    fi
}

# 删除证书 (不撤销)
delete_certificate() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        read -p "请输入要删除的域名: " domain
    fi
    
    print_warning "即将删除证书: $domain"
    print_warning "这只会删除本地文件，不会撤销证书"
    print_info "如果要撤销证书，请使用 revoke 选项"
    
    read -p "确定要删除证书吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "取消删除"
        return 0
    fi
    
    if certbot delete --cert-name "$domain"; then
        print_success "证书删除成功"
    else
        print_error "证书删除失败"
        return 1
    fi
}

# 检查证书状态
check_certificate_status() {
    print_info "=== 证书状态检查 ==="
    
    # 检查即将过期的证书
    print_info "检查即将过期的证书..."
    
    local expiring_certs=()
    
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [[ -d "$cert_dir" ]]; then
            local domain=$(basename "$cert_dir")
            local cert_path="$cert_dir/fullchain.pem"
            
            if [[ -f "$cert_path" ]]; then
                local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
                local expiry_timestamp=$(date -d "$expiry_date" +%s)
                local current_timestamp=$(date +%s)
                local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                
                if [[ $days_until_expiry -lt 30 ]]; then
                    expiring_certs+=("$domain ($days_until_expiry 天)")
                fi
            fi
        fi
    done
    
    if [[ ${#expiring_certs[@]} -gt 0 ]]; then
        print_warning "以下证书将在30天内过期:"
        for cert in "${expiring_certs[@]}"; do
            echo "  - $cert"
        done
    else
        print_success "所有证书都在有效期内"
    fi
    
    # 测试自动续期
    print_info "测试自动续期..."
    if certbot renew --dry-run; then
        print_success "自动续期测试通过"
    else
        print_warning "自动续期测试失败"
    fi
}

# 显示帮助
show_help() {
    echo "SSL证书管理脚本"
    echo
    echo "用法:"
    echo "  $0 list                    # 列出所有证书"
    echo "  $0 show [domain]           # 查看证书详情"
    echo "  $0 renew [domain]          # 续期证书"
    echo "  $0 revoke [domain]         # 撤销证书"
    echo "  $0 delete [domain]         # 删除证书 (不撤销)"
    echo "  $0 status                  # 检查证书状态"
    echo "  $0 help                    # 显示帮助"
    echo
    echo "示例:"
    echo "  $0 show niub.win           # 查看niub.win的证书详情"
    echo "  $0 renew niub.win          # 续期niub.win的证书"
    echo "  $0 revoke niub.win         # 撤销niub.win的证书"
    echo
}

# 主函数
main() {
    check_root
    
    case "${1:-}" in
        "list")
            list_certificates
            ;;
        "show")
            show_certificate_details "${2:-}"
            ;;
        "renew")
            renew_certificate "${2:-}"
            ;;
        "revoke")
            revoke_certificate "${2:-}"
            ;;
        "delete")
            delete_certificate "${2:-}"
            ;;
        "status")
            check_certificate_status
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
