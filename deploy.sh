#!/bin/bash

# Element Server Suite 内网部署自动化脚本
# 版本: 1.0
# 作者: Suna.so AI Assistant
# 描述: 为内网环境定制的ESS自动化部署脚本，支持菜单式交互

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deployment.conf"
DEPLOY_DIR="/opt/matrix"
NAMESPACE="matrix"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    local deps=("kubectl" "helm" "dig" "curl" "jq")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少以下依赖: ${missing_deps[*]}"
        log_info "正在安装缺少的依赖..."
        
        # 更新包管理器
        apt-get update -qq
        
        # 安装基础工具
        apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates
        
        # 安装kubectl
        if [[ " ${missing_deps[*]} " =~ " kubectl " ]]; then
            log_info "安装 kubectl..."
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
            apt-get update -qq
            apt-get install -y kubectl
        fi
        
        # 安装helm
        if [[ " ${missing_deps[*]} " =~ " helm " ]]; then
            log_info "安装 Helm..."
            curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
            apt-get update -qq
            apt-get install -y helm
        fi
        
        # 安装其他工具
        if [[ " ${missing_deps[*]} " =~ " dig " ]]; then
            apt-get install -y dnsutils
        fi
        
        if [[ " ${missing_deps[*]} " =~ " jq " ]]; then
            apt-get install -y jq
        fi
        
        log_success "依赖安装完成"
    else
        log_success "所有依赖已满足"
    fi
}

