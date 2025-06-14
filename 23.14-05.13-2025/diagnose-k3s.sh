#!/bin/bash

# K3s诊断脚本
# 用于排查K3s安装和运行问题

set -euo pipefail

# 颜色定义
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

# 检查K3s服务状态
check_k3s_service() {
    print_info "=== K3s服务状态检查 ==="
    
    if systemctl is-active --quiet k3s; then
        print_success "K3s服务运行正常"
        systemctl status k3s --no-pager
    else
        print_error "K3s服务未运行"
        print_info "K3s服务状态:"
        systemctl status k3s --no-pager || true
        
        print_info "K3s服务日志 (最近50行):"
        journalctl -u k3s -n 50 --no-pager || true
    fi
}

# 检查kubeconfig
check_kubeconfig() {
    print_info "=== kubeconfig检查 ==="
    
    local kubeconfig_file="/etc/rancher/k3s/k3s.yaml"
    
    if [[ -f "$kubeconfig_file" ]]; then
        print_success "kubeconfig文件存在: $kubeconfig_file"
        ls -la "$kubeconfig_file"
        
        # 设置KUBECONFIG
        export KUBECONFIG="$kubeconfig_file"
        
        # 测试kubectl连接
        if kubectl get nodes &>/dev/null; then
            print_success "kubectl连接正常"
            kubectl get nodes
        else
            print_error "kubectl连接失败"
            print_info "尝试连接测试..."
            kubectl get nodes || true
        fi
    else
        print_error "kubeconfig文件不存在: $kubeconfig_file"
        print_info "检查K3s数据目录:"
        ls -la /etc/rancher/k3s/ || true
    fi
}

# 检查系统Pod
check_system_pods() {
    print_info "=== 系统Pod检查 ==="
    
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    
    if kubectl get nodes &>/dev/null; then
        print_info "kube-system命名空间Pod状态:"
        kubectl get pods -n kube-system -o wide || true
        
        print_info "所有命名空间Pod状态:"
        kubectl get pods --all-namespaces || true
        
        # 检查有问题的Pod
        print_info "检查非Running状态的Pod:"
        kubectl get pods --all-namespaces --field-selector=status.phase!=Running || true
        
        # 检查事件
        print_info "最近的集群事件:"
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20 || true
        
    else
        print_error "无法连接到K3s集群"
    fi
}

# 检查网络配置
check_network() {
    print_info "=== 网络配置检查 ==="
    
    # 检查网络接口
    print_info "网络接口:"
    ip addr show | grep -E "^[0-9]+:|inet " || true
    
    # 检查路由
    print_info "路由表:"
    ip route show || true
    
    # 检查DNS
    print_info "DNS配置:"
    cat /etc/resolv.conf || true
    
    # 检查K3s网络接口
    print_info "K3s网络接口:"
    ip addr show | grep -E "cni0|flannel" || print_info "未发现K3s网络接口"
}

# 检查资源使用
check_resources() {
    print_info "=== 系统资源检查 ==="
    
    # 检查内存
    print_info "内存使用:"
    free -h
    
    # 检查磁盘空间
    print_info "磁盘空间:"
    df -h
    
    # 检查CPU负载
    print_info "CPU负载:"
    uptime
    
    # 检查进程
    print_info "K3s相关进程:"
    ps aux | grep -E "k3s|containerd" | grep -v grep || true
}

# 检查容器运行时
check_container_runtime() {
    print_info "=== 容器运行时检查 ==="
    
    # 检查containerd
    if command -v ctr >/dev/null 2>&1; then
        print_success "containerd可用"
        
        print_info "containerd命名空间:"
        ctr namespace list || true
        
        print_info "K3s容器:"
        ctr -n k8s.io container list || true
        
    else
        print_warning "ctr命令不可用"
    fi
    
    # 检查crictl
    if command -v crictl >/dev/null 2>&1; then
        print_success "crictl可用"
        
        print_info "容器运行时信息:"
        crictl info || true
        
        print_info "运行中的容器:"
        crictl ps || true
        
        print_info "Pod列表:"
        crictl pods || true
        
    else
        print_warning "crictl命令不可用"
    fi
}

