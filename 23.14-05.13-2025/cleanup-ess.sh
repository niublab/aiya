#!/bin/bash

# ESS部署完全清理脚本
# 清理所有ESS相关组件，准备重新部署

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
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本需要root权限运行"
    exit 1
fi

print_warning "=== ESS部署完全清理 ==="
print_warning "这将删除所有ESS相关组件和数据！"
echo
print_info "将要清理的组件:"
echo "- ESS Helm部署和数据"
echo "- K3s Kubernetes集群"
echo "- Nginx ESS配置"
echo "- SSL证书 (可选)"
echo "- 安装目录和配置文件"
echo

read -p "确定要继续清理吗? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "取消清理"
    exit 0
fi

# 获取域名 (用于清理证书)
DOMAIN="${DOMAIN:-}"
if [[ -z "$DOMAIN" ]]; then
    read -p "请输入域名 (用于清理证书，留空跳过): " DOMAIN
fi

print_info "开始清理..."

# 1. 清理ESS Helm部署
print_info "1. 清理ESS Helm部署..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if kubectl get nodes &>/dev/null 2>&1; then
    # 删除ESS部署
    if helm list -n ess 2>/dev/null | grep -q ess; then
        print_info "删除ESS Helm部署..."
        helm uninstall ess -n ess || true
    fi
    
    # 删除命名空间
    if kubectl get namespace ess &>/dev/null 2>&1; then
        print_info "删除ESS命名空间..."
        kubectl delete namespace ess --timeout=60s || true
    fi
    
    # 清理PVC
    kubectl get pvc -A 2>/dev/null | grep ess | awk '{print $1 " " $2}' | while read ns pvc; do
        kubectl delete pvc "$pvc" -n "$ns" || true
    done 2>/dev/null || true
    
    print_success "ESS部署清理完成"
else
    print_warning "无法连接K3s，跳过ESS清理"
fi

# 2. 清理K3s集群
print_info "2. 清理K3s集群..."

# 停止K3s服务
systemctl stop k3s 2>/dev/null || true
systemctl disable k3s 2>/dev/null || true

# 运行K3s卸载脚本
if [[ -f "/usr/local/bin/k3s-uninstall.sh" ]]; then
    print_info "运行K3s卸载脚本..."
    /usr/local/bin/k3s-uninstall.sh || true
fi

# 清理K3s文件
print_info "清理K3s文件和目录..."
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s
rm -rf /var/lib/kubelet
rm -rf /var/lib/cni
rm -rf /opt/cni
rm -rf /run/k3s
rm -rf ~/.kube

# 清理网络接口
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true

print_success "K3s集群清理完成"

# 3. 清理Nginx配置
print_info "3. 清理Nginx配置..."

# 停止Nginx
systemctl stop nginx 2>/dev/null || true

# 删除ESS配置
rm -f /etc/nginx/sites-available/matrix-ess
rm -f /etc/nginx/sites-enabled/matrix-ess

# 恢复默认站点
if [[ -f "/etc/nginx/sites-available/default" ]]; then
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

# 重启Nginx
if nginx -t 2>/dev/null; then
    systemctl start nginx || true
fi

print_success "Nginx配置清理完成"

# 4. 清理SSL证书 (可选)
if [[ -n "$DOMAIN" && "$DOMAIN" != "your-domain.com" ]]; then
    print_info "4. 清理SSL证书..."
    
    # 删除Let's Encrypt证书
    if command -v certbot &>/dev/null && certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
        print_info "删除Let's Encrypt证书: $DOMAIN"
        certbot delete --cert-name "$DOMAIN" || true
    fi
    
    # 清理证书目录
    rm -rf "/etc/letsencrypt/live/$DOMAIN"
    rm -rf "/etc/letsencrypt/archive/$DOMAIN"
    rm -rf "/etc/letsencrypt/renewal/$DOMAIN.conf"
    
    print_success "SSL证书清理完成"
else
    print_info "4. 跳过SSL证书清理"
fi

# 5. 清理DNS验证凭据
print_info "5. 清理DNS验证凭据..."
rm -f /etc/letsencrypt/cloudflare.ini
rm -f /etc/letsencrypt/route53.ini
rm -f /etc/letsencrypt/digitalocean.ini

# 6. 清理安装目录
print_info "6. 清理安装目录..."
rm -rf /opt/matrix-ess

# 7. 清理配置文件 (当前目录)
print_info "7. 清理配置文件..."
rm -f ess-config-template.env
rm -f ess-values.yaml
rm -f nginx.conf.template

# 8. 清理防火墙规则 (可选)
read -p "是否重置防火墙规则? [y/N]: " reset_fw
if [[ "$reset_fw" =~ ^[Yy]$ ]]; then
    print_info "8. 重置防火墙规则..."
    ufw --force reset || true
    ufw --force enable || true
    print_success "防火墙规则已重置"
else
    print_info "8. 跳过防火墙重置"
fi

print_success "=== 清理完成 ==="
print_info "所有ESS组件已清理完毕"
print_info "现在可以重新运行部署脚本"
echo
print_info "重新部署命令示例:"
echo "DOMAIN=your-domain.com CLOUDFLARE_API_TOKEN=your_token AUTO_DEPLOY=3 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)"
