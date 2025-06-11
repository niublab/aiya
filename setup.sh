#!/bin/bash

# Matrix ESS Community 内网部署自动化脚本
# 版本: 1.0.0 (第一阶段)
# 创建日期: 2025-06-09
# 许可证: AGPL-3.0 (仅限非商业用途)

set -euo pipefail

# ==================== 全局变量和配置 ====================

# 脚本信息
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="Matrix ESS Community 部署脚本"
readonly SCRIPT_DATE="2025-06-10"

# 版本信息 (基于官方最新稳定版本)
readonly ESS_VERSION="25.6.1"
readonly K3S_VERSION="v1.32.2+k3s1"
readonly HELM_VERSION="v3.17.3"
readonly CERT_MANAGER_VERSION="v1.17.2"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# 日志文件
readonly LOG_DIR="/var/log/matrix-ess"
readonly LOG_FILE="${LOG_DIR}/setup.log"

# 默认配置
readonly DEFAULT_INSTALL_DIR="/opt/matrix"
readonly DEFAULT_HTTP_PORT="8080"
readonly DEFAULT_HTTPS_PORT="8443"
readonly DEFAULT_FEDERATION_PORT="8448"

# ESS 相关配置
readonly ESS_NAMESPACE="ess"
readonly ESS_HELM_CHART="oci://ghcr.io/element-hq/ess-helm/matrix-stack"
readonly ESS_CONFIG_DIR="ess-config-values"

# 全局状态变量
INSTALL_DIR=""
CURRENT_STEP=""
TOTAL_STEPS=10

# ESS 配置变量
ESS_SERVER_NAME=""
ESS_SYNAPSE_HOST=""
ESS_AUTH_HOST=""
ESS_RTC_HOST=""
ESS_WEB_HOST=""
ESS_CERT_EMAIL=""
ESS_ADMIN_EMAIL=""
ESS_ADMIN_USERNAME=""
ESS_ADMIN_PASSWORD=""
ESS_CERT_MODE=""
ESS_CLOUDFLARE_TOKEN=""

# ==================== 日志和输出函数 ====================

# 执行命令函数 - 根据用户权限决定是否使用sudo
run_cmd() {
    if [ "$EUID" -eq 0 ]; then
        # 以root用户运行，直接执行命令
        "$@"
    else
        # 非root用户，使用sudo
        sudo "$@"
    fi
}

# 初始化日志目录
init_logging() {
    run_cmd mkdir -p "${LOG_DIR}"
    run_cmd touch "${LOG_FILE}"
    run_cmd chmod 644 "${LOG_FILE}"
    
    # 记录脚本开始
    log_info "=========================================="
    log_info "${SCRIPT_NAME} v${SCRIPT_VERSION} 启动"
    log_info "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "用户: $(whoami)"
    log_info "系统: $(uname -a)"
    log_info "=========================================="
}

# 日志记录函数
log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" | run_cmd tee -a "${LOG_FILE}" >/dev/null
}

log_warn() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $message" | run_cmd tee -a "${LOG_FILE}" >/dev/null
}

log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" | run_cmd tee -a "${LOG_FILE}" >/dev/null
}

# 彩色输出函数
print_header() {
    echo -e "\n${PURPLE}========================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}\n"
}

print_step() {
    local step_num="$1"
    local step_desc="$2"
    CURRENT_STEP="$step_desc"
    echo -e "\n${CYAN}[步骤 ${step_num}/${TOTAL_STEPS}] ${step_desc}${NC}"
    log_info "开始执行步骤 ${step_num}/${TOTAL_STEPS}: ${step_desc}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log_info "成功: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log_warn "$1"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    log_error "$1"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
    log_info "$1"
}

# 进度显示
show_progress() {
    local current="$1"
    local total="$2"
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}进度: ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%% - %s${NC}" "$percent" "$desc"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# ==================== 错误处理 ====================

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    print_error "脚本在第 ${line_number} 行执行失败 (退出码: ${exit_code})"
    print_error "当前步骤: ${CURRENT_STEP}"
    
    log_error "脚本执行失败"
    log_error "退出码: ${exit_code}"
    log_error "行号: ${line_number}"
    log_error "当前步骤: ${CURRENT_STEP}"
    
    echo -e "\n${RED}部署失败！${NC}"
    echo -e "${YELLOW}请检查日志文件: ${LOG_FILE}${NC}"
    echo -e "${YELLOW}如需帮助，请提供日志文件内容${NC}"
    
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR

# ==================== 系统检查函数 ====================

# 检查操作系统
check_os() {
    print_step 1 "检查操作系统兼容性"
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "无法检测操作系统信息"
        exit 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            print_success "检测到兼容的操作系统: $PRETTY_NAME"
            ;;
        *)
            print_warning "检测到可能不兼容的操作系统: $PRETTY_NAME"
            print_info "脚本主要针对 Debian/Ubuntu 系统测试"
            read -p "是否继续安装? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "用户取消安装"
                exit 0
            fi
            ;;
    esac
    
    # 检查架构
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            print_success "检测到支持的架构: $arch"
            ;;
        aarch64|arm64)
            print_success "检测到支持的架构: $arch"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 检查系统资源
