#!/bin/bash

# K3s问题诊断和修复脚本

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

# 诊断K3s状态
diagnose_k3s() {
    print_info "=== K3s状态诊断 ==="
    
    # 检查K3s服务状态
    print_info "1. 检查K3s服务状态:"
    if systemctl is-active --quiet k3s; then
        print_success "K3s服务正在运行"
        systemctl status k3s --no-pager
    else
        print_error "K3s服务未运行"
        systemctl status k3s --no-pager || true
    fi
    
    # 检查K3s进程
    print_info "2. 检查K3s进程:"
    ps aux | grep k3s | grep -v grep || print_warning "未找到K3s进程"
    
    # 检查端口占用
    print_info "3. 检查K3s端口:"
    netstat -tlnp | grep :6443 || print_warning "6443端口未监听"
    netstat -tlnp | grep :10250 || print_warning "10250端口未监听"
    
    # 检查kubeconfig文件
    print_info "4. 检查kubeconfig文件:"
    if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
        print_success "K3s kubeconfig存在"
        ls -la /etc/rancher/k3s/k3s.yaml
    else
        print_error "K3s kubeconfig不存在"
    fi
    
    if [[ -f "$HOME/.kube/config" ]]; then
        print_success "用户kubeconfig存在"
        ls -la "$HOME/.kube/config"
    else
        print_warning "用户kubeconfig不存在"
    fi
    
    # 检查环境变量
    print_info "5. 检查环境变量:"
    echo "KUBECONFIG: ${KUBECONFIG:-未设置}"
    
    # 测试kubectl连接
    print_info "6. 测试kubectl连接:"
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    if kubectl get nodes 2>/dev/null; then
        print_success "kubectl连接正常"
    else
        print_error "kubectl连接失败"
        kubectl get nodes || true
    fi
}

# 修复K3s
fix_k3s() {
    print_info "=== 修复K3s ==="
    
    # 停止K3s服务
    print_info "1. 停止K3s服务..."
    systemctl stop k3s || true
    
    # 清理旧的配置
    print_info "2. 清理旧配置..."
    rm -rf /var/lib/rancher/k3s/server/db
    rm -rf /var/lib/rancher/k3s/server/tls
    
    # 重新启动K3s
    print_info "3. 重新启动K3s..."
    systemctl start k3s
    
    # 等待服务启动
    print_info "4. 等待K3s启动..."
    local retry_count=0
    while ! systemctl is-active --quiet k3s && [[ $retry_count -lt 30 ]]; do
        sleep 2
        ((retry_count++))
        print_info "等待K3s启动... ($retry_count/30)"
    done
    
    if ! systemctl is-active --quiet k3s; then
        print_error "K3s启动失败"
        systemctl status k3s --no-pager
        return 1
    fi
    
    # 等待API服务器就绪
    print_info "5. 等待API服务器就绪..."
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    local api_retry=0
    while ! kubectl get nodes &>/dev/null && [[ $api_retry -lt 30 ]]; do
        sleep 3
        ((api_retry++))
        print_info "等待API服务器... ($api_retry/30)"
    done
    
    if ! kubectl get nodes &>/dev/null; then
        print_error "API服务器未就绪"
        return 1
    fi
    
    print_success "K3s修复完成"
}

# 配置kubectl
configure_kubectl() {
    print_info "=== 配置kubectl ==="
    
    # 创建.kube目录
    mkdir -p "$HOME/.kube"
    
    # 复制kubeconfig
    if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
        cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
        chmod 600 "$HOME/.kube/config"
        print_success "kubeconfig已复制到用户目录"
    else
        print_error "K3s kubeconfig不存在"
        return 1
    fi
    
    # 设置环境变量
    export KUBECONFIG="$HOME/.kube/config"
    
    # 测试连接
    if kubectl get nodes; then
        print_success "kubectl配置成功"
    else
        print_error "kubectl配置失败"
        return 1
    fi
}

# 验证集群
verify_cluster() {
    print_info "=== 验证集群 ==="
    
    export KUBECONFIG="$HOME/.kube/config"
    
    # 检查节点
    print_info "集群节点:"
    kubectl get nodes -o wide
    
    # 检查系统Pod
    print_info "系统Pod状态:"
    kubectl get pods -n kube-system
    
    # 检查命名空间
    print_info "命名空间:"
    kubectl get namespaces
    
    # 等待所有系统Pod就绪
    print_info "等待系统Pod就绪..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
    
    print_success "集群验证完成"
}

# 重新安装K3s
reinstall_k3s() {
    print_info "=== 重新安装K3s ==="
    
    # 卸载K3s
    print_info "1. 卸载现有K3s..."
    if [[ -f "/usr/local/bin/k3s-uninstall.sh" ]]; then
        /usr/local/bin/k3s-uninstall.sh || true
    fi
    
    # 清理残留文件
    print_info "2. 清理残留文件..."
    rm -rf /var/lib/rancher/k3s
    rm -rf /etc/rancher/k3s
    rm -rf "$HOME/.kube"
    
    # 重新安装
    print_info "3. 重新安装K3s..."
    curl -sfL https://get.k3s.io | sh -
    
    # 等待启动
    print_info "4. 等待K3s启动..."
    sleep 30
    
    # 配置kubectl
    configure_kubectl
    
    # 验证集群
    verify_cluster
}

# 主菜单
main_menu() {
    while true; do
        echo
        print_info "=== K3s诊断和修复工具 ==="
        echo "1) 诊断K3s状态"
        echo "2) 修复K3s"
        echo "3) 配置kubectl"
        echo "4) 验证集群"
        echo "5) 重新安装K3s"
        echo "0) 退出"
        echo
        read -p "请选择操作 [0-5]: " choice
        
        case "$choice" in
            "1")
                diagnose_k3s
                ;;
            "2")
                fix_k3s
                ;;
            "3")
                configure_kubectl
                ;;
            "4")
                verify_cluster
                ;;
            "5")
                read -p "确定要重新安装K3s吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    reinstall_k3s
                fi
                ;;
            "0")
                print_info "退出"
                exit 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
    done
}

# 自动修复模式
auto_fix() {
    print_info "=== 自动修复模式 ==="
    
    # 先诊断
    diagnose_k3s
    
    # 尝试修复
    if ! fix_k3s; then
        print_warning "修复失败，尝试重新安装..."
        reinstall_k3s
    fi
    
    # 配置kubectl
    configure_kubectl
    
    # 验证集群
    verify_cluster
    
    print_success "自动修复完成"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    
    if [[ "${1:-}" == "auto" ]]; then
        auto_fix
    else
        main_menu
    fi
fi