# 获取公网IP
get_public_ip() {
    local domain="$1"
    log_info "获取公网IP地址..."
    
    local ip1=$(dig +short "ip.$domain" @8.8.8.8 2>/dev/null | tail -n1)
    local ip2=$(dig +short "ip.$domain" @1.1.1.1 2>/dev/null | tail -n1)
    
    if [[ -n "$ip1" && "$ip1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip1"
        return 0
    elif [[ -n "$ip2" && "$ip2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip2"
        return 0
    else
        log_error "无法获取公网IP地址"
        return 1
    fi
}

# 验证域名解析
verify_domain_resolution() {
    local domain="$1"
    local expected_ip="$2"
    
    log_info "验证域名解析: $domain"
    
    local resolved_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | tail -n1)
    
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        log_success "域名解析正确: $domain -> $resolved_ip"
        return 0
    else
        log_warning "域名解析可能不正确: $domain -> $resolved_ip (期望: $expected_ip)"
        return 1
    fi
}

# 配置收集菜单
collect_configuration() {
    log_header "配置收集"
    
    # 部署目录
    echo -e "${CYAN}请输入部署主目录 [默认: /opt/matrix]:${NC}"
    read -r input_deploy_dir
    DEPLOY_DIR="${input_deploy_dir:-/opt/matrix}"
    
    # 自定义域名
    echo -e "${CYAN}请输入您的域名 (例如: example.com):${NC}"
    read -r DOMAIN
    while [[ -z "$DOMAIN" ]]; do
        log_error "域名不能为空"
        echo -e "${CYAN}请输入您的域名:${NC}"
        read -r DOMAIN
    done
    
    # 获取公网IP
    PUBLIC_IP=$(get_public_ip "$DOMAIN")
    if [[ $? -ne 0 ]]; then
        echo -e "${CYAN}请手动输入公网IP地址:${NC}"
        read -r PUBLIC_IP
        while [[ ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            log_error "IP地址格式不正确"
            echo -e "${CYAN}请输入正确的IP地址:${NC}"
            read -r PUBLIC_IP
        done
    fi
    
    log_info "检测到公网IP: $PUBLIC_IP"
    
    # 验证域名解析
    verify_domain_resolution "$DOMAIN" "$PUBLIC_IP"
    
    # 外网访问端口配置
    echo -e "${CYAN}请输入HTTP外网访问端口 [默认: 8080]:${NC}"
    read -r input_http_port
    HTTP_PORT="${input_http_port:-8080}"
    
    echo -e "${CYAN}请输入HTTPS外网访问端口 [默认: 8443]:${NC}"
    read -r input_https_port
    HTTPS_PORT="${input_https_port:-8443}"
    
    # 内部端口配置
    echo -e "${CYAN}请输入内部HTTP端口 [默认: 30080]:${NC}"
    read -r input_internal_http
    INTERNAL_HTTP_PORT="${input_internal_http:-30080}"
    
    echo -e "${CYAN}请输入内部HTTPS端口 [默认: 30443]:${NC}"
    read -r input_internal_https
    INTERNAL_HTTPS_PORT="${input_internal_https:-30443}"
    
    echo -e "${CYAN}请输入联邦端口 [默认: 30448]:${NC}"
    read -r input_federation_port
    FEDERATION_PORT="${input_federation_port:-30448}"
    
    # UDP端口段
    echo -e "${CYAN}请输入UDP端口段起始 [默认: 30152]:${NC}"
    read -r input_udp_start
    UDP_PORT_START="${input_udp_start:-30152}"
    
    echo -e "${CYAN}请输入UDP端口段结束 [默认: 30250]:${NC}"
    read -r input_udp_end
    UDP_PORT_END="${input_udp_end:-30250}"
    
    # 证书配置
    echo -e "${CYAN}请选择证书模式:${NC}"
    echo "1) 生产证书 (Let's Encrypt)"
    echo "2) 测试证书 (Let's Encrypt Staging)"
    read -r cert_choice
    
    case $cert_choice in
        1)
            CERT_MODE="production"
            CERT_ISSUER="letsencrypt-prod"
            ;;
        2)
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            ;;
        *)
            log_warning "无效选择，使用测试证书"
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            ;;
    esac
    
    # Cloudflare API Token
    echo -e "${CYAN}请输入Cloudflare API Token:${NC}"
    read -r CLOUDFLARE_TOKEN
    while [[ -z "$CLOUDFLARE_TOKEN" ]]; do
        log_error "Cloudflare API Token不能为空"
        echo -e "${CYAN}请输入Cloudflare API Token:${NC}"
        read -r CLOUDFLARE_TOKEN
    done
    
    # 证书邮箱
    echo -e "${CYAN}请输入证书申请邮箱:${NC}"
    read -r CERT_EMAIL
    while [[ -z "$CERT_EMAIL" ]]; do
        log_error "证书邮箱不能为空"
        echo -e "${CYAN}请输入证书申请邮箱:${NC}"
        read -r CERT_EMAIL
    done
    
    # 服务管理员邮箱（可选）
    echo -e "${CYAN}请输入服务管理员邮箱 [可选]:${NC}"
    read -r ADMIN_EMAIL
    
    # 保存配置
    save_configuration
    
    # 显示配置摘要
    show_configuration_summary
}

# 保存配置
save_configuration() {
    cat > "$CONFIG_FILE" << EOF
# Element Server Suite 部署配置
# 生成时间: $(date)

DEPLOY_DIR="$DEPLOY_DIR"
DOMAIN="$DOMAIN"
PUBLIC_IP="$PUBLIC_IP"
HTTP_PORT="$HTTP_PORT"
HTTPS_PORT="$HTTPS_PORT"
INTERNAL_HTTP_PORT="$INTERNAL_HTTP_PORT"
INTERNAL_HTTPS_PORT="$INTERNAL_HTTPS_PORT"
FEDERATION_PORT="$FEDERATION_PORT"
UDP_PORT_START="$UDP_PORT_START"
UDP_PORT_END="$UDP_PORT_END"
CERT_MODE="$CERT_MODE"
CERT_ISSUER="$CERT_ISSUER"
CLOUDFLARE_TOKEN="$CLOUDFLARE_TOKEN"
CERT_EMAIL="$CERT_EMAIL"
ADMIN_EMAIL="$ADMIN_EMAIL"
NAMESPACE="$NAMESPACE"
EOF
    
    log_success "配置已保存到: $CONFIG_FILE"
}

# 加载配置
load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_success "配置已加载"
        return 0
    else
        log_warning "配置文件不存在"
        return 1
    fi
}

# 显示配置摘要
show_configuration_summary() {
    log_header "配置摘要"
    echo -e "${CYAN}部署目录:${NC} $DEPLOY_DIR"
    echo -e "${CYAN}域名:${NC} $DOMAIN"
    echo -e "${CYAN}公网IP:${NC} $PUBLIC_IP"
    echo -e "${CYAN}外网端口:${NC} HTTP:$HTTP_PORT, HTTPS:$HTTPS_PORT"
    echo -e "${CYAN}内部端口:${NC} HTTP:$INTERNAL_HTTP_PORT, HTTPS:$INTERNAL_HTTPS_PORT, 联邦:$FEDERATION_PORT"
    echo -e "${CYAN}UDP端口段:${NC} $UDP_PORT_START-$UDP_PORT_END"
    echo -e "${CYAN}证书模式:${NC} $CERT_MODE"
    echo -e "${CYAN}证书邮箱:${NC} $CERT_EMAIL"
    if [[ -n "$ADMIN_EMAIL" ]]; then
        echo -e "${CYAN}管理员邮箱:${NC} $ADMIN_EMAIL"
    fi
    echo ""
}

# 主菜单
show_main_menu() {
    clear
    log_header "Element Server Suite 内网部署工具"
    echo ""
    echo "1) 配置部署参数"
    echo "2) 开始部署"
    echo "3) 查看当前配置"
    echo "4) 清理部署"
    echo "5) 重启服务"
    echo "6) 查看服务状态"
    echo "7) 查看日志"
    echo "8) 退出"
    echo ""
    echo -e "${CYAN}请选择操作 [1-8]:${NC}"
}

# 主函数
main() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    while true; do
        show_main_menu
        read -r choice
        
        case $choice in
            1)
                collect_configuration
                ;;
            2)
                if load_configuration; then
                    deploy_matrix_stack
                else
                    log_error "请先配置部署参数"
                fi
                ;;
            3)
                if load_configuration; then
                    show_configuration_summary
                else
                    log_error "配置文件不存在"
                fi
                read -p "按回车键继续..."
                ;;
            4)
                cleanup_deployment
                ;;
            5)
                restart_services
                ;;
            6)
                show_service_status
                ;;
            7)
                show_logs
                ;;
            8)
                log_info "退出部署工具"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 2
                ;;
        esac
    done
}