# 检查K3s配置
check_k3s_config() {
    print_info "=== K3s配置检查 ==="
    
    # 检查K3s配置目录
    print_info "K3s配置目录:"
    ls -la /etc/rancher/k3s/ || true
    
    # 检查K3s数据目录
    print_info "K3s数据目录:"
    ls -la /var/lib/rancher/k3s/ || true
    
    # 检查K3s manifests
    print_info "K3s manifests:"
    ls -la /var/lib/rancher/k3s/server/manifests/ || true
    
    # 检查Traefik配置
    if [[ -f "/var/lib/rancher/k3s/server/manifests/traefik-config.yaml" ]]; then
        print_info "Traefik配置:"
        cat /var/lib/rancher/k3s/server/manifests/traefik-config.yaml || true
    fi
}

# 尝试修复K3s
try_fix_k3s() {
    print_info "=== 尝试修复K3s ==="
    
    read -p "是否尝试重启K3s服务? [y/N]: " restart_k3s
    if [[ "$restart_k3s" =~ ^[Yy]$ ]]; then
        print_info "重启K3s服务..."
        systemctl restart k3s || true
        
        print_info "等待K3s启动..."
        sleep 30
        
        # 重新检查
        check_k3s_service
        check_kubeconfig
    fi
    
    read -p "是否尝试重新安装K3s? [y/N]: " reinstall_k3s
    if [[ "$reinstall_k3s" =~ ^[Yy]$ ]]; then
        print_warning "这将删除现有的K3s安装"
        read -p "确定要继续吗? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            print_info "卸载K3s..."
            /usr/local/bin/k3s-uninstall.sh || true
            
            print_info "重新安装K3s..."
            curl -sfL https://get.k3s.io | sh -
            
            print_info "等待K3s启动..."
            sleep 60
            
            # 重新检查
            check_k3s_service
            check_kubeconfig
            check_system_pods
        fi
    fi
}

# 显示解决建议
show_recommendations() {
    print_info "=== 解决建议 ==="
    
    echo "常见问题和解决方案:"
    echo
    echo "1. K3s服务启动失败:"
    echo "   - 检查系统资源 (内存至少2GB)"
    echo "   - 检查防火墙配置"
    echo "   - 查看服务日志: journalctl -u k3s -f"
    echo
    echo "2. kubectl连接失败:"
    echo "   - 检查kubeconfig文件权限"
    echo "   - 设置KUBECONFIG环境变量"
    echo "   - 重启K3s服务"
    echo
    echo "3. 系统Pod未就绪:"
    echo "   - 等待更长时间 (首次安装可能需要10-15分钟)"
    echo "   - 检查网络连接"
    echo "   - 检查容器镜像拉取"
    echo
    echo "4. 网络问题:"
    echo "   - 检查DNS配置"
    echo "   - 检查防火墙规则"
    echo "   - 重启网络服务"
    echo
    echo "有用的命令:"
    echo "  systemctl status k3s"
    echo "  journalctl -u k3s -f"
    echo "  kubectl get pods --all-namespaces"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo "  kubectl logs <pod-name> -n <namespace>"
}

# 主函数
main() {
    print_info "=== K3s诊断工具 ==="
    echo
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 执行诊断
    check_k3s_service
    echo
    check_kubeconfig
    echo
    check_system_pods
    echo
    check_network
    echo
    check_resources
    echo
    check_container_runtime
    echo
    check_k3s_config
    echo
    show_recommendations
    echo
    
    # 询问是否尝试修复
    try_fix_k3s
    
    print_success "K3s诊断完成！"
}

# 脚本入口
main "$@"