check_system_resources() {
    print_step 2 "检查系统资源"
    
    # 检查内存
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_gb" -lt 2 ]; then
        print_warning "系统内存不足 2GB (当前: ${mem_gb}GB)"
        print_info "建议至少 2GB 内存用于 50 人以下的视频会议"
    else
        print_success "内存检查通过: ${mem_gb}GB"
    fi
    
    # 检查CPU核心数
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        print_warning "CPU核心数不足 2 个 (当前: ${cpu_cores})"
        print_info "建议至少 2 个CPU核心"
    else
        print_success "CPU检查通过: ${cpu_cores} 核心"
    fi
    
    # 检查磁盘空间
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$disk_gb" -lt 10 ]; then
        print_error "磁盘空间不足 10GB (可用: ${disk_gb}GB)"
        exit 1
    else
        print_success "磁盘空间检查通过: ${disk_gb}GB 可用"
    fi
}

# 检查网络连接
check_network() {
    print_step 3 "检查网络连接"
    
    # 检查基本网络连接
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_success "网络连接正常"
    else
        print_error "无法连接到互联网"
        exit 1
    fi
    
    # 检查DNS解析
    if nslookup github.com >/dev/null 2>&1; then
        print_success "DNS解析正常"
    else
        print_error "DNS解析失败"
        exit 1
    fi
    
    # 检查关键域名解析
    local domains=("k3s.io" "helm.sh" "github.com" "get.helm.sh")
    for domain in "${domains[@]}"; do
        if nslookup "$domain" >/dev/null 2>&1; then
            print_success "域名解析正常: $domain"
        else
            print_warning "域名解析失败: $domain"
        fi
    done
}

# 检查权限
check_permissions() {
    print_step 4 "检查用户权限"
    
    if [ "$EUID" -eq 0 ]; then
        print_warning "检测到以 root 用户运行"
        print_info "将以 root 权限继续安装..."
    fi
    
    if [ "$EUID" -eq 0 ]; then
        print_success "root 权限检查通过"
    elif sudo -n true 2>/dev/null; then
        print_success "sudo 权限检查通过"
    else
        print_error "当前用户没有 sudo 权限"
        print_info "请确保当前用户在 sudo 组中或以 root 用户运行"
        exit 1
    fi
}

# ==================== 依赖安装函数 ====================

# 更新系统包
update_system() {
    print_step 5 "更新系统包"
    
    print_info "更新包列表..."
    run_cmd apt-get update -qq
    
    print_info "安装基础依赖..."
    run_cmd apt-get install -y -qq \
        curl \
        wget \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        software-properties-common \
        jq \
        unzip
    
    print_success "系统包更新完成"
}

# 安装 K3s
install_k3s() {
    print_step 6 "安装 K3s"
    
    # 检查是否已安装
    if command -v k3s >/dev/null 2>&1; then
        local installed_version=$(k3s --version | head -n1 | awk '{print $3}')
        print_info "检测到已安装的 K3s 版本: $installed_version"
        
        if [[ "$installed_version" == "$K3S_VERSION"* ]]; then
            print_success "K3s 版本正确，跳过安装"
            return 0
        else
            print_warning "K3s 版本不匹配，将重新安装"
        fi
    fi
    
    print_info "下载并安装 K3s $K3S_VERSION..."
    
    # 设置安装参数
    export INSTALL_K3S_VERSION="$K3S_VERSION"
    export INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb"
    
    # 下载并执行安装脚本
    curl -sfL https://get.k3s.io | sh -
    
    # 等待 K3s 启动
    print_info "等待 K3s 服务启动..."
    local timeout=60
    local count=0
    
    while [ $count -lt $timeout ]; do
        if run_cmd k3s kubectl get nodes >/dev/null 2>&1; then
            break
        fi
        sleep 2
        count=$((count + 2))
        show_progress $count $timeout "等待 K3s 启动"
    done
    
    if [ $count -ge $timeout ]; then
        print_error "K3s 启动超时"
        exit 1
    fi
    
    # 配置 kubectl
    mkdir -p ~/.kube
    run_cmd cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    run_cmd chown $(id -u):$(id -g) ~/.kube/config
    
    # 验证安装
    if run_cmd k3s kubectl get nodes | grep -q Ready; then
        print_success "K3s 安装并启动成功"
        run_cmd k3s kubectl get nodes
    else
        print_error "K3s 安装失败"
        exit 1
    fi
}

# 安装 Helm
install_helm() {
    print_step 7 "安装 Helm"
    
    # 检查是否已安装
    if command -v helm >/dev/null 2>&1; then
        local installed_version=$(helm version --short | cut -d'+' -f1)
        print_info "检测到已安装的 Helm 版本: $installed_version"
        
        if [[ "$installed_version" == "$HELM_VERSION"* ]]; then
            print_success "Helm 版本正确，跳过安装"
            return 0
        else
            print_warning "Helm 版本不匹配，将重新安装"
        fi
    fi
    
    print_info "下载并安装 Helm $HELM_VERSION..."
    
    # 下载 Helm 安装脚本
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    
    # 安装 Helm
    ./get_helm.sh
    rm -f get_helm.sh
    
    # 验证安装
    if helm version >/dev/null 2>&1; then
        print_success "Helm 安装成功"
        helm version --short
    else
        print_error "Helm 安装失败"
        exit 1
    fi
}

