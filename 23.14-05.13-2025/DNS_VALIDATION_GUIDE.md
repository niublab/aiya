# 🌐 DNS验证SSL证书使用指南

## 📋 DNS验证概述

DNS验证是Let's Encrypt证书申请的一种方式，通过在DNS记录中添加特定的TXT记录来验证域名所有权。相比HTTP验证，DNS验证有以下优势：

### ✅ **DNS验证优势**
- **无需开放80端口**: 适合防火墙后的服务器
- **支持通配符证书**: 可以申请 `*.domain.com` 证书
- **更安全**: 不需要临时开放HTTP服务
- **适合内网**: 服务器无需公网HTTP访问
- **自动化**: 通过API自动管理DNS记录

### ❌ **DNS验证限制**
- **需要API访问**: 需要DNS提供商的API凭据
- **DNS传播延迟**: 需要等待DNS记录传播 (通常1-5分钟)
- **依赖DNS提供商**: 需要支持的DNS服务商

## 🚀 快速开始

### **Cloudflare DNS验证** (推荐)

#### **1. 获取API Token**
1. 访问 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. 点击 "Create Token"
3. 选择 "Custom token"
4. 配置权限:
   - **Zone** - `Zone:Read` - 所有区域
   - **Zone** - `DNS:Edit` - 所有区域 (或特定区域)
5. 复制生成的Token

#### **2. 使用DNS验证部署**
```bash
# 方法1: 环境变量方式
DOMAIN=matrix.example.com \
CERT_CHALLENGE=dns \
DNS_PROVIDER=cloudflare \
CLOUDFLARE_API_TOKEN=your_api_token_here \
AUTO_DEPLOY=3 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 方法2: 交互式配置
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
# 选择DNS验证，然后输入API Token
```

## 🔧 支持的DNS提供商

### **1. Cloudflare** (推荐)
```bash
# 环境变量
DNS_PROVIDER="cloudflare"
CLOUDFLARE_API_TOKEN="your_token"

# API Token权限要求
# Zone:Zone:Read (所有区域)
# Zone:DNS:Edit (所有区域或特定区域)
```

**优势**: 
- 免费DNS服务
- 快速DNS传播
- 强大的API
- 全球CDN

### **2. AWS Route53**
```bash
# 环境变量
DNS_PROVIDER="route53"
AWS_ACCESS_KEY_ID="your_access_key"
AWS_SECRET_ACCESS_KEY="your_secret_key"
AWS_DEFAULT_REGION="us-east-1"

# IAM权限要求
# route53:ListHostedZones
# route53:ChangeResourceRecordSets
# route53:GetChange
```

**优势**:
- AWS生态集成
- 高可用性
- 精确的权限控制

### **3. DigitalOcean**
```bash
# 环境变量
DNS_PROVIDER="digitalocean"
DO_API_TOKEN="your_do_token"

# API Token权限
# 需要读写DNS记录权限
```

**优势**:
- 简单易用
- 价格便宜
- 快速设置

## 📱 使用场景

### **场景1: 防火墙后的服务器**
```bash
# 服务器在企业防火墙后，无法开放80端口
DOMAIN=matrix.company.com \
CERT_CHALLENGE=dns \
DNS_PROVIDER=cloudflare \
CLOUDFLARE_API_TOKEN=xxx \
AUTO_DEPLOY=3 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **场景2: 家庭网络部署**
```bash
# 家庭路由器不想开放80端口
DOMAIN=home.example.com \
CERT_CHALLENGE=dns \
DNS_PROVIDER=cloudflare \
CLOUDFLARE_API_TOKEN=xxx \
AUTO_DEPLOY=3 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### **场景3: 云服务器标准部署**
```bash
# 云服务器，使用DNS验证更安全
DOMAIN=matrix.cloud.com \
CERT_CHALLENGE=dns \
DNS_PROVIDER=route53 \
AWS_ACCESS_KEY_ID=xxx \
AWS_SECRET_ACCESS_KEY=xxx \
AUTO_DEPLOY=3 \
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

## 🔐 安全最佳实践

### **API Token安全**
1. **最小权限原则**: 只授予必要的DNS权限
2. **定期轮换**: 定期更新API Token
3. **环境隔离**: 测试和生产使用不同的Token
4. **监控使用**: 监控API Token的使用情况

### **Cloudflare Token配置示例**
```
Token名称: Matrix ESS Certificate
权限:
- Zone:Zone:Read (所有区域)
- Zone:DNS:Edit (包含 example.com)
客户端IP限制: 服务器IP地址
TTL: 1年
```

### **AWS IAM策略示例**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ChangeResourceRecordSets",
                "route53:GetChange"
            ],
            "Resource": "*"
        }
    ]
}
```

## 🛠️ 手动DNS验证

如果自动DNS验证失败，可以手动验证：

### **1. 获取验证记录**
```bash
# 运行certbot获取验证信息
certbot certonly --manual --preferred-challenges dns \
  -d matrix.example.com \
  -d app.matrix.example.com \
  --dry-run
```

### **2. 添加DNS记录**
在DNS管理界面添加TXT记录：
```
名称: _acme-challenge.matrix.example.com
类型: TXT
值: (certbot提供的验证字符串)
TTL: 300
```

### **3. 验证DNS传播**
```bash
# 检查DNS记录是否生效
dig TXT _acme-challenge.matrix.example.com @8.8.8.8
nslookup -type=TXT _acme-challenge.matrix.example.com 8.8.8.8
```

## 🔍 故障排除

### **常见问题**

#### **1. API Token权限不足**
```
错误: 403 Forbidden
解决: 检查Token权限，确保包含Zone:DNS:Edit
```

#### **2. DNS传播延迟**
```
错误: DNS record not found
解决: 等待5-10分钟，DNS记录需要时间传播
```

#### **3. 域名不在DNS提供商管理**
```
错误: Zone not found
解决: 确保域名的NS记录指向正确的DNS服务商
```

#### **4. API配额限制**
```
错误: Rate limit exceeded
解决: 等待一段时间后重试，或联系DNS提供商
```

### **调试命令**
```bash
# 检查DNS记录
dig TXT _acme-challenge.your-domain.com @8.8.8.8

# 测试API连接 (Cloudflare)
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# 查看certbot详细日志
certbot --help dns-cloudflare
tail -f /var/log/letsencrypt/letsencrypt.log
```

## 📊 DNS验证 vs HTTP验证对比

| 特性 | DNS验证 | HTTP验证 |
|------|---------|----------|
| 端口要求 | 无 | 需要80端口 |
| 防火墙友好 | ✅ | ❌ |
| 通配符证书 | ✅ | ❌ |
| 设置复杂度 | 中等 | 简单 |
| API依赖 | ✅ | ❌ |
| 验证速度 | 较慢 (DNS传播) | 较快 |
| 安全性 | 高 | 中等 |
| 适用场景 | 生产环境 | 测试环境 |

## 🔄 证书自动续期

DNS验证的证书可以自动续期：

### **配置自动续期**
```bash
# 添加到crontab
echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -

# 或使用systemd timer
systemctl enable certbot.timer
systemctl start certbot.timer
```

### **续期测试**
```bash
# 测试续期
certbot renew --dry-run

# 强制续期
certbot renew --force-renewal
```

---

**推荐**: 对于生产环境，强烈建议使用DNS验证方式申请SSL证书，特别是当服务器位于防火墙后或使用非标准端口时。
