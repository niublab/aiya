#!/bin/bash

# Matrix ESS Community 部署验证脚本
# 用于验证分阶段部署的各个组件状态

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查第一阶段：基础服务
check_phase_1() {
    print_info "检查第一阶段：基础服务功能实现"
    
    # 检查K3s
    if command -v k3s &> /dev/null; then
        print_success "K3s已安装"
        if systemctl is-active --quiet k3s; then
            print_success "K3s服务运行中"
        else
            print_warning "K3s服务未运行"
        fi
    else
        print_error "K3s未安装"
    fi
    
    # 检查Helm
    if command -v helm &> /dev/null; then
        print_success "Helm已安装"
        local helm_version=$(helm version --short 2>/dev/null || echo "未知")
        print_info "Helm版本: $helm_version"
    else
        print_error "Helm未安装"
    fi
    
    # 检查cert-manager
    if k3s kubectl get namespace cert-manager &> /dev/null; then
        print_success "cert-manager命名空间存在"
        local cert_pods=$(k3s kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)
        print_info "cert-manager Pods数量: $cert_pods"
    else
        print_warning "cert-manager未部署"
    fi
}

# 检查第二阶段：ESS核心部署
check_phase_2() {
    print_info "检查第二阶段：ESS核心部署"
    
    # 检查ESS命名空间
    if k3s kubectl get namespace ess &> /dev/null; then
        print_success "ESS命名空间存在"
        
        # 检查ESS Pods
        local ess_pods=$(k3s kubectl get pods -n ess --no-headers 2>/dev/null | wc -l)
        local running_pods=$(k3s kubectl get pods -n ess --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        print_info "ESS Pods总数: $ess_pods"
        print_info "运行中的Pods: $running_pods"
        
        # 检查Helm release
        if helm list -n ess | grep -q "ess"; then
            print_success "ESS Helm release已部署"
            local release_status=$(helm status ess -n ess -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "未知")
            print_info "Release状态: $release_status"
        else
            print_warning "ESS Helm release未找到"
        fi
    else
        print_error "ESS命名空间不存在"
    fi
}

# 检查第三阶段：用户体验和高级功能
check_phase_3() {
    print_info "检查第三阶段：用户体验和高级功能"
    
    # 检查Ingress
    local ingress_count=$(k3s kubectl get ingress -A --no-headers 2>/dev/null | wc -l)
    print_info "Ingress资源数量: $ingress_count"
    
    # 检查证书
    local cert_count=$(k3s kubectl get certificates -A --no-headers 2>/dev/null | wc -l)
    print_info "证书资源数量: $cert_count"
    
    # 检查服务
    local svc_count=$(k3s kubectl get svc -n ess --no-headers 2>/dev/null | wc -l)
    print_info "ESS服务数量: $svc_count"
}

# 检查第四阶段：完善和优化
check_phase_4() {
    print_info "检查第四阶段：完善和优化"
    
    # 检查配置文件
    if [[ -f "/opt/matrix/ess-values.yaml" ]]; then
        print_success "ESS配置文件存在"
    else
        print_warning "ESS配置文件不存在"
    fi
    
    # 检查网络连通性
    print_info "检查网络连通性..."
    if curl -s --connect-timeout 5 https://ghcr.io &> /dev/null; then
        print_success "可以访问GitHub Container Registry"
    else
        print_warning "无法访问GitHub Container Registry"
    fi
}

# 显示部署摘要
show_deployment_summary() {
    print_info "部署摘要"
    echo "========================================"
    
    # 系统信息
    echo "系统信息:"
    echo "  操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || echo "未知")"
    echo "  内核版本: $(uname -r)"
    echo "  架构: $(uname -m)"
    echo
    
    # 组件版本
    echo "组件版本:"
    if command -v k3s &> /dev/null; then
        echo "  K3s: $(k3s --version | head -1 | awk '{print $3}' || echo "未知")"
    fi
    if command -v helm &> /dev/null; then
        echo "  Helm: $(helm version --short 2>/dev/null | cut -d'+' -f1 || echo "未知")"
    fi
    echo
    
    # 资源统计
    echo "资源统计:"
    local total_pods=$(k3s kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    local running_pods=$(k3s kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo "  总Pods数: $total_pods"
    echo "  运行中: $running_pods"
    echo
}

# 主函数
main() {
    echo "========================================"
    echo "Matrix ESS Community 部署验证"
    echo "========================================"
    echo
    
    # 检查是否有K3s环境
    if ! command -v k3s &> /dev/null; then
        print_warning "K3s未安装，无法进行完整验证"
        echo "请先运行部署脚本的第一阶段"
        exit 1
    fi
    
    # 逐阶段检查
    check_phase_1
    echo
    check_phase_2
    echo
    check_phase_3
    echo
    check_phase_4
    echo
    
    # 显示摘要
    show_deployment_summary
    
    print_info "验证完成"
}

# 运行验证
main "$@"