# 安装 cert-manager
install_cert_manager() {
    print_step 8 "安装 cert-manager"
    
    # 检查是否已安装
    if run_cmd k3s kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_info "检测到已安装的 cert-manager"
        
        # 检查版本
        local installed_version=$(run_cmd k3s kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || echo "unknown")
        if [[ "$installed_version" == "${CERT_MANAGER_VERSION#v}" ]]; then
            print_success "cert-manager 版本正确，跳过安装"
            return 0
        else
            print_warning "cert-manager 版本不匹配 (当前: $installed_version, 期望: ${CERT_MANAGER_VERSION#v})"
            print_info "将重新安装 cert-manager"
        fi
    fi
    
    print_info "安装 cert-manager $CERT_MANAGER_VERSION..."
    
    # 添加 Helm 仓库
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    
    # 创建命名空间
    run_cmd k3s kubectl create namespace cert-manager --dry-run=client -o yaml | run_cmd k3s kubectl apply -f -
    
    # 安装 cert-manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version "$CERT_MANAGER_VERSION" \
        --set crds.enabled=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait --timeout=300s
    
    # 等待 cert-manager 就绪
    print_info "等待 cert-manager 组件就绪..."
    run_cmd k3s kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
    
    # 验证安装
    if run_cmd k3s kubectl get pods -n cert-manager | grep -q Running; then
        print_success "cert-manager 安装成功"
        run_cmd k3s kubectl get pods -n cert-manager
    else
        print_error "cert-manager 安装失败"
        exit 1
    fi
}

# ==================== 菜单系统 ====================

# 显示主菜单
show_main_menu() {
    clear
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    
    echo -e "${YELLOW}⚠ 许可证声明: 本软件仅限非商业用途使用 (AGPL-3.0)${NC}"
    echo -e "${YELLOW}  商业使用请联系 Element 获取商业许可${NC}\n"
    
    echo -e "${WHITE}请选择操作:${NC}"
    echo -e "  ${GREEN}1)${NC} 安装 Matrix ESS 基础环境 (K3s + Helm + cert-manager)"
    echo -e "  ${GREEN}2)${NC} 部署 ESS Community 完整服务"
    echo -e "  ${GREEN}3)${NC} 检查系统状态"
    echo -e "  ${GREEN}4)${NC} 查看安装日志"
    echo -e "  ${GREEN}5)${NC} 卸载所有组件"
    echo -e "  ${GREEN}6)${NC} 显示版本信息"
    echo -e "  ${RED}0)${NC} 退出"
    echo
}

# 显示版本信息
show_version_info() {
    clear
    print_header "版本信息"
    
    echo -e "${WHITE}脚本信息:${NC}"
    echo -e "  脚本名称: $SCRIPT_NAME"
    echo -e "  脚本版本: $SCRIPT_VERSION"
    echo -e "  创建日期: $SCRIPT_DATE"
    echo -e "  许可证: AGPL-3.0 (仅限非商业用途)"
    echo
    
    echo -e "${WHITE}组件版本 (基于官方最新稳定版本):${NC}"
    echo -e "  ESS Community: $ESS_VERSION"
    echo -e "  K3s: $K3S_VERSION"
    echo -e "  Helm: $HELM_VERSION"
    echo -e "  cert-manager: $CERT_MANAGER_VERSION"
    echo
    
    echo -e "${WHITE}系统信息:${NC}"
    echo -e "  操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || echo "未知")"
    echo -e "  内核版本: $(uname -r)"
    echo -e "  架构: $(uname -m)"
    echo -e "  当前用户: $(whoami)"
    echo
    
    read -p "按回车键返回主菜单..."
}

