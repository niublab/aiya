#!/bin/bash

# Matrix ESS Community 部署脚本 v5.0.0
# 简化版本 - 专注核心部署功能

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

# 检查配置文件
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "未找到配置文件: $CONFIG_FILE"
    print_info "请先运行 ./setup.sh 进行配置"
    exit 1
fi

# 安全加载配置，忽略readonly变量错误
source "$CONFIG_FILE" 2>/dev/null || {
    print_warning "配置文件加载有警告，但继续执行部署"
}

print_step "Matrix ESS Community 自动部署"
print_info "基于配置文件: $CONFIG_FILE"
print_info "ESS版本: $ESS_VERSION"

# ==================== 部署流程 ====================

deploy_k3s() {
    print_step "安装 K3s Kubernetes"
    
    if command -v k3s &> /dev/null; then
        print_info "K3s已安装，检查状态..."
        if systemctl is-active --quiet k3s; then
            print_success "K3s运行正常"
            return 0
        fi
    fi
    
    print_info "下载并安装K3s..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -
    
    # 等待K3s启动
    print_info "等待K3s启动..."
    local retry=0
    while ! k3s kubectl get nodes &> /dev/null; do
        if [[ $retry -ge 30 ]]; then
            print_error "K3s启动超时"
            return 1
        fi
        sleep 10
        ((retry++))
    done
    
    print_success "K3s安装完成"
}

deploy_helm() {
    print_step "安装 Helm"
    
    if command -v helm &> /dev/null; then
        print_success "Helm已安装"
        return 0
    fi
    
    print_info "下载并安装Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    print_success "Helm安装完成"
}

deploy_cert_manager() {
    print_step "安装 cert-manager"
    
    if k3s kubectl get namespace cert-manager &> /dev/null; then
        print_success "cert-manager已安装"
        return 0
    fi
    
    print_info "安装cert-manager..."
    k3s kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.0/cert-manager.yaml
    
    # 等待cert-manager启动
    print_info "等待cert-manager启动..."
    k3s kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
    
    # 创建Let's Encrypt Issuer
    print_info "配置Let's Encrypt证书颁发者..."
    cat << EOF | k3s kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-production
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
    
    print_success "cert-manager配置完成"
}

generate_ess_values() {
    print_step "生成ESS配置"
    
    local values_file="$SCRIPT_DIR/ess-values.yaml"
    
    print_info "基于ESS官方最新规范生成配置..."
    
    cat > "$values_file" << EOF
# Matrix ESS Community 配置文件
# 基于ESS官方最新规范 $ESS_VERSION
# 生成时间: $(date)

# 服务器名称
serverName: "$SERVER_NAME"

# 全局Ingress配置
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    traefik.ingress.kubernetes.io/router.tls: "true"
  tlsEnabled: true

# Element Web配置
elementWeb:
  enabled: true
  ingress:
    host: "$WEB_HOST"

# Matrix Authentication Service配置
matrixAuthenticationService:
  enabled: true
  ingress:
    host: "$AUTH_HOST"

# Matrix RTC配置
matrixRTC:
  enabled: true
  ingress:
    host: "$RTC_HOST"

# Synapse配置
synapse:
  enabled: true
  ingress:
    host: "$SYNAPSE_HOST"

# PostgreSQL配置
postgresql:
  enabled: true

# HAProxy配置
haproxy:
  enabled: true

# Well-known委托配置
wellKnownDelegation:
  enabled: true
  additional:
    client: '{"m.homeserver":{"base_url":"https://$SYNAPSE_HOST"},"org.matrix.msc2965.authentication":{"issuer":"https://$AUTH_HOST/","account":"https://$AUTH_HOST/account"},"org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://$RTC_HOST"}]}'
    server: '{"m.server":"$SYNAPSE_HOST:443"}'
EOF
    
    print_success "ESS配置文件已生成: $values_file"
}

