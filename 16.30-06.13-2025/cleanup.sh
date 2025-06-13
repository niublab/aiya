#!/bin/bash

# Matrix ESS Community 清理脚本 v5.0.0
# 简化版本 - 快速清理

set -euo pipefail

# 导入配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/matrix-config.env"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

print_step() {
    echo -e "\n${CYAN}>>> $1${NC}"
}

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
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

# 加载配置 (如果存在)
if [[ -f "$CONFIG_FILE" ]]; then
    # 安全加载配置文件，忽略readonly变量错误
    if source "$CONFIG_FILE" 2>/dev/null; then
        print_info "已加载配置文件: $CONFIG_FILE"
    else
        print_warning "配置文件加载有警告，但继续执行清理"
        # 手动提取关键配置
        INSTALL_DIR=$(grep "^INSTALL_DIR=" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2 || echo "/opt/matrix")
    fi
else
    print_warning "未找到配置文件，执行基本清理"
    INSTALL_DIR="/opt/matrix"
fi

print_step "Matrix ESS Community 清理"
print_warning "⚠️  这将删除所有Matrix数据，操作不可逆！"

# ==================== 清理函数 ====================

cleanup_ess() {
    print_step "清理 ESS 部署"
    
    if command -v helm &> /dev/null && command -v k3s &> /dev/null; then
        # 删除ESS Helm release
        if helm list -n ess | grep -q "ess"; then
            print_info "删除ESS Helm release..."
            helm uninstall ess -n ess || true
        fi
        
        # 删除命名空间
        if k3s kubectl get namespace ess &> /dev/null; then
            print_info "删除ESS命名空间..."
            k3s kubectl delete namespace ess --timeout=60s || true
        fi
        
        print_success "ESS清理完成"
    else
        print_info "K3s或Helm未安装，跳过ESS清理"
    fi
}

cleanup_cert_manager() {
    print_step "清理 cert-manager"
    
    if command -v k3s &> /dev/null; then
        if k3s kubectl get namespace cert-manager &> /dev/null; then
            print_info "删除cert-manager..."
            k3s kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.0/cert-manager.yaml || true
        fi
        
        print_success "cert-manager清理完成"
    else
        print_info "K3s未安装，跳过cert-manager清理"
    fi
}

cleanup_k3s() {
    print_step "清理 K3s"
    
    if command -v k3s &> /dev/null; then
        print_info "卸载K3s..."
        if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
            /usr/local/bin/k3s-uninstall.sh || true
        fi
        
        # 清理残留文件
        rm -rf /etc/rancher/k3s /var/lib/rancher/k3s /var/lib/kubelet /etc/kubernetes || true
        
        print_success "K3s清理完成"
    else
        print_info "K3s未安装，跳过清理"
    fi
}

cleanup_files() {
    print_step "清理文件和目录"
    
    # 清理安装目录
    if [[ -n "${INSTALL_DIR:-}" && -d "$INSTALL_DIR" ]]; then
        print_info "删除安装目录: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR" || true
    fi
    
    # 清理配置文件
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "删除配置文件: $CONFIG_FILE"
        rm -f "$CONFIG_FILE" || true
    fi
    
    # 清理其他生成的文件
    rm -f "$SCRIPT_DIR"/*.yaml "$SCRIPT_DIR"/*.txt "$SCRIPT_DIR"/*.log 2>/dev/null || true
    
    print_success "文件清理完成"
}

cleanup_packages() {
    print_step "清理软件包"
    
    # 卸载Helm
    if command -v helm &> /dev/null; then
        print_info "删除Helm..."
        rm -f /usr/local/bin/helm || true
    fi
    
    print_success "软件包清理完成"
}

show_cleanup_summary() {
    print_step "清理完成"
    
    print_success "🧹 Matrix ESS Community 清理完成！"
    echo
    print_info "已清理的内容:"
    echo "  ✅ ESS Helm部署"
    echo "  ✅ cert-manager"
    echo "  ✅ K3s集群"
    echo "  ✅ 安装目录和配置文件"
    echo "  ✅ 相关软件包"
    echo
    print_info "系统已恢复到安装前状态"
    echo
    print_warning "注意: 如果有其他应用使用K3s，请检查是否受到影响"
}

# ==================== 主清理流程 ====================

main() {
    print_info "开始清理流程..."
    
    # 执行清理步骤
    cleanup_ess
    cleanup_cert_manager
    cleanup_k3s
    cleanup_files
    cleanup_packages
    show_cleanup_summary
    
    print_success "🎉 清理流程完成！"
}

# 运行清理
main "$@"