# 检查系统状态
check_system_status() {
    clear
    print_header "系统状态检查"
    
    echo -e "${WHITE}检查已安装组件:${NC}\n"
    
    # 检查 K3s
    if command -v k3s >/dev/null 2>&1; then
        local k3s_version=$(k3s --version | head -n1 | awk '{print $3}')
        print_success "K3s: $k3s_version"
        
        if systemctl is-active --quiet k3s; then
            print_success "K3s 服务: 运行中"
        else
            print_warning "K3s 服务: 未运行"
        fi
        
        # 检查节点状态
        if run_cmd k3s kubectl get nodes >/dev/null 2>&1; then
            local node_status=$(run_cmd k3s kubectl get nodes --no-headers | awk '{print $2}')
            if [[ "$node_status" == "Ready" ]]; then
                print_success "K3s 节点: Ready"
            else
                print_warning "K3s 节点: $node_status"
            fi
        fi
    else
        print_warning "K3s: 未安装"
    fi
    
    # 检查 Helm
    if command -v helm >/dev/null 2>&1; then
        local helm_version=$(helm version --short)
        print_success "Helm: $helm_version"
    else
        print_warning "Helm: 未安装"
    fi
    
    # 检查 cert-manager
    if run_cmd k3s kubectl get namespace cert-manager >/dev/null 2>&1; then
        local cm_version=$(run_cmd k3s kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || echo "unknown")
        print_success "cert-manager: v$cm_version"
        
        # 检查 cert-manager 状态
        local cm_ready=$(run_cmd k3s kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c Running || echo "0")
        local cm_total=$(run_cmd k3s kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$cm_ready" -eq "$cm_total" ] && [ "$cm_total" -gt 0 ]; then
            print_success "cert-manager 状态: $cm_ready/$cm_total 运行中"
        else
            print_warning "cert-manager 状态: $cm_ready/$cm_total 运行中"
        fi
    else
        print_warning "cert-manager: 未安装"
    fi
    
    echo
    read -p "按回车键返回主菜单..."
}

# 查看日志
view_logs() {
    clear
    print_header "安装日志"
    
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "${WHITE}最近 50 行日志:${NC}\n"
        tail -n 50 "$LOG_FILE"
    else
        print_warning "日志文件不存在: $LOG_FILE"
    fi
    
    echo
    read -p "按回车键返回主菜单..."
}

# 卸载所有组件
uninstall_all() {
    clear
    print_header "卸载所有组件"
    
    echo -e "${RED}警告: 此操作将完全删除以下组件:${NC}"
    echo -e "  - ESS Community (如果已安装)"
    echo -e "  - cert-manager"
    echo -e "  - Helm"
    echo -e "  - K3s (包括所有数据)"
    echo
    echo -e "${RED}此操作不可逆转！${NC}"
    echo
    
    read -p "确认要继续吗? 请输入 'YES' 确认: " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        print_info "取消卸载操作"
        read -p "按回车键返回主菜单..."
        return
    fi
    
    print_step 1 "卸载 ESS Community"
    if run_cmd k3s kubectl get namespace "$ESS_NAMESPACE" >/dev/null 2>&1; then
        helm uninstall ess -n "$ESS_NAMESPACE" 2>/dev/null || true
        run_cmd k3s kubectl delete namespace "$ESS_NAMESPACE" --ignore-not-found=true
        print_success "ESS Community 已卸载"
    else
        print_info "ESS Community 未安装，跳过"
    fi

    print_step 2 "卸载 cert-manager"
    if run_cmd k3s kubectl get namespace cert-manager >/dev/null 2>&1; then
        helm uninstall cert-manager -n cert-manager 2>/dev/null || true
        run_cmd k3s kubectl delete namespace cert-manager --ignore-not-found=true
        print_success "cert-manager 已卸载"
    else
        print_info "cert-manager 未安装，跳过"
    fi
    
    print_step 3 "卸载 K3s"
    if command -v k3s-uninstall.sh >/dev/null 2>&1; then
        run_cmd k3s-uninstall.sh
        print_success "K3s 已卸载"
    else
        print_info "K3s 未安装，跳过"
    fi
    
    print_step 4 "清理配置文件"
    rm -rf ~/.kube 2>/dev/null || true
    rm -rf "$DEFAULT_INSTALL_DIR" 2>/dev/null || true
    print_success "配置文件已清理"
    
    print_success "所有组件已成功卸载"
    read -p "按回车键返回主菜单..."
}

# ==================== 主安装流程 ====================

# 执行完整安装
run_full_installation() {
    clear
    print_header "开始安装 Matrix ESS 基础环境"
    
    echo -e "${WHITE}即将安装以下组件:${NC}"
    echo -e "  - K3s $K3S_VERSION"
    echo -e "  - Helm $HELM_VERSION"
    echo -e "  - cert-manager $CERT_MANAGER_VERSION"
    echo
    
    read -p "确认开始安装? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "用户取消安装"
        return
    fi
    
    # 初始化日志
    init_logging
    
    # 执行安装步骤
    check_os
    check_system_resources
    check_network
    check_permissions
    update_system
    install_k3s
    install_helm
    install_cert_manager
    
    # 最终验证
    print_step 9 "最终验证"
    
    local all_ok=true
    
    # 验证 K3s
    if ! run_cmd k3s kubectl get nodes | grep -q Ready; then
        print_error "K3s 验证失败"
        all_ok=false
    fi
    
    # 验证 Helm
    if ! helm version >/dev/null 2>&1; then
        print_error "Helm 验证失败"
        all_ok=false
    fi
    
    # 验证 cert-manager
    if ! run_cmd k3s kubectl get pods -n cert-manager | grep -q Running; then
        print_error "cert-manager 验证失败"
        all_ok=false
    fi
    
    if $all_ok; then
        print_step 10 "安装完成"
        print_success "所有组件安装成功！"
        
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${WHITE}安装完成总结${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${WHITE}已安装组件:${NC}"
        echo -e "  ✓ K3s $K3S_VERSION"
        echo -e "  ✓ Helm $HELM_VERSION"
        echo -e "  ✓ cert-manager $CERT_MANAGER_VERSION"
        echo
        echo -e "${WHITE}下一步:${NC}"
        echo -e "  - 第一阶段基础环境已就绪"
        echo -e "  - 可以开始第二阶段 ESS 部署"
        echo -e "  - 日志文件: $LOG_FILE"
        echo -e "${GREEN}========================================${NC}"
    else
        print_error "安装过程中出现错误，请检查日志"
    fi
    
    echo
    read -p "按回车键返回主菜单..."
}

# ==================== 主程序入口 ====================

# 主函数
main() {
    # 检查基本环境
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}警告: 检测到以 root 用户运行${NC}"
        echo -e "${GREEN}将以 root 权限继续安装...${NC}"
    fi
    
    # 主循环
    while true; do
        show_main_menu
        
        read -p "请选择 (0-6): " choice
        
        case $choice in
            1)
                run_full_installation
                ;;
            2)
                deploy_ess_community
                ;;
            3)
                check_system_status
                ;;
            4)
                view_logs
                ;;
            5)
                uninstall_all
                ;;
            6)
                show_version_info
                ;;
            0)
                echo -e "\n${GREEN}感谢使用 Matrix ESS Community 部署脚本！${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}无效选择，请重新输入${NC}"
                sleep 2
                ;;
        esac
    done
}

