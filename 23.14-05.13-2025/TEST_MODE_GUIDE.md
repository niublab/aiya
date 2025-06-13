# 🧪 ESS-Helm测试模式使用指南

## 📋 测试模式概述

测试模式专为开发、测试和演示环境设计，提供快速部署选项，无需复杂的DNS配置和证书申请。

## 🎯 测试模式特点

### ✅ **优势**
- **快速部署**: 无需等待DNS传播和证书验证
- **无域名要求**: 可使用自签名证书，无需真实域名
- **开发友好**: 适合本地开发和内网测试
- **无速率限制**: Let's Encrypt Staging环境无申请限制
- **安全隔离**: 测试证书不会影响生产环境

### ⚠️ **限制**
- **浏览器警告**: 会显示"不安全"或"证书无效"警告
- **手动信任**: 需要手动添加证书信任
- **仅限测试**: 不适合生产环境使用

## 🚀 快速开始

### **方法1: 交互式测试部署**
```bash
# 运行安装程序，选择选项4
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **方法2: 自动测试部署**
```bash
# 使用Let's Encrypt Staging证书
DOMAIN=test.example.com AUTO_DEPLOY=4 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 使用自签名证书 (推荐内网测试)
DOMAIN=matrix.local TEST_MODE=true CERT_TYPE=self-signed AUTO_DEPLOY=4 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **方法3: 环境变量方式**
```bash
# 设置环境变量
export DOMAIN="test.matrix.local"
export TEST_MODE="true"
export CERT_TYPE="self-signed"
export AUTO_DEPLOY="test"

# 运行部署
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

## 🔧 证书类型选择

### **1. Let's Encrypt Staging证书**
```bash
CERT_TYPE="letsencrypt-staging"
```
- ✅ 真实的ACME协议验证
- ✅ 无申请速率限制
- ✅ 适合测试自动化流程
- ❌ 需要真实域名和DNS解析
- ❌ 浏览器显示不安全

### **2. 自签名证书** (推荐)
```bash
CERT_TYPE="self-signed"
```
- ✅ 无需域名解析
- ✅ 完全离线生成
- ✅ 适合内网和本地测试
- ✅ 支持多域名SAN
- ❌ 浏览器显示不安全

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

### **场景1: 本地开发测试**
```bash
# 使用本地域名
DOMAIN=matrix.local \
TEST_MODE=true \
CERT_TYPE=self-signed \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://matrix.local:8443 (需要添加hosts记录)
```

### **场景2: 内网演示环境**
```bash
# 使用内网IP或域名
DOMAIN=192.168.1.100 \
TEST_MODE=true \
CERT_TYPE=self-signed \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://192.168.1.100:8443
```

### **场景3: 云服务器测试**
```bash
# 使用测试域名
DOMAIN=test.yourdomain.com \
TEST_MODE=true \
CERT_TYPE=letsencrypt-staging \
AUTO_DEPLOY=test \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 访问地址
# https://test.yourdomain.com:8443
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

### **自签名证书配置**
```bash
# 在ess-config-template.env中配置
SELF_SIGNED_DAYS="365"           # 证书有效期
SELF_SIGNED_COUNTRY="CN"         # 国家
SELF_SIGNED_STATE="Beijing"      # 省份
SELF_SIGNED_CITY="Beijing"       # 城市
SELF_SIGNED_ORG="Test Matrix"    # 组织名称
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

# 手动生成自签名证书
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
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
# 添加hosts记录 (本地测试)
echo "127.0.0.1 matrix.local app.matrix.local mas.matrix.local" >> /etc/hosts

# 或使用IP地址访问
https://服务器IP:8443
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