# 部署Matrix Stack
deploy_matrix_stack() {
    log_header "开始部署Element Server Suite"
    
    # 检查Kubernetes集群
    check_kubernetes_cluster
    
    # 创建部署目录
    create_deployment_directory
    
    # 安装cert-manager
    install_cert_manager
    
    # 配置证书颁发者
    setup_certificate_issuers
    
    # 生成自定义values文件
    generate_values_file
    
    # 部署Matrix Stack
    deploy_helm_chart
    
    # 配置防火墙和端口转发
    configure_firewall_and_ports
    
    # 验证部署
    verify_deployment
    
    log_success "Element Server Suite部署完成!"
    show_access_information
    read -p "按回车键继续..."
}

# 检查Kubernetes集群
check_kubernetes_cluster() {
    log_info "检查Kubernetes集群状态..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接到Kubernetes集群"
        log_info "请确保Kubernetes集群正在运行并且kubectl配置正确"
        
        echo -e "${CYAN}是否需要安装k3s? (y/n):${NC}"
        read -r install_k3s
        
        if [[ "$install_k3s" =~ ^[Yy]$ ]]; then
            install_k3s_cluster
        else
            log_error "需要Kubernetes集群才能继续部署"
            return 1
        fi
    fi
    
    # 检查节点状态
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ $ready_nodes -eq 0 ]]; then
        log_error "没有Ready状态的节点"
        return 1
    fi
    
    log_success "Kubernetes集群状态正常 ($ready_nodes 个节点Ready)"
}