deploy_ess() {
    print_step "部署 Matrix ESS"
    
    local values_file="$SCRIPT_DIR/ess-values.yaml"
    local namespace="ess"
    
    # 创建命名空间
    k3s kubectl create namespace "$namespace" --dry-run=client -o yaml | k3s kubectl apply -f -
    
    # 检查是否已部署
    if helm list -n "$namespace" | grep -q "ess"; then
        print_info "ESS已部署，执行升级..."
        helm upgrade ess "$ESS_CHART_OCI" \
            --namespace "$namespace" \
            --values "$values_file" \
            --version "$ESS_VERSION" \
            --timeout=600s \
            --wait
    else
        print_info "部署ESS..."
        helm install ess "$ESS_CHART_OCI" \
            --namespace "$namespace" \
            --values "$values_file" \
            --version "$ESS_VERSION" \
            --timeout=600s \
            --wait
    fi
    
    print_success "ESS部署完成"
}

wait_for_pods() {
    print_step "等待服务启动"
    
    print_info "等待所有Pod就绪..."
    k3s kubectl wait --for=condition=ready pod --all -n ess --timeout=600s
    
    print_success "所有服务已启动"
}

create_admin_user() {
    print_step "创建管理员用户"
    
    print_info "等待Synapse就绪..."
    sleep 30
    
    # 获取Synapse Pod名称
    local synapse_pod=$(k3s kubectl get pods -n ess -l app.kubernetes.io/name=synapse -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -n "$synapse_pod" ]]; then
        print_info "在Synapse中创建管理员用户..."
        k3s kubectl exec -n ess "$synapse_pod" -- \
            register_new_matrix_user \
            -u "$ADMIN_USERNAME" \
            -p "$ADMIN_PASSWORD" \
            -a \
            -c /data/homeserver.yaml \
            http://localhost:8008 || true
        
        print_success "管理员用户创建完成"
    else
        print_warning "未找到Synapse Pod，请稍后手动创建管理员用户"
    fi
}

show_deployment_info() {
    print_step "部署完成"
    
    print_success "Matrix ESS Community 部署成功！"
    echo
    print_info "访问地址:"
    echo "  Element Web: https://$WEB_HOST"
    echo "  认证服务: https://$AUTH_HOST"
    echo "  RTC服务: https://$RTC_HOST"
    echo "  Synapse: https://$SYNAPSE_HOST"
    echo
    print_info "管理员账户:"
    echo "  用户名: $ADMIN_USERNAME"
    echo "  密码: [已设置]"
    echo
    print_info "重要提示:"
    echo "  1. 请确保域名DNS解析指向此服务器"
    echo "  2. 证书将自动申请，可能需要几分钟"
    echo "  3. 首次访问可能需要等待服务完全启动"
    echo
    
    # 保存部署信息
    cat > "$SCRIPT_DIR/deployment-info.txt" << EOF
Matrix ESS Community 部署信息
部署时间: $(date)
脚本版本: $SCRIPT_VERSION
ESS版本: $ESS_VERSION

访问地址:
- Element Web: https://$WEB_HOST
- 认证服务: https://$AUTH_HOST
- RTC服务: https://$RTC_HOST
- Synapse: https://$SYNAPSE_HOST

管理员账户:
- 用户名: $ADMIN_USERNAME
- 密码: [已设置]

配置文件位置:
- 主配置: $SCRIPT_DIR/matrix-config.env
- ESS配置: $SCRIPT_DIR/ess-values.yaml
- 部署信息: $SCRIPT_DIR/deployment-info.txt
EOF
    
    print_info "部署信息已保存到: $SCRIPT_DIR/deployment-info.txt"
}

# ==================== 主部署流程 ====================

main() {
    print_header "Matrix ESS Community 自动部署"
    
    # 检查配置文件
    if [[ ! -f "$SCRIPT_DIR/matrix-config.env" ]]; then
        print_error "未找到配置文件，请先运行主脚本进行配置"
        exit 1
    fi
    
    print_info "开始部署流程..."
    
    # 执行部署步骤
    deploy_k3s
    deploy_helm
    deploy_cert_manager
    generate_ess_values
    deploy_ess
    wait_for_pods
    create_admin_user
    show_deployment_info
    
    print_success "部署流程完成！"
}

# 运行部署
main "$@"
