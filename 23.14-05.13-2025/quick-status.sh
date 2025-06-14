#!/bin/bash

# 快速状态检查脚本 - 简化输出
# 只显示关键状态信息

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
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        print_success "$cmd 已安装"
        return 0
    else
        print_error "$cmd 未安装"
        return 1
    fi
}

# 检查服务状态
check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_success "$service 服务运行中"
        return 0
    else
        print_error "$service 服务未运行"
        return 1
    fi
}

# 主检查函数
main() {
    echo "=== 快速状态检查 ==="
    echo
    
    # 1. 检查基础命令
    print_info "检查基础命令:"
    check_command "curl"
    check_command "wget"
    check_command "nginx"
    check_command "certbot"
    check_command "ufw"
    
    echo
    
    # 2. 检查K3s相关
    print_info "检查K3s相关:"
    check_command "k3s"
    check_command "kubectl"
    check_command "helm"
    
    echo
    
    # 3. 检查服务状态
    print_info "检查服务状态:"
    check_service "ssh"
    check_service "nginx"
    check_service "k3s"
    
    echo
    
    # 4. 检查K3s连接
    print_info "检查K3s连接:"
    if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
        print_success "kubeconfig 文件存在"
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        
        if kubectl get nodes >/dev/null 2>&1; then
            print_success "kubectl 连接正常"
            local node_count=$(kubectl get nodes --no-headers | wc -l)
            print_info "节点数量: $node_count"
        else
            print_error "kubectl 连接失败"
        fi
    else
        print_error "kubeconfig 文件不存在"
    fi
    
    echo
    
    # 5. 检查防火墙
    print_info "检查防火墙状态:"
    if ufw status >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1 | awk '{print $2}')
        if [[ "$ufw_status" == "active" ]]; then
            print_warning "UFW 防火墙已启用"
        else
            print_info "UFW 防火墙未启用"
        fi
    else
        print_error "UFW 不可用"
    fi
    
    echo
    
    # 6. 检查端口监听
    print_info "检查关键端口:"
    local ports=("22" "80" "443" "8080" "8443" "8448")
    for port in "${ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            print_success "端口 $port 正在监听"
        else
            print_warning "端口 $port 未监听"
        fi
    done
    
    echo
    
    # 7. 检查磁盘空间
    print_info "检查磁盘空间:"
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 80 ]]; then
        print_success "磁盘空间充足 (${disk_usage}% 已使用)"
    else
        print_warning "磁盘空间不足 (${disk_usage}% 已使用)"
    fi
    
    # 8. 检查内存
    local mem_available=$(free -m | awk '/^Mem:/{print $7}')
    if [[ $mem_available -gt 1000 ]]; then
        print_success "内存充足 (${mem_available}MB 可用)"
    else
        print_warning "内存不足 (${mem_available}MB 可用)"
    fi
    
    echo
    
    # 9. 给出建议
    print_info "=== 建议操作 ==="
    
    if ! command -v helm >/dev/null 2>&1; then
        echo "• 安装 Helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    fi
    
    if ! systemctl is-active --quiet k3s 2>/dev/null; then
        echo "• 安装 K3s: curl -sfL https://get.k3s.io | sh -"
    fi
    
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        echo "• 安装 Nginx: apt update && apt install -y nginx"
    fi
    
    echo "• 重新运行部署: bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)"
    
    echo
    print_info "状态检查完成"
}

# 脚本入口
main "$@"