# 安装k3s集群
install_k3s_cluster() {
    log_info "安装k3s Kubernetes集群..."
    
    # 下载并安装k3s
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -
    
    # 等待k3s启动
    sleep 30
    
    # 配置kubectl
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config
    
    # 验证安装
    if kubectl cluster-info &>/dev/null; then
        log_success "k3s集群安装成功"
    else
        log_error "k3s集群安装失败"
        return 1
    fi
}

# 创建部署目录
create_deployment_directory() {
    log_info "创建部署目录: $DEPLOY_DIR"
    
    mkdir -p "$DEPLOY_DIR"/{synapse,postgres,element-web,element-call,configs,backups}
    chown -R 1000:1000 "$DEPLOY_DIR"
    
    log_success "部署目录创建完成"
}

# 安装cert-manager
install_cert_manager() {
    log_info "安装cert-manager..."
    
    # 检查cert-manager是否已安装
    if kubectl get namespace cert-manager &>/dev/null; then
        log_info "cert-manager已存在，跳过安装"
        return 0
    fi
    
    # 添加cert-manager Helm仓库
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # 安装cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.0 \
        --set installCRDs=true \
        --wait
    
    if [[ $? -eq 0 ]]; then
        log_success "cert-manager安装成功"
    else
        log_error "cert-manager安装失败"
        return 1
    fi
}

# 配置证书颁发者
setup_certificate_issuers() {
    log_info "配置证书颁发者..."
    
    # 创建Cloudflare API Token Secret
    local cloudflare_secret=$(cat templates/cert-manager/cloudflare-secret.yaml)
    cloudflare_secret=${cloudflare_secret//CLOUDFLARE_TOKEN_PLACEHOLDER/$CLOUDFLARE_TOKEN}
    
    echo "$cloudflare_secret" | kubectl apply -f -
    
    # 创建证书颁发者
    local issuer_file=""
    if [[ "$CERT_MODE" == "production" ]]; then
        issuer_file="templates/cert-manager/cluster-issuer-production.yaml"
    else
        issuer_file="templates/cert-manager/cluster-issuer-staging.yaml"
    fi
    
    local issuer_config=$(cat "$issuer_file")
    issuer_config=${issuer_config//CERT_EMAIL_PLACEHOLDER/$CERT_EMAIL}
    
    echo "$issuer_config" | kubectl apply -f -
    
    log_success "证书颁发者配置完成"
}

# 生成自定义values文件
generate_values_file() {
    log_info "生成自定义values文件..."
    
    local values_content=$(cat templates/matrix-stack/values-template.yaml)
    
    # 替换占位符
    values_content=${values_content//DOMAIN_PLACEHOLDER/$DOMAIN}
    values_content=${values_content//HTTPS_PORT_PLACEHOLDER/$HTTPS_PORT}
    values_content=${values_content//HTTP_PORT_PLACEHOLDER/$HTTP_PORT}
    values_content=${values_content//INTERNAL_HTTP_PORT_PLACEHOLDER/$INTERNAL_HTTP_PORT}
    values_content=${values_content//INTERNAL_HTTPS_PORT_PLACEHOLDER/$INTERNAL_HTTPS_PORT}
    values_content=${values_content//FEDERATION_PORT_PLACEHOLDER/$FEDERATION_PORT}
    values_content=${values_content//UDP_PORT_START_PLACEHOLDER/$UDP_PORT_START}
    values_content=${values_content//UDP_PORT_END_PLACEHOLDER/$UDP_PORT_END}
    values_content=${values_content//CERT_ISSUER_PLACEHOLDER/$CERT_ISSUER}
    values_content=${values_content//DEPLOY_DIR_PLACEHOLDER/$DEPLOY_DIR}
    
    # 生成随机PostgreSQL密码
    local postgres_password=$(openssl rand -base64 32)
    values_content=${values_content//POSTGRES_PASSWORD_PLACEHOLDER/$postgres_password}
    
    # 保存values文件
    echo "$values_content" > "$DEPLOY_DIR/values.yaml"
    
    log_success "自定义values文件生成完成: $DEPLOY_DIR/values.yaml"
}

# 部署Helm Chart
deploy_helm_chart() {
    log_info "部署Matrix Stack Helm Chart..."
    
    # 创建命名空间
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # 添加ESS Helm仓库
    helm repo add ess https://element-hq.github.io/ess-helm
    helm repo update
    
    # 部署Matrix Stack
    helm upgrade --install matrix-stack ess/matrix-stack \
        --namespace "$NAMESPACE" \
        --values "$DEPLOY_DIR/values.yaml" \
        --wait \
        --timeout 20m
    
    if [[ $? -eq 0 ]]; then
        log_success "Matrix Stack部署成功"
    else
        log_error "Matrix Stack部署失败"
        return 1
    fi
}

# 配置防火墙和端口转发
configure_firewall_and_ports() {
    log_info "配置防火墙和端口转发..."
    
    # 检查iptables是否可用
    if command -v iptables &>/dev/null; then
        # 配置端口转发规则
        iptables -t nat -A PREROUTING -p tcp --dport "$HTTP_PORT" -j REDIRECT --to-port "$INTERNAL_HTTP_PORT"
        iptables -t nat -A PREROUTING -p tcp --dport "$HTTPS_PORT" -j REDIRECT --to-port "$INTERNAL_HTTPS_PORT"
        
        # 配置UDP端口转发 (用于RTC)
        for ((port=$UDP_PORT_START; port<=$UDP_PORT_END; port++)); do
            iptables -t nat -A PREROUTING -p udp --dport "$port" -j REDIRECT --to-port "$port"
        done
        
        # 保存iptables规则
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        
        log_success "防火墙规则配置完成"
    else
        log_warning "iptables不可用，请手动配置端口转发"
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态..."
    
    # 等待所有Pod就绪
    log_info "等待所有Pod就绪..."
    kubectl wait --for=condition=ready pod --all -n "$NAMESPACE" --timeout=600s
    
    # 检查服务状态
    local failed_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -v "Running\|Completed" | wc -l)
    
    if [[ $failed_pods -eq 0 ]]; then
        log_success "所有Pod运行正常"
    else
        log_warning "有 $failed_pods 个Pod状态异常"
        kubectl get pods -n "$NAMESPACE"
    fi
    
    # 检查证书状态
    log_info "检查证书状态..."
    kubectl get certificates -n "$NAMESPACE"
}

# 显示访问信息
show_access_information() {
    log_header "访问信息"
    echo -e "${CYAN}Matrix服务器:${NC} https://$DOMAIN:$HTTPS_PORT"
    echo -e "${CYAN}Element Web客户端:${NC} https://element.$DOMAIN:$HTTPS_PORT"
    echo -e "${CYAN}Element Call视频会议:${NC} https://call.$DOMAIN:$HTTPS_PORT"
    echo -e "${CYAN}联邦端口:${NC} $FEDERATION_PORT"
    echo -e "${CYAN}UDP端口范围:${NC} $UDP_PORT_START-$UDP_PORT_END"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "1. 请确保防火墙允许以上端口的访问"
    echo "2. 请确保域名DNS解析指向您的公网IP: $PUBLIC_IP"
    echo "3. 证书可能需要几分钟时间完成申请和验证"
    echo ""
}

# 清理部署
cleanup_deployment() {
    log_header "清理部署环境"
    
    echo -e "${YELLOW}警告: 此操作将删除所有Matrix相关的部署和数据!${NC}"
    echo -e "${CYAN}确认要继续吗? (输入 'YES' 确认):${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log_info "操作已取消"
        read -p "按回车键继续..."
        return 0
    fi
    
    log_info "开始清理部署..."
    
    # 删除Helm部署
    if helm list -n "$NAMESPACE" | grep -q "matrix-stack"; then
        log_info "删除Matrix Stack Helm部署..."
        helm uninstall matrix-stack -n "$NAMESPACE"
    fi
    
    # 删除命名空间
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "删除命名空间: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --timeout=300s
    fi
    
    # 删除cert-manager (可选)
    echo -e "${CYAN}是否同时删除cert-manager? (y/n):${NC}"
    read -r delete_certmanager
    
    if [[ "$delete_certmanager" =~ ^[Yy]$ ]]; then
        if kubectl get namespace cert-manager &>/dev/null; then
            log_info "删除cert-manager..."
            helm uninstall cert-manager -n cert-manager
            kubectl delete namespace cert-manager --timeout=300s
        fi
    fi
    
    # 清理持久化数据
    echo -e "${CYAN}是否删除持久化数据目录? (y/n):${NC}"
    read -r delete_data
    
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        if [[ -d "$DEPLOY_DIR" ]]; then
            log_info "删除数据目录: $DEPLOY_DIR"
            rm -rf "$DEPLOY_DIR"
        fi
    fi
    
    # 清理iptables规则
    echo -e "${CYAN}是否清理iptables端口转发规则? (y/n):${NC}"
    read -r clean_iptables
    
    if [[ "$clean_iptables" =~ ^[Yy]$ ]]; then
        cleanup_iptables_rules
    fi
    
    log_success "清理完成!"
    read -p "按回车键继续..."
}

# 清理iptables规则
cleanup_iptables_rules() {
    if load_configuration && command -v iptables &>/dev/null; then
        log_info "清理iptables规则..."
        
        # 删除端口转发规则
        iptables -t nat -D PREROUTING -p tcp --dport "$HTTP_PORT" -j REDIRECT --to-port "$INTERNAL_HTTP_PORT" 2>/dev/null || true
        iptables -t nat -D PREROUTING -p tcp --dport "$HTTPS_PORT" -j REDIRECT --to-port "$INTERNAL_HTTPS_PORT" 2>/dev/null || true
        
        # 删除UDP端口转发规则
        for ((port=$UDP_PORT_START; port<=$UDP_PORT_END; port++)); do
            iptables -t nat -D PREROUTING -p udp --dport "$port" -j REDIRECT --to-port "$port" 2>/dev/null || true
        done
        
        # 保存规则
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        
        log_success "iptables规则清理完成"
    fi
}

# 重启服务
restart_services() {
    log_header "重启Matrix服务"
    
    if ! load_configuration; then
        log_error "配置文件不存在，无法重启服务"
        read -p "按回车键继续..."
        return 1
    fi
    
    echo -e "${CYAN}选择重启方式:${NC}"
    echo "1) 重启所有Pod"
    echo "2) 重启Synapse"
    echo "3) 重启Element Web"
    echo "4) 重启Element Call"
    echo "5) 重启PostgreSQL"
    echo "6) 返回主菜单"
    
    read -r restart_choice
    
    case $restart_choice in
        1)
            restart_all_pods
            ;;
        2)
            restart_specific_service "synapse"
            ;;
        3)
            restart_specific_service "element-web"
            ;;
        4)
            restart_specific_service "element-call"
            ;;
        5)
            restart_specific_service "postgres"
            ;;
        6)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    read -p "按回车键继续..."
}

# 重启所有Pod
restart_all_pods() {
    log_info "重启所有Pod..."
    
    # 获取所有部署
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o name 2>/dev/null)
    local statefulsets=$(kubectl get statefulsets -n "$NAMESPACE" -o name 2>/dev/null)
    
    # 重启部署
    for deployment in $deployments; do
        log_info "重启 $deployment"
        kubectl rollout restart "$deployment" -n "$NAMESPACE"
    done
    
    # 重启有状态集
    for statefulset in $statefulsets; do
        log_info "重启 $statefulset"
        kubectl rollout restart "$statefulset" -n "$NAMESPACE"
    done
    
    # 等待重启完成
    log_info "等待重启完成..."
    kubectl rollout status deployment --all -n "$NAMESPACE" --timeout=300s
    kubectl rollout status statefulset --all -n "$NAMESPACE" --timeout=300s
    
    log_success "所有服务重启完成"
}

# 重启特定服务
restart_specific_service() {
    local service_name="$1"
    log_info "重启服务: $service_name"
    
    # 查找匹配的部署或有状态集
    local resource=$(kubectl get deployments,statefulsets -n "$NAMESPACE" -o name | grep "$service_name" | head -1)
    
    if [[ -n "$resource" ]]; then
        kubectl rollout restart "$resource" -n "$NAMESPACE"
        kubectl rollout status "$resource" -n "$NAMESPACE" --timeout=300s
        log_success "$service_name 重启完成"
    else
        log_error "未找到服务: $service_name"
    fi
}

# 查看服务状态
show_service_status() {
    log_header "服务状态"
    
    if ! load_configuration; then
        log_error "配置文件不存在"
        read -p "按回车键继续..."
        return 1
    fi
    
    # 检查命名空间是否存在
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "命名空间 $NAMESPACE 不存在，可能尚未部署"
        read -p "按回车键继续..."
        return 1
    fi
    
    echo -e "${CYAN}=== Pod状态 ===${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo -e "\n${CYAN}=== 服务状态 ===${NC}"
    kubectl get services -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== Ingress状态 ===${NC}"
    kubectl get ingress -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== 证书状态 ===${NC}"
    kubectl get certificates -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== 持久卷状态 ===${NC}"
    kubectl get pvc -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== Helm部署状态 ===${NC}"
    helm list -n "$NAMESPACE"
    
    # 检查关键服务的健康状态
    echo -e "\n${CYAN}=== 服务健康检查 ===${NC}"
    check_service_health
    
    read -p "按回车键继续..."
}

# 检查服务健康状态
check_service_health() {
    local services=("synapse" "postgres" "element-web")
    
    for service in "${services[@]}"; do
        local pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$service" -o name | head -1)
        
        if [[ -n "$pod" ]]; then
            local status=$(kubectl get "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            if [[ "$status" == "Running" ]]; then
                echo -e "${GREEN}✓${NC} $service: 运行正常"
            else
                echo -e "${RED}✗${NC} $service: $status"
            fi
        else
            echo -e "${YELLOW}?${NC} $service: 未找到Pod"
        fi
    done
}

# 查看日志
show_logs() {
    log_header "查看服务日志"
    
    if ! load_configuration; then
        log_error "配置文件不存在"
        read -p "按回车键继续..."
        return 1
    fi
    
    # 检查命名空间是否存在
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "命名空间 $NAMESPACE 不存在，可能尚未部署"
        read -p "按回车键继续..."
        return 1
    fi
    
    echo -e "${CYAN}选择要查看日志的服务:${NC}"
    echo "1) Synapse"
    echo "2) Element Web"
    echo "3) Element Call"
    echo "4) PostgreSQL"
    echo "5) 所有服务"
    echo "6) 返回主菜单"
    
    read -r log_choice
    
    case $log_choice in
        1)
            show_service_logs "synapse"
            ;;
        2)
            show_service_logs "element-web"
            ;;
        3)
            show_service_logs "element-call"
            ;;
        4)
            show_service_logs "postgres"
            ;;
        5)
            show_all_logs
            ;;
        6)
            return 0
            ;;
        *)
            log_error "无效选择"
            read -p "按回车键继续..."
            ;;
    esac
}

# 查看特定服务日志
show_service_logs() {
    local service_name="$1"
    log_info "查看 $service_name 日志 (按Ctrl+C退出)"
    
    # 查找匹配的Pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$service_name" -o name | head -1)
    
    if [[ -n "$pod" ]]; then
        kubectl logs -f "$pod" -n "$NAMESPACE" --tail=100
    else
        log_error "未找到 $service_name 的Pod"
    fi
    
    read -p "按回车键继续..."
}

# 查看所有服务日志
show_all_logs() {
    log_info "查看所有服务日志 (按Ctrl+C退出)"
    
    # 获取所有Pod
    local pods=$(kubectl get pods -n "$NAMESPACE" -o name)
    
    if [[ -n "$pods" ]]; then
        kubectl logs -f --all-containers=true --prefix=true -n "$NAMESPACE" --tail=50 $pods
    else
        log_error "未找到任何Pod"
    fi
    
    read -p "按回车键继续..."
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi