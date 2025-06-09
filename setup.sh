#!/bin/bash

# ESS Community 修复版部署脚本
# 基于Element官方文档 - 2025年6月最新版本
# 版本: 2.0-fixed
# 使用方法: bash <(curl -fsSL https://raw.githubusercontent.com/your-repo/setup_fixed.sh)

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
CONFIG_DIR="$HOME/ess-config"
NAMESPACE="ess"

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
    
    local deps=("kubectl" "helm" "curl" "jq")
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
        apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates jq
        
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
        
        log_success "依赖安装完成"
    else
        log_success "所有依赖已满足"
    fi
}

# 检查Kubernetes集群
check_kubernetes_cluster() {
    log_info "检查Kubernetes集群状态..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接到Kubernetes集群"
        log_info "请确保Kubernetes集群正在运行并且kubectl配置正确"
        echo ""
        log_info "选项："
        log_info "  y - 自动安装k3s轻量级Kubernetes集群"
        log_info "  n - 取消部署，手动配置Kubernetes集群"
        echo ""
        echo -e "${CYAN}是否需要安装k3s? (y/n):${NC}"
        read -r install_k3s
        
        if [[ "$install_k3s" =~ ^[Yy]$ ]]; then
            install_k3s_cluster
            if [[ $? -ne 0 ]]; then
                log_error "k3s安装失败，无法继续部署"
                return 1
            fi
        else
            log_warning "用户选择不安装k3s，部署取消"
            log_info "您可以手动安装Kubernetes集群后重新运行部署"
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
    curl -sfL https://get.k3s.io | sh -
    
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

# 安装cert-manager
install_cert_manager() {
    log_info "安装cert-manager..."
    
    # 检查cert-manager是否已安装
    if kubectl get namespace cert-manager &>/dev/null; then
        log_info "cert-manager已存在，跳过安装"
        return 0
    fi
    
    # 添加cert-manager Helm仓库
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    
    # 安装cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.17.0 \
        --set crds.enabled=true \
        --wait
    
    if [[ $? -eq 0 ]]; then
        log_success "cert-manager安装成功"
    else
        log_error "cert-manager安装失败"
        return 1
    fi
}

# 配置收集菜单
collect_configuration() {
    log_header "配置收集"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 域名配置
    echo -e "${CYAN}请输入您的域名 (例如: example.com):${NC}"
    read -r DOMAIN
    while [[ -z "$DOMAIN" ]]; do
        log_error "域名不能为空"
        echo -e "${CYAN}请输入您的域名:${NC}"
        read -r DOMAIN
    done
    
    # 证书邮箱
    echo -e "${CYAN}请输入证书申请邮箱:${NC}"
    read -r CERT_EMAIL
    while [[ -z "$CERT_EMAIL" ]]; do
        log_error "证书邮箱不能为空"
        echo -e "${CYAN}请输入证书申请邮箱:${NC}"
        read -r CERT_EMAIL
    done
    
    # 证书模式选择
    echo -e "${CYAN}请选择证书模式:${NC}"
    echo "1) 生产证书 (Let's Encrypt)"
    echo "2) 测试证书 (Let's Encrypt Staging)"
    read -r cert_choice
    
    case $cert_choice in
        1)
            CERT_MODE="production"
            CERT_ISSUER="letsencrypt-prod"
            CERT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
            ;;
        2)
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            CERT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
            ;;
        *)
            log_warning "无效选择，使用测试证书"
            CERT_MODE="staging"
            CERT_ISSUER="letsencrypt-staging"
            CERT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
            ;;
    esac
    
    # 保存配置
    save_configuration
    
    # 显示配置摘要
    show_configuration_summary
}

# 保存配置
save_configuration() {
    cat > "$CONFIG_DIR/config.env" << EOF
# ESS Community 部署配置
# 生成时间: $(date)

DOMAIN="$DOMAIN"
CERT_EMAIL="$CERT_EMAIL"
CERT_MODE="$CERT_MODE"
CERT_ISSUER="$CERT_ISSUER"
CERT_SERVER="$CERT_SERVER"
NAMESPACE="$NAMESPACE"
EOF
    
    log_success "配置已保存到: $CONFIG_DIR/config.env"
}

# 加载配置
load_configuration() {
    if [[ -f "$CONFIG_DIR/config.env" ]]; then
        source "$CONFIG_DIR/config.env"
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
    echo -e "${CYAN}域名:${NC} $DOMAIN"
    echo -e "${CYAN}Element Web:${NC} https://element.$DOMAIN"
    echo -e "${CYAN}Matrix服务器:${NC} https://$DOMAIN"
    echo -e "${CYAN}证书模式:${NC} $CERT_MODE"
    echo -e "${CYAN}证书邮箱:${NC} $CERT_EMAIL"
    echo ""
}

# 生成配置文件
generate_configuration_files() {
    log_info "生成配置文件..."
    
    # 生成ClusterIssuer
    cat > "$CONFIG_DIR/cluster-issuer.yaml" << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $CERT_ISSUER
spec:
  acme:
    server: $CERT_SERVER
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: $CERT_ISSUER
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
    
    # 生成ESS Community values文件
    cat > "$CONFIG_DIR/values.yaml" << EOF
global:
  serverName: "$DOMAIN"

ingress:
  enabled: true
  className: "traefik"
  hosts:
    element: "element.$DOMAIN"
    synapse: "$DOMAIN"
  
  annotations:
    cert-manager.io/cluster-issuer: "$CERT_ISSUER"
    traefik.ingress.kubernetes.io/router.tls: "true"
  
  tls:
    - hosts:
        - "$DOMAIN"
        - "element.$DOMAIN"
      secretName: "ess-tls"

# Synapse配置
synapse:
  config:
    serverName: "$DOMAIN"
    publicBaseurl: "https://$DOMAIN"
    
    # 注册配置
    registration:
      enabled: false
      requiresToken: false
      allowGuests: false
    
    # 联邦配置
    federation:
      enabled: true
    
    # 日志配置
    logging:
      level: "INFO"

# Element Web配置
elementWeb:
  enabled: true
  config:
    defaultServerName: "$DOMAIN"
    defaultServerUrl: "https://$DOMAIN"
    brand: "Element"

# PostgreSQL配置
postgresql:
  enabled: true
  auth:
    database: "synapse"
    username: "synapse"
    password: "$(openssl rand -base64 32)"

# Matrix Authentication Service
matrixAuthenticationService:
  enabled: true

# 资源配置 (适配小型环境)
resources:
  synapse:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
  
  postgresql:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "500m"

# 持久化存储
persistence:
  enabled: true
  storageClass: ""
  accessMode: "ReadWriteOnce"
  size: "20Gi"
EOF
    
    log_success "配置文件生成完成"
}

# 部署ESS Community
deploy_ess_community() {
    log_header "部署ESS Community"
    
    log_info "使用官方OCI registry部署ESS Community..."
    
    # 创建命名空间
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # 应用ClusterIssuer
    kubectl apply -f "$CONFIG_DIR/cluster-issuer.yaml"
    
    # 部署ESS Community - 使用正确的OCI registry
    log_info "正在部署ESS Community，这可能需要几分钟时间..."
    helm upgrade --install --namespace "$NAMESPACE" ess \
        oci://ghcr.io/element-hq/ess-helm/matrix-stack \
        -f "$CONFIG_DIR/values.yaml" \
        --wait \
        --timeout 20m
    
    if [[ $? -eq 0 ]]; then
        log_success "ESS Community部署成功!"
    else
        log_error "ESS Community部署失败"
        return 1
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
    kubectl get certificates -n "$NAMESPACE" 2>/dev/null || log_info "证书正在申请中..."
    
    # 检查Ingress状态
    log_info "检查Ingress状态..."
    kubectl get ingress -n "$NAMESPACE"
}

# 创建初始用户
create_initial_user() {
    log_header "创建初始用户"
    
    log_info "ESS Community不允许默认用户注册"
    log_info "使用Matrix Authentication Service创建初始用户..."
    
    echo -e "${CYAN}准备创建初始用户，请按回车键继续...${NC}"
    read -r
    
    # 等待MAS pod就绪
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=matrix-authentication-service -n "$NAMESPACE" --timeout=300s
    
    # 创建用户
    kubectl exec -n "$NAMESPACE" -it deploy/ess-matrix-authentication-service -- \
        mas-cli manage register-user
    
    log_success "用户创建完成!"
}

# 显示访问信息
show_access_information() {
    log_header "访问信息"
    echo -e "${CYAN}Matrix服务器:${NC} https://$DOMAIN"
    echo -e "${CYAN}Element Web客户端:${NC} https://element.$DOMAIN"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "1. 请确保防火墙允许80和443端口的访问"
    echo "2. 请确保域名DNS解析指向您的服务器IP"
    echo "3. 证书可能需要几分钟时间完成申请和验证"
    echo "4. 如果无法访问，请检查Ingress和证书状态："
    echo "   kubectl get ingress -n $NAMESPACE"
    echo "   kubectl get certificates -n $NAMESPACE"
    echo ""
}

# 清理部署
cleanup_deployment() {
    log_header "清理部署环境"
    
    echo -e "${YELLOW}警告: 此操作将删除所有ESS相关的部署和数据!${NC}"
    echo -e "${CYAN}确认要继续吗? (输入 'YES' 确认):${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log_info "操作已取消"
        return 0
    fi
    
    log_info "开始清理部署..."
    
    # 删除Helm部署
    if helm list -n "$NAMESPACE" | grep -q "ess"; then
        log_info "删除ESS Community Helm部署..."
        helm uninstall ess -n "$NAMESPACE"
    fi
    
    # 删除命名空间
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "删除命名空间: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --timeout=300s
    fi
    
    # 删除ClusterIssuer
    kubectl delete clusterissuer "$CERT_ISSUER" 2>/dev/null || true
    
    # 询问是否删除cert-manager
    echo -e "${CYAN}是否同时删除cert-manager? (y/n):${NC}"
    read -r delete_certmanager
    
    if [[ "$delete_certmanager" =~ ^[Yy]$ ]]; then
        if kubectl get namespace cert-manager &>/dev/null; then
            log_info "删除cert-manager..."
            helm uninstall cert-manager -n cert-manager
            kubectl delete namespace cert-manager --timeout=300s
        fi
    fi
    
    # 询问是否删除配置文件
    echo -e "${CYAN}是否删除配置文件? (y/n):${NC}"
    read -r delete_config
    
    if [[ "$delete_config" =~ ^[Yy]$ ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            log_info "删除配置目录: $CONFIG_DIR"
            rm -rf "$CONFIG_DIR"
        fi
    fi
    
    log_success "清理完成!"
}

# 显示服务状态
show_service_status() {
    log_header "服务状态"
    
    if ! load_configuration; then
        log_error "配置文件不存在"
        return 0
    fi
    
    # 检查命名空间是否存在
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "命名空间 $NAMESPACE 不存在，可能尚未部署"
        return 0
    fi
    
    echo -e "${CYAN}=== Pod状态 ===${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo -e "\n${CYAN}=== 服务状态 ===${NC}"
    kubectl get services -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== Ingress状态 ===${NC}"
    kubectl get ingress -n "$NAMESPACE"
    
    echo -e "\n${CYAN}=== 证书状态 ===${NC}"
    kubectl get certificates -n "$NAMESPACE" 2>/dev/null || echo "无证书资源"
    
    echo -e "\n${CYAN}=== Helm部署状态 ===${NC}"
    helm list -n "$NAMESPACE"
}

# 主菜单
show_main_menu() {
    clear
    log_header "ESS Community 部署工具 (修复版)"
    echo ""
    echo "1) 配置部署参数"
    echo "2) 开始部署"
    echo "3) 查看当前配置"
    echo "4) 查看服务状态"
    echo "5) 创建用户"
    echo "6) 清理部署"
    echo "7) 退出"
    echo ""
    echo -e "${CYAN}请选择操作 [1-7]:${NC}"
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
    
    # 如果有参数，直接执行自动部署
    if [[ $# -gt 0 && "$1" == "auto" ]]; then
        log_header "自动部署模式"
        
        # 检查Kubernetes集群
        check_kubernetes_cluster || exit 1
        
        # 安装cert-manager
        install_cert_manager || exit 1
        
        # 配置收集
        collect_configuration
        
        # 生成配置文件
        generate_configuration_files
        
        # 部署ESS Community
        deploy_ess_community || exit 1
        
        # 验证部署
        verify_deployment
        
        # 显示访问信息
        show_access_information
        
        log_success "ESS Community自动部署完成!"
        return 0
    fi
    
    # 交互式菜单
    while true; do
        show_main_menu
        read -r choice
        
        case $choice in
            1)
                collect_configuration || true
                ;;
            2)
                if load_configuration; then
                    check_kubernetes_cluster || continue
                    install_cert_manager || continue
                    generate_configuration_files
                    deploy_ess_community || continue
                    verify_deployment
                    show_access_information
                else
                    log_error "请先配置部署参数"
                fi
                read -p "按回车键继续..."
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
                show_service_status
                read -p "按回车键继续..."
                ;;
            5)
                if load_configuration; then
                    create_initial_user
                else
                    log_error "请先完成部署"
                fi
                read -p "按回车键继续..."
                ;;
            6)
                cleanup_deployment
                read -p "按回车键继续..."
                ;;
            7)
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

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
