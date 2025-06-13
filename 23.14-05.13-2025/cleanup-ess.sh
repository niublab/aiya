#!/bin/bash

# ESS简单清理脚本

echo "清理ESS部署..."

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "需要root权限，请使用sudo运行"
    exit 1
fi

# 清理ESS
echo "1. 清理ESS部署..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm uninstall ess -n ess 2>/dev/null || true
kubectl delete namespace ess 2>/dev/null || true

# 清理K3s
echo "2. 清理K3s..."
systemctl stop k3s 2>/dev/null || true
/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
rm -rf /var/lib/rancher/k3s /etc/rancher/k3s ~/.kube

# 清理Nginx
echo "3. 清理Nginx配置..."
rm -f /etc/nginx/sites-enabled/matrix-ess
systemctl restart nginx 2>/dev/null || true

# 清理DNS凭据文件 (保留证书)
echo "4. 清理DNS凭据..."
rm -f /etc/letsencrypt/cloudflare.ini
rm -f /etc/letsencrypt/route53.ini
rm -f /etc/letsencrypt/digitalocean.ini

# 清理安装目录
echo "5. 清理安装目录..."
rm -rf /opt/matrix-ess

echo "清理完成！现在可以重新部署。"
echo "注意: SSL证书已保留，如需删除证书请手动运行:"
echo "sudo certbot delete --cert-name your-domain.com"
