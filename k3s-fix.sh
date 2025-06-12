#!/bin/bash

# K3s问题诊断和修复脚本
# 用于解决K3s服务启动失败的问题

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

print_info() {
    echo -e "${WHITE}[信息]${NC} $1"
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
    echo
    echo -e "${GREEN}=== $1 ===${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 诊断K3s问题
diagnose_k3s() {
    print_step "诊断K3s问题"
    
    print_info "检查K3s服务状态..."
    systemctl status k3s.service --no-pager || true
    
    echo
    print_info "检查K3s服务日志..."
    journalctl -u k3s.service --no-pager -n 50 || true
    
    echo
    print_info "检查系统资源..."
    echo "内存使用情况:"
    free -h
    echo
    echo "磁盘使用情况:"
    df -h
    echo
    echo "网络接口:"
    ip addr show
    
    echo
    print_info "检查端口占用..."
    netstat -tuln | grep -E ':(6443|10250|10251|10252)' || echo "K3s相关端口未被占用"
}

# 完全清理K3s
cleanup_k3s() {
    print_step "完全清理K3s"
    
    print_info "停止K3s服务..."
    systemctl stop k3s || true
    systemctl disable k3s || true
    
    print_info "运行官方卸载脚本..."
    if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
        /usr/local/bin/k3s-uninstall.sh || true
    fi
    
    print_info "手动清理残留文件..."
    rm -rf /var/lib/rancher/k3s || true
    rm -rf /etc/rancher/k3s || true
    rm -f /usr/local/bin/k3s* || true
    rm -f /usr/local/bin/kubectl || true
    rm -f /usr/local/bin/crictl || true
    rm -f /usr/local/bin/ctr || true
    rm -f /etc/systemd/system/k3s.service* || true
    
    print_info "重新加载systemd..."
    systemctl daemon-reload
    
    print_info "清理网络接口..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    print_success "K3s清理完成"
}

# 重新安装K3s
reinstall_k3s() {
    print_step "重新安装K3s"
    
    # 获取公网IP
    print_info "获取公网IP..."
    local public_ip=""
    public_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "")
    
    if [[ -z "$public_ip" ]]; then
        print_warning "无法获取公网IP，使用本地IP"
        public_ip=$(hostname -I | awk '{print $1}')
    fi
    
    print_info "使用IP: $public_ip"
    
    # 设置K3s安装参数（简化版本，避免复杂配置）
    export INSTALL_K3S_VERSION="v1.32.5+k3s1"
    export INSTALL_K3S_EXEC="--write-kubeconfig-mode=644"
    
    print_info "下载并安装K3s..."
    curl -sfL https://get.k3s.io | sh -
    
    # 等待服务启动
    print_info "等待K3s服务启动..."
    local retry_count=0
    while ! systemctl is-active --quiet k3s; do
        if [ $retry_count -ge 60 ]; then
            print_error "K3s服务启动超时"
            return 1
        fi
        print_info "等待中... ($((retry_count + 1))/60)"
        sleep 5
        ((retry_count++))
    done
    
    # 验证安装
    print_info "验证K3s安装..."
    sleep 10
    
    if k3s kubectl get nodes; then
        print_success "K3s安装成功！"
        k3s kubectl get nodes
    else
        print_error "K3s验证失败"
        return 1
    fi
}

# 主菜单
show_menu() {
    echo
    echo -e "${WHITE}K3s问题诊断和修复工具${NC}"
    echo -e "${WHITE}请选择操作:${NC}"
    echo -e "  ${GREEN}1)${NC} 诊断K3s问题"
    echo -e "  ${GREEN}2)${NC} 完全清理K3s"
    echo -e "  ${GREEN}3)${NC} 重新安装K3s"
    echo -e "  ${GREEN}4)${NC} 清理并重新安装"
    echo -e "  ${RED}0)${NC} 退出"
    echo
}

# 主程序
main() {
    check_root
    
    while true; do
        show_menu
        read -p "请选择操作 (0-4): " choice
        
        case $choice in
            1)
                diagnose_k3s
                read -p "按回车键继续..."
                ;;
            2)
                cleanup_k3s
                read -p "按回车键继续..."
                ;;
            3)
                reinstall_k3s
                read -p "按回车键继续..."
                ;;
            4)
                cleanup_k3s
                echo
                reinstall_k3s
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "\n${GREEN}退出${NC}\n"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 0-4"
                sleep 2
                ;;
        esac
    done
}

main "$@"
