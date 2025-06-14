#!/bin/bash

# ESS-Helm部署清理脚本
# 用于清理之前的部署，准备重新安装

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

# 显示清理选项
show_cleanup_options() {
    echo
    print_info "=== ESS部署清理工具 ==="
    echo "选择要清理的组件:"
    echo
    echo "1) 清理ESS Helm部署"
    echo "2) 清理K3s集群"
    echo "3) 清理Nginx配置"
    echo "4) 清理SSL证书"
    echo "5) 清理systemd服务"
    echo "6) 清理安装目录"
    echo "7) 清理配置文件"
    echo "8) 清理临时文件"
    echo "9) 完全清理 (所有组件)"
    echo "0) 退出"
    echo
}

# 清理ESS Helm部署
cleanup_ess() {
    print_info "清理ESS Helm部署..."
    
    # 设置kubeconfig
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    
    if kubectl get nodes &>/dev/null; then
        # 删除ESS部署
        if helm list -n ess | grep -q ess; then
            print_info "删除ESS Helm部署..."
            helm uninstall ess -n ess || true
        fi
        
        # 删除命名空间
        if kubectl get namespace ess &>/dev/null; then
            print_info "删除ESS命名空间..."
            kubectl delete namespace ess --timeout=60s || true
        fi
        
        # 清理PVC (如果存在)
        print_info "清理持久卷声明..."
        kubectl get pvc -A | grep ess | awk '{print $1 " " $2}' | while read ns pvc; do
            kubectl delete pvc "$pvc" -n "$ns" || true
        done
        
        print_success "ESS Helm部署清理完成"
    else
        print_warning "无法连接到K3s集群，跳过ESS清理"
    fi
}

# 清理K3s集群
cleanup_k3s() {
    print_info "清理K3s集群..."
    
    # 停止K3s服务
    print_info "停止K3s服务..."
    systemctl stop k3s || true
    systemctl disable k3s || true
    
    # 运行K3s卸载脚本
    if [[ -f "/usr/local/bin/k3s-uninstall.sh" ]]; then
        print_info "运行K3s卸载脚本..."
        /usr/local/bin/k3s-uninstall.sh || true
    fi
    
    # 清理K3s文件和目录
    print_info "清理K3s文件..."
    rm -rf /var/lib/rancher/k3s
    rm -rf /etc/rancher/k3s
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/cni
    rm -rf /opt/cni
    rm -rf /run/k3s
    
    # 清理kubectl配置
    rm -rf ~/.kube
    
    # 清理网络接口
    print_info "清理网络接口..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    # 清理iptables规则
    print_info "清理iptables规则..."
    iptables -F || true
    iptables -X || true
    iptables -t nat -F || true
    iptables -t nat -X || true
    
    print_success "K3s集群清理完成"
}

# 清理Nginx配置
cleanup_nginx() {
    print_info "清理Nginx配置..."
    
    # 停止Nginx
    systemctl stop nginx || true
    
    # 删除ESS相关配置
    rm -f /etc/nginx/sites-available/matrix-ess
    rm -f /etc/nginx/sites-enabled/matrix-ess
    
    # 恢复默认站点
    if [[ -f "/etc/nginx/sites-available/default" ]]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    fi
    
    # 测试配置
    nginx -t && systemctl start nginx || print_warning "Nginx配置测试失败"
    
    print_success "Nginx配置清理完成"
}

# 清理SSL证书
cleanup_ssl() {
    print_info "清理SSL证书..."
    
    # 获取域名
    local domain="${DOMAIN:-}"
    if [[ -z "$domain" ]]; then
        read -p "请输入要清理证书的域名: " domain
    fi
    
    if [[ -n "$domain" && "$domain" != "your-domain.com" ]]; then
        # 删除Let's Encrypt证书
        if certbot certificates | grep -q "$domain"; then
            print_info "删除Let's Encrypt证书: $domain"
            certbot delete --cert-name "$domain" || true
        fi
        
        # 清理证书目录
        rm -rf "/etc/letsencrypt/live/$domain"
        rm -rf "/etc/letsencrypt/archive/$domain"
        rm -rf "/etc/letsencrypt/renewal/$domain.conf"
    fi
    
    # 清理DNS验证凭据
    rm -f /etc/letsencrypt/cloudflare.ini
    rm -f /etc/letsencrypt/route53.ini
    rm -f /etc/letsencrypt/digitalocean.ini
    
    print_success "SSL证书清理完成"
}

# 清理安装目录
cleanup_install_dir() {
    print_info "清理安装目录..."

    local install_dir="${INSTALL_DIR:-/opt/matrix-ess}"

    # 清理主安装目录
    if [[ -d "$install_dir" ]]; then
        rm -rf "$install_dir"
        print_success "安装目录清理完成: $install_dir"
    else
        print_info "安装目录不存在: $install_dir"
    fi

    # 清理IP更新系统目录
    if [[ -d "/opt/ip-updater" ]]; then
        print_info "清理IP更新系统目录..."
        rm -rf "/opt/ip-updater"
        print_success "IP更新系统目录清理完成"
    fi

    # 清理数据目录
    local data_dirs=(
        "/var/lib/matrix-ess"
        "/var/log/matrix-ess"
        "/var/backups/matrix-ess"
    )

    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            print_info "清理数据目录: $dir"
            rm -rf "$dir"
        fi
    done
}

# 清理systemd服务
cleanup_systemd_services() {
    print_info "清理systemd服务..."

    # 停止并禁用IP更新服务
    systemctl stop ip-update.timer 2>/dev/null || true
    systemctl stop ip-update.service 2>/dev/null || true
    systemctl disable ip-update.timer 2>/dev/null || true
    systemctl disable ip-update.service 2>/dev/null || true

    # 删除服务文件
    rm -f /etc/systemd/system/ip-update.service
    rm -f /etc/systemd/system/ip-update.timer

    # 重载systemd
    systemctl daemon-reload

    print_success "systemd服务清理完成"
}

# 清理配置文件
cleanup_config_files() {
    print_info "清理配置文件..."

    # 清理当前目录的配置文件
    rm -f ess-config-template.env
    rm -f ess-values.yaml
    rm -f nginx.conf.template

    # 清理生成的配置备份文件
    rm -f "$INSTALL_DIR"/*-backup.yaml 2>/dev/null || true
    rm -f "$INSTALL_DIR"/*.yaml 2>/dev/null || true
    rm -f "$INSTALL_DIR"/*.json 2>/dev/null || true

    print_success "配置文件清理完成"
}

# 清理临时文件
cleanup_temp_files() {
    print_info "清理临时文件..."

    # 清理setup.sh创建的临时目录
    rm -rf /tmp/ess-installer-* 2>/dev/null || true

    # 清理下载的文件目录
    rm -rf "$HOME"/ess-installer-* 2>/dev/null || true

    # 清理其他临时文件
    rm -f /tmp/matrix-*.log 2>/dev/null || true
    rm -f /tmp/ess-*.log 2>/dev/null || true

    print_success "临时文件清理完成"
}

# 完全清理
cleanup_all() {
    print_warning "执行完全清理..."
    print_warning "这将删除所有ESS相关组件和数据！"
    
    read -p "确定要继续吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "取消清理"
        return
    fi
    
    cleanup_ess
    cleanup_k3s
    cleanup_nginx
    cleanup_ssl
    cleanup_systemd_services
    cleanup_install_dir
    cleanup_config_files
    cleanup_temp_files

    print_success "完全清理完成"
}

# 快速清理 (保留证书和配置)
quick_cleanup() {
    print_info "执行快速清理 (保留证书和配置)..."
    
    cleanup_ess
    cleanup_k3s
    cleanup_nginx
    
    print_success "快速清理完成"
}

# 主菜单
main_menu() {
    while true; do
        show_cleanup_options
        read -p "请选择 [0-9]: " choice

        case "$choice" in
            "1")
                cleanup_ess
                ;;
            "2")
                cleanup_k3s
                ;;
            "3")
                cleanup_nginx
                ;;
            "4")
                cleanup_ssl
                ;;
            "5")
                cleanup_systemd_services
                ;;
            "6")
                cleanup_install_dir
                ;;
            "7")
                cleanup_config_files
                ;;
            "8")
                cleanup_temp_files
                ;;
            "9")
                cleanup_all
                ;;
            "0")
                print_info "退出清理工具"
                exit 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 显示使用帮助
show_help() {
    echo "ESS部署清理脚本"
    echo
    echo "用法:"
    echo "  $0                    # 交互式菜单"
    echo "  $0 quick             # 快速清理 (保留证书)"
    echo "  $0 all               # 完全清理"
    echo "  $0 ess               # 仅清理ESS部署"
    echo "  $0 k3s               # 仅清理K3s"
    echo "  $0 nginx             # 仅清理Nginx"
    echo "  $0 ssl               # 仅清理SSL证书"
    echo "  $0 config            # 仅清理配置文件"
    echo
    echo "环境变量:"
    echo "  DOMAIN=your-domain.com    # 指定要清理的域名"
    echo
}

# 脚本入口
main() {
    check_root
    
    case "${1:-}" in
        "quick")
            quick_cleanup
            ;;
        "all")
            cleanup_all
            ;;
        "ess")
            cleanup_ess
            ;;
        "k3s")
            cleanup_k3s
            ;;
        "nginx")
            cleanup_nginx
            ;;
        "ssl")
            cleanup_ssl
            ;;
        "config")
            cleanup_config_files
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            main_menu
            ;;
        *)
            print_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