# ==================== ESS 部署功能 ====================

# 生成32位随机密码
generate_password() {
    local length=${1:-32}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c $length
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 验证邮箱格式
validate_email() {
    local email="$1"
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 收集ESS配置信息
collect_ess_config() {
    clear
    print_header "ESS Community 配置收集"
    
    echo -e "${WHITE}请按步骤配置 ESS Community 部署参数${NC}"
    echo -e "${YELLOW}提示: 所有域名都应该指向您的服务器IP地址${NC}"
    echo
    
    # 1. 服务器名称配置
    while true; do
        echo -e "${CYAN}步骤 1/7: 配置服务器名称${NC}"
        echo -e "服务器名称将作为Matrix用户ID的后缀，例如: @alice:your-domain.com"
        read -p "请输入服务器名称 (例如: matrix.example.com): " ESS_SERVER_NAME
        
        if validate_domain "$ESS_SERVER_NAME"; then
            print_success "服务器名称: $ESS_SERVER_NAME"
            break
        else
            print_error "无效的域名格式，请重新输入"
        fi
    done
    echo
    
    # 2. 子域名配置
    echo -e "${CYAN}步骤 2/7: 配置服务子域名${NC}"
    echo -e "建议使用以下子域名结构:"
    
    while true; do
        read -p "Synapse服务域名 [默认: matrix.$ESS_SERVER_NAME]: " input
        ESS_SYNAPSE_HOST=${input:-"matrix.$ESS_SERVER_NAME"}
        if validate_domain "$ESS_SYNAPSE_HOST"; then
            break
        else
            print_error "无效的域名格式"
        fi
    done
    
    while true; do
        read -p "认证服务域名 [默认: account.$ESS_SERVER_NAME]: " input
        ESS_AUTH_HOST=${input:-"account.$ESS_SERVER_NAME"}
        if validate_domain "$ESS_AUTH_HOST"; then
            break
        else
            print_error "无效的域名格式"
        fi
    done
    
    while true; do
        read -p "RTC服务域名 [默认: mrtc.$ESS_SERVER_NAME]: " input
        ESS_RTC_HOST=${input:-"mrtc.$ESS_SERVER_NAME"}
        if validate_domain "$ESS_RTC_HOST"; then
            break
        else
            print_error "无效的域名格式"
        fi
    done
    
    while true; do
        read -p "Web客户端域名 [默认: chat.$ESS_SERVER_NAME]: " input
        ESS_WEB_HOST=${input:-"chat.$ESS_SERVER_NAME"}
        if validate_domain "$ESS_WEB_HOST"; then
            break
        else
            print_error "无效的域名格式"
        fi
    done
    echo
    
    # 3. 证书配置
    echo -e "${CYAN}步骤 3/7: 配置SSL证书${NC}"
    echo -e "请选择证书类型:"
    echo -e "  1) 生产证书 (Let's Encrypt 正式环境)"
    echo -e "  2) 测试证书 (Let's Encrypt Staging环境)"
    
    while true; do
        read -p "请选择 (1-2): " cert_choice
        case $cert_choice in
            1)
                ESS_CERT_MODE="production"
                print_success "选择: 生产证书"
                break
                ;;
            2)
                ESS_CERT_MODE="staging"
                print_success "选择: 测试证书"
                break
                ;;
            *)
                print_error "无效选择，请输入 1 或 2"
                ;;
        esac
    done
    echo
    
    # 4. 证书邮箱
    echo -e "${CYAN}步骤 4/7: 配置证书申请邮箱${NC}"
    while true; do
        read -p "证书申请邮箱 (用于Let's Encrypt通知): " ESS_CERT_EMAIL
        if validate_email "$ESS_CERT_EMAIL"; then
            print_success "证书邮箱: $ESS_CERT_EMAIL"
            break
        else
            print_error "无效的邮箱格式"
        fi
    done
    echo
    
    # 5. Cloudflare API Token
    echo -e "${CYAN}步骤 5/7: 配置Cloudflare API Token${NC}"
    echo -e "${YELLOW}需要具有以下权限的API Token:${NC}"
    echo -e "  - Zone:DNS:Edit"
    echo -e "  - Zone:Zone:Read"
    echo -e "  - 作用域: 包含您的域名"
    
    while true; do
        read -p "Cloudflare API Token: " ESS_CLOUDFLARE_TOKEN
        if [[ -n "$ESS_CLOUDFLARE_TOKEN" ]]; then
            print_success "API Token已设置"
            break
        else
            print_error "API Token不能为空"
        fi
    done
    echo
    
    # 6. 管理员用户配置
    echo -e "${CYAN}步骤 6/7: 配置管理员用户${NC}"
    
    while true; do
        read -p "管理员用户名 [默认: admin]: " input
        ESS_ADMIN_USERNAME=${input:-"admin"}
        if [[ "$ESS_ADMIN_USERNAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            print_error "用户名只能包含字母、数字、下划线和连字符"
        fi
    done
    
    # 生成32位密码
    ESS_ADMIN_PASSWORD=$(generate_password 32)
    print_success "管理员密码已自动生成 (32位)"
    
    read -p "管理员邮箱 [可选，直接回车跳过]: " ESS_ADMIN_EMAIL
    if [[ -n "$ESS_ADMIN_EMAIL" ]] && ! validate_email "$ESS_ADMIN_EMAIL"; then
        print_warning "邮箱格式无效，将跳过邮箱设置"
        ESS_ADMIN_EMAIL=""
    fi
    echo
    
    # 7. 配置确认
    echo -e "${CYAN}步骤 7/7: 配置确认${NC}"
    echo -e "${WHITE}请确认以下配置信息:${NC}"
    echo -e "  服务器名称: $ESS_SERVER_NAME"
    echo -e "  Synapse: $ESS_SYNAPSE_HOST"
    echo -e "  认证服务: $ESS_AUTH_HOST"
    echo -e "  RTC服务: $ESS_RTC_HOST"
    echo -e "  Web客户端: $ESS_WEB_HOST"
    echo -e "  证书类型: $ESS_CERT_MODE"
    echo -e "  证书邮箱: $ESS_CERT_EMAIL"
    echo -e "  管理员用户: $ESS_ADMIN_USERNAME"
    echo -e "  管理员邮箱: ${ESS_ADMIN_EMAIL:-"未设置"}"
    echo
    
    read -p "确认配置并继续部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "用户取消部署"
        return 1
    fi
    
    return 0
}

# 检查基础环境
check_base_environment() {
    print_step 1 "检查基础环境"
    
    # 检查K3s
    if ! command -v k3s >/dev/null 2>&1; then
        print_error "K3s 未安装，请先运行选项1安装基础环境"
        return 1
    fi
    
    if ! run_cmd k3s kubectl get nodes >/dev/null 2>&1; then
        print_error "K3s 集群未就绪"
        return 1
    fi
    
    # 检查Helm
    if ! command -v helm >/dev/null 2>&1; then
        print_error "Helm 未安装，请先运行选项1安装基础环境"
        return 1
    fi
    
    # 检查cert-manager
    if ! run_cmd k3s kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_error "cert-manager 未安装，请先运行选项1安装基础环境"
        return 1
    fi
    
    print_success "基础环境检查通过"
    return 0
}

# 创建ESS命名空间和配置目录
setup_ess_environment() {
    print_step 2 "准备ESS环境"
    
    # 创建命名空间
    run_cmd k3s kubectl create namespace "$ESS_NAMESPACE" --dry-run=client -o yaml | run_cmd k3s kubectl apply -f -
    print_success "ESS命名空间已创建"
    
    # 创建配置目录
    local config_dir="$INSTALL_DIR/$ESS_CONFIG_DIR"
    mkdir -p "$config_dir"
    print_success "配置目录已创建: $config_dir"
    
    return 0
}

# 配置Cloudflare DNS验证
setup_cloudflare_dns() {
    print_step 3 "配置Cloudflare DNS验证"
    
    # 创建Cloudflare API Token Secret
    run_cmd k3s kubectl create secret generic cloudflare-api-token \
        --from-literal=api-token="$ESS_CLOUDFLARE_TOKEN" \
        --namespace cert-manager \
        --dry-run=client -o yaml | run_cmd k3s kubectl apply -f -
    
    print_success "Cloudflare API Token Secret已创建"
    
    # 创建ClusterIssuer
    local issuer_name="letsencrypt-$ESS_CERT_MODE"
    local acme_server
    
    if [[ "$ESS_CERT_MODE" == "production" ]]; then
        acme_server="https://acme-v02.api.letsencrypt.org/directory"
    else
        acme_server="https://acme-staging-v02.api.letsencrypt.org/directory"
    fi
    
    cat <<EOF | run_cmd k3s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $issuer_name
spec:
  acme:
    server: $acme_server
    email: $ESS_CERT_EMAIL
    privateKeySecretRef:
      name: $issuer_name-private-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
EOF
    
    print_success "ClusterIssuer已创建: $issuer_name"
    return 0
}

# 生成ESS配置文件
generate_ess_config() {
    print_step 4 "生成ESS配置文件"
    
    local config_dir="$INSTALL_DIR/$ESS_CONFIG_DIR"
    local issuer_name="letsencrypt-$ESS_CERT_MODE"
    
# 根据官方格式生成hostnames.yaml
    print_info "使用官方标准配置格式生成配置文件..."
    cat > "$config_dir/hostnames.yaml" <<EOF
# Copyright 2024-2025 New Vector Ltd
# SPDX-License-Identifier: AGPL-3.0-only
# Generated by Matrix ESS Community 部署脚本

# 服务器名称 - Matrix用户ID的后缀
serverName: $ESS_SERVER_NAME

# Element Web客户端配置
elementWeb:
  ingress:
    host: $ESS_WEB_HOST

# Matrix认证服务配置  
matrixAuthenticationService:
  ingress:
    host: $ESS_AUTH_HOST

# Matrix RTC服务配置
matrixRTC:
  ingress:
    host: $ESS_RTC_HOST

# Synapse服务器配置
synapse:
  ingress:
    host: $ESS_SYNAPSE_HOST

# 证书管理配置
certManager:
  clusterIssuer: $issuer_name

# 全局ingress配置
ingress:
  tlsEnabled: true
  annotations:
    cert-manager.io/cluster-issuer: $issuer_name
EOF    
    print_success "配置文件已生成: $config_dir/hostnames.yaml"
    return 0
}

# 部署ESS Community
deploy_ess_helm() {
    print_step 5 "部署ESS Community"
    
    local config_dir="$INSTALL_DIR/$ESS_CONFIG_DIR"
    
    print_info "开始Helm部署，这可能需要几分钟..."
    
    # 执行Helm安装
    print_info "正在执行: helm upgrade --install --namespace $ESS_NAMESPACE ess $ESS_HELM_CHART"
    if helm upgrade --install \
        --namespace "$ESS_NAMESPACE" \
        ess "$ESS_HELM_CHART" \
        -f "$config_dir/hostnames.yaml" \
        --wait --timeout=600s; then
        print_success "ESS Community部署成功"
    else
        print_error "ESS Community部署失败"
        print_error "可能的原因："
        print_error "1. 网络连接问题，无法下载镜像"
        print_error "2. 配置文件有误"
        print_error "3. 资源不足"
        print_error "4. DNS解析问题"
        echo
        print_info "请检查以下信息："
        echo "- 运行 'kubectl get pods -n $ESS_NAMESPACE' 查看Pod状态"
        echo "- 运行 'kubectl logs -n $ESS_NAMESPACE <pod-name>' 查看详细日志"
        echo "- 检查网络连接和DNS解析"
        return 1
    fi
    
    return 0
}

# 等待服务就绪
wait_for_services() {
    print_step 6 "等待服务就绪"
    
    local timeout=300
    local count=0
    
    print_info "等待所有Pod启动..."
    
    while [ $count -lt $timeout ]; do
        local ready_pods=$(run_cmd k3s kubectl get pods -n "$ESS_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local total_pods=$(run_cmd k3s kubectl get pods -n "$ESS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$total_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
            print_success "所有服务已就绪 ($ready_pods/$total_pods)"
            break
        fi
        
        sleep 5
        count=$((count + 5))
        show_progress $count $timeout "等待服务启动 ($ready_pods/$total_pods)"
    done
    
    if [ $count -ge $timeout ]; then
        print_warning "服务启动超时，但将继续创建用户"
    fi
    
    return 0
}

# 创建初始管理员用户
create_admin_user() {
    print_step 7 "创建管理员用户"
    
    print_info "创建管理员用户: $ESS_ADMIN_USERNAME"
    
    # 等待MAS服务可用
    local timeout=60
    local count=0
    
    while [ $count -lt $timeout ]; do
        if run_cmd k3s kubectl get pods -n "$ESS_NAMESPACE" -l app.kubernetes.io/name=matrix-authentication-service --no-headers 2>/dev/null | grep -q "Running"; then
            break
        fi
        sleep 2
        count=$((count + 2))
    done
    
    if [ $count -ge $timeout ]; then
        print_error "MAS服务未就绪，无法创建用户"
        return 1
    fi
    
    # 创建用户
    local create_cmd="mas-cli manage register-user --yes '$ESS_ADMIN_USERNAME'"
    
    if run_cmd k3s kubectl exec -n "$ESS_NAMESPACE" -it deploy/ess-matrix-authentication-service -- sh -c "$create_cmd" >/dev/null 2>&1; then
        print_success "管理员用户已创建: $ESS_ADMIN_USERNAME"
    else
        print_warning "用户创建可能失败，请手动验证"
    fi
    
    # 设置密码
    local password_cmd="mas-cli manage set-password '$ESS_ADMIN_USERNAME' '$ESS_ADMIN_PASSWORD'"
    
    if run_cmd k3s kubectl exec -n "$ESS_NAMESPACE" -it deploy/ess-matrix-authentication-service -- sh -c "$password_cmd" >/dev/null 2>&1; then
        print_success "管理员密码已设置"
    else
        print_warning "密码设置可能失败，请手动验证"
    fi
    
    return 0
}

# 验证部署
verify_deployment() {
    print_step 8 "验证部署"
    
    # 检查Pod状态
    local running_pods=$(run_cmd k3s kubectl get pods -n "$ESS_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$(run_cmd k3s kubectl get pods -n "$ESS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$running_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        print_success "Pod状态检查通过 ($running_pods/$total_pods)"
    else
        print_warning "部分Pod可能未正常运行 ($running_pods/$total_pods)"
    fi
    
    # 检查Ingress
    if run_cmd k3s kubectl get ingress -n "$ESS_NAMESPACE" >/dev/null 2>&1; then
        print_success "Ingress配置正常"
    else
        print_warning "Ingress配置可能有问题"
    fi
    
    # 检查证书
    local cert_count=$(run_cmd k3s kubectl get certificates -n "$ESS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$cert_count" -gt 0 ]; then
        print_success "SSL证书配置正常 ($cert_count 个证书)"
    else
        print_warning "SSL证书配置可能有问题"
    fi
    
    return 0
}

# 显示部署结果
show_deployment_result() {
    print_step 9 "部署完成"
    
    # 保存配置信息到文件
    local config_file="$INSTALL_DIR/ess-deployment-info.txt"
    
    cat > "$config_file" <<EOF
# ESS Community 部署信息
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

## 服务访问地址
Web客户端: https://$ESS_WEB_HOST
Synapse服务: https://$ESS_SYNAPSE_HOST
认证服务: https://$ESS_AUTH_HOST
RTC服务: https://$ESS_RTC_HOST

## 管理员账户
用户名: $ESS_ADMIN_USERNAME
密码: $ESS_ADMIN_PASSWORD
Matrix ID: @$ESS_ADMIN_USERNAME:$ESS_SERVER_NAME

## 证书信息
证书类型: $ESS_CERT_MODE
证书邮箱: $ESS_CERT_EMAIL

## 配置文件位置
配置目录: $INSTALL_DIR/$ESS_CONFIG_DIR
部署信息: $config_file

## 常用命令
查看Pod状态: kubectl get pods -n $ESS_NAMESPACE
查看日志: kubectl logs -n $ESS_NAMESPACE -l app.kubernetes.io/name=synapse
创建新用户: kubectl exec -n $ESS_NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
EOF
    
    print_success "ESS Community 部署完成！"
    
    echo -e "\\n${GREEN}========================================${NC}"
    echo -e "${WHITE}ESS Community 部署成功${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${WHITE}访问地址:${NC}"
    echo -e "  Web客户端: ${CYAN}https://$ESS_WEB_HOST${NC}"
    echo -e "  Synapse: ${CYAN}https://$ESS_SYNAPSE_HOST${NC}"
    echo -e "  认证服务: ${CYAN}https://$ESS_AUTH_HOST${NC}"
    echo -e "  RTC服务: ${CYAN}https://$ESS_RTC_HOST${NC}"
    echo
    echo -e "${WHITE}管理员账户:${NC}"
    echo -e "  用户名: ${YELLOW}$ESS_ADMIN_USERNAME${NC}"
    echo -e "  密码: ${YELLOW}$ESS_ADMIN_PASSWORD${NC}"
    echo -e "  Matrix ID: ${YELLOW}@$ESS_ADMIN_USERNAME:$ESS_SERVER_NAME${NC}"
    echo
    echo -e "${WHITE}重要提示:${NC}"
    echo -e "  - 请妥善保存管理员密码"
    echo -e "  - 详细信息已保存到: ${CYAN}$config_file${NC}"
    echo -e "  - 证书申请可能需要几分钟生效"
    echo -e "  - 确保所有域名的DNS记录指向此服务器"
    echo -e "${GREEN}========================================${NC}"
    
    return 0
}

# ESS Community 完整部署流程
deploy_ess_community() {
    clear
    print_header "部署 ESS Community 完整服务"
    
    echo -e "${WHITE}即将开始 ESS Community 部署流程${NC}"
    echo -e "${YELLOW}注意: 此操作需要有效的域名和Cloudflare API Token${NC}"
    echo
    
    read -p "确认开始部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "用户取消部署"
        return
    fi
    
    # 初始化日志
    init_logging
    
    # 设置安装目录
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    
    # 执行部署步骤
    if ! collect_ess_config; then
        print_error "配置收集失败或用户取消"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! check_base_environment; then
        print_error "基础环境检查失败，请先运行选项1安装基础环境"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! setup_ess_environment; then
        print_error "ESS环境准备失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! setup_cloudflare_dns; then
        print_error "Cloudflare DNS配置失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! generate_ess_config; then
        print_error "ESS配置文件生成失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! deploy_ess_helm; then
        print_error "ESS Community 部署失败，请检查错误信息"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! wait_for_services; then
        print_error "服务启动超时或失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! create_admin_user; then
        print_error "管理员用户创建失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    if ! verify_deployment; then
        print_error "部署验证失败"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    show_deployment_result
    
    echo
    read -p "按回车键返回主菜单..."
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi