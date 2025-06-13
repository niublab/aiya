# 🧪 ESS-Helm测试模式使用指南

## 📋 测试模式概述

测试模式专为开发、测试和演示环境设计，使用Let's Encrypt Staging证书，提供快速部署选项。

## 🎯 测试模式特点

### ✅ **优势**
- **无速率限制**: Let's Encrypt Staging环境无申请限制
- **真实ACME流程**: 完整的证书申请流程测试
- **快速部署**: 适合开发和测试环境
- **安全隔离**: 测试证书不会影响生产环境配额
- **DNS验证支持**: 支持DNS和HTTP验证方式

### ⚠️ **限制**
- **浏览器警告**: 会显示"不安全"或"证书无效"警告
- **需要域名解析**: 必须有有效的域名解析
- **仅限测试**: 不适合生产环境使用

## 🚀 快速开始

### **方法1: 交互式测试部署**
```bash
# 运行安装程序，选择选项4
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **方法2: 自动测试部署**
```bash
# 使用Let's Encrypt Staging证书 (DNS验证)
DOMAIN=test.example.com \
CERT_CHALLENGE=dns \
CLOUDFLARE_API_TOKEN=your_token \
AUTO_DEPLOY=4 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 使用Let's Encrypt Staging证书 (HTTP验证)
DOMAIN=test.example.com \
CERT_CHALLENGE=http \
AUTO_DEPLOY=4 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **方法3: 环境变量方式**
```bash
# 设置环境变量
export DOMAIN="test.example.com"
export TEST_MODE="true"
export CERT_TYPE="letsencrypt-staging"
export CERT_CHALLENGE="dns"
export CLOUDFLARE_API_TOKEN="your_token"
export AUTO_DEPLOY="test"

# 运行部署
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

## 🔧 证书验证方式选择

### **1. DNS验证** (推荐)
```bash
CERT_CHALLENGE="dns"
DNS_PROVIDER="cloudflare"
CLOUDFLARE_API_TOKEN="your_token"
```
- ✅ 无需开放80端口
- ✅ 适合防火墙后的服务器
- ✅ 支持通配符证书
- ✅ 更安全的验证方式
- ❌ 需要DNS API凭据

### **2. HTTP验证**
```bash
CERT_CHALLENGE="http"
```
- ✅ 配置简单
- ✅ 无需API凭据
- ❌ 需要开放80端口
- ❌ 需要公网HTTP访问

### **3. 自定义证书**
```bash
CERT_TYPE="custom"
CUSTOM_CERT_PATH="/path/to/your.crt"
CUSTOM_KEY_PATH="/path/to/your.key"
```
- ✅ 使用现有证书
- ✅ 完全控制证书内容
- ❌ 需要手动管理证书

## 📱 使用场景

### **场景1: 开发环境测试**
```bash
# 使用开发域名 (DNS验证)
DOMAIN=dev.example.com \
TEST_MODE=true \
CERT_CHALLENGE=dns \
CLOUDFLARE_API_TOKEN=your_token \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://dev.example.com:8443
```

### **场景2: 内网测试环境**
```bash
# 使用内网域名 (HTTP验证)
DOMAIN=test.internal.com \
TEST_MODE=true \
CERT_CHALLENGE=http \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://test.internal.com:8443
```

### **场景3: 云服务器测试**
```bash
# 使用测试域名 (DNS验证推荐)
DOMAIN=staging.yourdomain.com \
TEST_MODE=true \
CERT_CHALLENGE=dns \
DNS_PROVIDER=cloudflare \
CLOUDFLARE_API_TOKEN=your_token \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://staging.yourdomain.com:8443
```

## 🔐 浏览器证书信任

### **Chrome浏览器**
1. 访问 `https://your-domain:8443`
2. 点击"高级"
3. 点击"继续前往 your-domain (不安全)"
4. 或者导入证书到"受信任的根证书颁发机构"

### **Firefox浏览器**
1. 访问 `https://your-domain:8443`
2. 点击"高级"
3. 点击"添加例外"
4. 点击"确认安全例外"

### **导入证书 (推荐)**
```bash
# 导出证书
openssl x509 -in /etc/letsencrypt/live/your-domain/fullchain.pem -out matrix-cert.crt

# Windows: 双击证书文件，安装到"受信任的根证书颁发机构"
# macOS: 双击证书文件，添加到钥匙串并设为"始终信任"
# Linux: 复制到 /usr/local/share/ca-certificates/ 并运行 update-ca-certificates
```

## 🛠️ 配置自定义

### **Let's Encrypt Staging配置**
```bash
# 在ess-config-template.env中配置
TEST_MODE="true"                 # 启用测试模式
CERT_TYPE="letsencrypt-staging"  # 使用Staging证书
CERT_CHALLENGE="dns"             # 验证方式
DNS_PROVIDER="cloudflare"        # DNS提供商
CLOUDFLARE_API_TOKEN="your_token" # API凭据
```

### **测试环境优化**
```bash
# 禁用不必要的功能
ENABLE_FEDERATION="false"        # 关闭联邦功能
ENABLE_REGISTRATION="true"       # 允许用户注册 (测试用)
ENABLE_GUEST_ACCESS="true"       # 允许访客访问
ENABLE_METRICS="false"           # 关闭监控 (节省资源)
```

## 🔍 故障排除

### **常见问题**

#### **1. 证书生成失败**
```bash
# 检查域名配置
./check-config.sh

# 检查DNS API凭据
echo $CLOUDFLARE_API_TOKEN

# 手动测试DNS验证
certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --staging -d test.example.com --dry-run
```

#### **2. 浏览器无法访问**
```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 8443/tcp

# 检查服务状态
systemctl status nginx
kubectl get pods -n ess
```

#### **3. 域名解析问题**
```bash
# 检查域名解析
dig test.example.com @8.8.8.8
nslookup test.example.com

# 检查DNS API权限
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```

## 📊 测试验证

### **功能测试清单**
- [ ] 网站可以访问 (忽略证书警告)
- [ ] Element Web客户端加载正常
- [ ] 可以创建用户账号
- [ ] 可以创建和加入房间
- [ ] 消息发送和接收正常
- [ ] 文件上传下载正常
- [ ] 视频通话功能正常 (如果启用)

### **性能测试**
```bash
# 检查资源使用
kubectl top pods -n ess
docker stats

# 检查响应时间
curl -w "@curl-format.txt" -o /dev/null -s https://your-domain:8443
```

## 🔄 从测试转生产

### **升级到生产证书**
```bash
# 方法1: 重新部署
DOMAIN=your-real-domain.com \
CERT_TYPE=letsencrypt \
AUTO_DEPLOY=3 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 方法2: 手动更新证书
certbot certonly --nginx -d your-real-domain.com -d app.your-real-domain.com
systemctl reload nginx
```

### **数据迁移**
```bash
# 备份数据
kubectl exec -n ess deployment/ess-synapse -- pg_dump synapse > synapse_backup.sql

# 恢复到新环境
kubectl exec -n ess deployment/ess-synapse -- psql synapse < synapse_backup.sql
```

---

**注意**: 测试模式仅用于开发、测试和演示目的。生产环境请使用正式的Let's Encrypt证书或购买的SSL证书。
