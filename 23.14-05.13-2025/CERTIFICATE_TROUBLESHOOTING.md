# 🔧 Let's Encrypt证书问题排查指南

## 📋 常见证书申请失败原因

### 🔍 **问题诊断步骤**

#### **1. 查看详细错误日志**
```bash
# 查看最新的错误日志
tail -50 /var/log/letsencrypt/letsencrypt.log

# 查看特定域名的日志
grep "your-domain.com" /var/log/letsencrypt/letsencrypt.log

# 实时监控日志
tail -f /var/log/letsencrypt/letsencrypt.log
```

#### **2. 启用调试模式**
```bash
# 使用调试模式重新运行
DEBUG=true DOMAIN=your-domain.com \
CLOUDFLARE_API_TOKEN=your_token \
./deploy-ess-nginx-proxy.sh
```

#### **3. 手动测试证书申请**
```bash
# DNS验证dry-run测试
certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dry-run -d your-domain.com \
  --verbose

# HTTP验证dry-run测试
certbot certonly --standalone \
  --dry-run -d your-domain.com \
  --verbose
```

## 🌐 DNS验证问题排查

### **问题1: DNS插件安装失败**
```bash
# 症状
[ERROR] Cloudflare DNS插件安装失败

# 排查步骤
# 1. 检查包管理器
apt list --installed | grep certbot
yum list installed | grep certbot

# 2. 手动安装插件
apt update
apt install -y python3-certbot-dns-cloudflare

# 3. 验证插件
certbot plugins | grep dns-cloudflare

# 4. 备用安装方法
pip3 install certbot-dns-cloudflare
```

### **问题2: Cloudflare API连接失败**
```bash
# 症状
[ERROR] Cloudflare API连接失败

# 排查步骤
# 1. 测试API Token
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"

# 2. 检查Token权限
# 需要权限: Zone:Zone:Read, Zone:DNS:Edit

# 3. 检查Token格式
echo $CLOUDFLARE_API_TOKEN | wc -c
# 应该是40个字符左右

# 4. 重新生成Token
# 访问: https://dash.cloudflare.com/profile/api-tokens
```

### **问题3: DNS记录创建失败**
```bash
# 症状
Failed to create DNS record

# 排查步骤
# 1. 检查域名是否在Cloudflare管理
dig NS your-domain.com @8.8.8.8

# 2. 手动测试DNS记录创建
curl -X POST "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"type":"TXT","name":"_acme-challenge.test","content":"test123"}'

# 3. 检查现有DNS记录
dig TXT _acme-challenge.your-domain.com @8.8.8.8
```

### **问题4: DNS传播超时**
```bash
# 症状
DNS propagation timeout

# 排查步骤
# 1. 增加传播等待时间
certbot certonly --dns-cloudflare \
  --dns-cloudflare-propagation-seconds 120 \
  -d your-domain.com

# 2. 手动检查DNS传播
dig TXT _acme-challenge.your-domain.com @8.8.8.8
dig TXT _acme-challenge.your-domain.com @1.1.1.1

# 3. 使用在线工具检查
# https://www.whatsmydns.net/
```

## 🌍 HTTP验证问题排查

### **问题1: 80端口无法访问**
```bash
# 症状
Connection refused on port 80

# 排查步骤
# 1. 检查端口占用
netstat -tlnp | grep :80
ss -tlnp | grep :80

# 2. 检查防火墙
ufw status
iptables -L | grep 80

# 3. 检查服务状态
systemctl status nginx
systemctl status apache2

# 4. 临时开放端口
ufw allow 80/tcp
```

### **问题2: 域名解析错误**
```bash
# 症状
Domain not resolving to this server

# 排查步骤
# 1. 检查A记录
dig A your-domain.com @8.8.8.8

# 2. 检查服务器IP
curl -4 ifconfig.me
curl -6 ifconfig.me

# 3. 测试HTTP访问
curl -I http://your-domain.com/.well-known/acme-challenge/test

# 4. 检查CDN/代理
curl -H "Host: your-domain.com" http://SERVER_IP/
```

## 🔐 证书配置问题

### **问题1: 证书文件不存在**
```bash
# 症状
Certificate files not found

# 排查步骤
# 1. 检查证书目录
ls -la /etc/letsencrypt/live/your-domain.com/

# 2. 检查证书权限
ls -la /etc/letsencrypt/live/your-domain.com/fullchain.pem
ls -la /etc/letsencrypt/live/your-domain.com/privkey.pem

# 3. 重新生成证书
certbot delete --cert-name your-domain.com
# 然后重新申请
```

### **问题2: 证书权限问题**
```bash
# 症状
Permission denied accessing certificate

# 排查步骤
# 1. 修复权限
chmod 644 /etc/letsencrypt/live/your-domain.com/fullchain.pem
chmod 600 /etc/letsencrypt/live/your-domain.com/privkey.pem

# 2. 修复所有者
chown root:root /etc/letsencrypt/live/your-domain.com/*

# 3. 检查SELinux (如果适用)
getenforce
setsebool -P httpd_can_network_connect 1
```

## 🚨 速率限制问题

### **问题1: Let's Encrypt速率限制**
```bash
# 症状
Rate limit exceeded

# 解决方案
# 1. 使用Staging环境测试
export TEST_MODE="true"
export CERT_TYPE="letsencrypt-staging"

# 2. 等待速率限制重置
# 每周最多5次失败尝试
# 每小时最多5次重复申请

# 3. 检查现有证书
certbot certificates
```

## 🛠️ 高级排查技巧

### **完整的诊断脚本**
```bash
#!/bin/bash
# 证书问题诊断脚本

DOMAIN="your-domain.com"
API_TOKEN="your_cloudflare_token"

echo "=== 证书问题诊断 ==="

# 1. 检查域名解析
echo "1. 检查域名解析:"
dig A $DOMAIN @8.8.8.8
dig AAAA $DOMAIN @8.8.8.8

# 2. 检查NS记录
echo "2. 检查NS记录:"
dig NS $DOMAIN @8.8.8.8

# 3. 测试API连接
echo "3. 测试Cloudflare API:"
curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $API_TOKEN" | jq .success

# 4. 检查certbot插件
echo "4. 检查certbot插件:"
certbot plugins | grep dns

# 5. 检查现有证书
echo "5. 检查现有证书:"
certbot certificates

# 6. 测试80端口
echo "6. 测试80端口:"
nc -zv $DOMAIN 80

# 7. 检查防火墙
echo "7. 检查防火墙:"
ufw status

echo "=== 诊断完成 ==="
```

### **手动证书申请测试**
```bash
# 完整的手动测试流程
# 1. 清理旧证书
certbot delete --cert-name your-domain.com

# 2. 测试DNS验证
certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  --staging \
  --dry-run \
  --verbose \
  -d your-domain.com \
  -d app.your-domain.com

# 3. 如果测试成功，申请正式证书
certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  --verbose \
  -d your-domain.com \
  -d app.your-domain.com
```

## 📞 获取帮助

### **官方资源**
- [Let's Encrypt社区](https://community.letsencrypt.org)
- [Certbot文档](https://certbot.eff.org/docs/)
- [Cloudflare API文档](https://developers.cloudflare.com/api/)

### **常用命令参考**
```bash
# 查看certbot帮助
certbot --help
certbot --help dns-cloudflare

# 查看证书状态
certbot certificates
certbot show_account

# 测试证书续期
certbot renew --dry-run

# 删除证书
certbot delete --cert-name your-domain.com

# 撤销证书
certbot revoke --cert-path /etc/letsencrypt/live/your-domain.com/cert.pem
```

---

**提示**: 大多数证书申请问题都与DNS配置、API权限或网络连接有关。按照上述步骤逐一排查，通常能快速定位和解决问题。
