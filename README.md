# Matrix ESS Community 自动部署脚本

🚀 **一键部署 Matrix Element Server Suite (ESS) Community 版本的专业自动化脚本**

基于实际生产环境部署经验，经过完整测试验证，确保部署成功和服务稳定运行。

## ✨ 功能特性

- 🎯 **一键部署**: 全自动安装配置，无需手动干预
- 🔧 **智能修复**: 自动检测并修复常见配置问题
- 🔒 **SSL证书**: 自动申请配置 Let's Encrypt 证书
- 🌐 **域名支持**: 灵活的域名和端口配置方案
- 📊 **实时监控**: 详细的部署进度和状态显示
- 🛠️ **完整管理**: 内置服务管理和故障诊断工具
- 🔄 **容错设计**: 部分失败不影响整体部署
- 🎛️ **端口自定义**: 支持自定义所有网络端口

## 📋 系统要求

### 硬件配置
| 组件 | 最低要求 | 推荐配置 |
|------|----------|----------|
| **CPU** | 2核心 | 4核心+ |
| **内存** | 4GB RAM | 8GB+ RAM |
| **存储** | 20GB | 50GB+ SSD |
| **网络** | 100Mbps | 1Gbps+ |

### 系统环境
- **操作系统**: Ubuntu 22.04 LTS 或更新版本
- **权限**: root 用户权限
- **网络**: 稳定的互联网连接
- **域名**: 已配置DNS解析的域名

### 网络端口
| 协议 | 端口 | 用途 | 是否必需 |
|------|------|------|----------|
| TCP | 8080 | HTTP访问 | ✅ 必需 |
| TCP | 8443 | HTTPS访问 | ✅ 必需 |
| TCP | 8448 | Matrix联邦 | ✅ 必需 |
| UDP | 30152-30352 | RTC音视频 | ✅ 必需 |
| TCP | 30080/30443/30448 | NodePort备用 | 🔄 备用 |

## 🚀 快速部署

### 1️⃣ 准备工作

**必需准备：**
- ✅ 已配置DNS解析的域名
- ✅ Cloudflare API Token ([获取方法](https://developers.cloudflare.com/api/tokens/create/))
- ✅ 服务器root访问权限
- ✅ 防火墙已开放必需端口

### 2️⃣ 一键部署

```bash
# 下载并运行最新版本脚本
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
```

### 3️⃣ 配置向导

脚本将引导您完成：

1. **域名配置**
   - 主域名设置
   - 子域名配置
   - DNS验证

2. **SSL证书配置**
   - Cloudflare API Token
   - 证书环境选择
   - 邮箱地址设置

3. **网络配置**
   - 端口自定义
   - NodePort配置
   - UDP端口范围

4. **管理员账户**
   - 用户名设置
   - 密码生成
   - 权限配置

### 4️⃣ 访问服务

部署完成后访问地址：

| 服务 | 默认地址 | 用途 |
|------|----------|------|
| **Element Web** | https://app.yourdomain.com:8443 | 主要聊天界面 |
| **认证服务** | https://mas.yourdomain.com:8443 | 账户管理 |
| **RTC服务** | https://rtc.yourdomain.com:8443 | 音视频通话 |
| **Synapse** | https://matrix.yourdomain.com:8443 | Matrix服务器 |

## ⚙️ 高级配置

### 域名配置方案

#### 方案1: 子域名模式 (推荐)
```
主域名: example.com
├── app.example.com     (Element Web)
├── mas.example.com     (认证服务)
├── rtc.example.com     (RTC服务)
└── matrix.example.com  (Synapse)
```

#### 方案2: 端口模式
```
主域名: example.com
├── example.com:8443    (所有HTTPS服务)
├── example.com:8080    (所有HTTP服务)
└── example.com:8448    (联邦服务)
```

### 端口自定义

脚本支持完全自定义所有端口：

```bash
# 应用端口 (用户访问)
HTTP端口: 8080 (可自定义)
HTTPS端口: 8443 (可自定义)
联邦端口: 8448 (可自定义)

# NodePort端口 (Kubernetes内部)
HTTP NodePort: 30080 (可自定义 30000-32767)
HTTPS NodePort: 30443 (可自定义 30000-32767)
联邦NodePort: 30448 (可自定义 30000-32767)

# UDP端口范围 (音视频通话)
UDP范围: 30152-30352 (可自定义)
```

### SSL证书环境

| 环境 | 用途 | 特点 |
|------|------|------|
| **staging** | 测试环境 | 无速率限制，测试证书 |
| **production** | 生产环境 | 有速率限制，正式证书 |

## 🛠️ 服务管理

### 重新运行管理界面
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
```

### 常用管理命令

#### 用户管理
```bash
# 创建新用户
kubectl exec -n ess -it deployment/ess-matrix-authentication-service -- mas-cli manage register-user

# 查看用户列表
kubectl exec -n ess -it deployment/ess-matrix-authentication-service -- mas-cli manage list-users
```

#### 服务状态
```bash
# 查看所有Pod状态
kubectl get pods -n ess

# 查看服务状态
kubectl get services -n ess

# 查看Ingress状态
kubectl get ingress -n ess

# 查看证书状态
kubectl get certificates -n ess
```

#### 日志查看
```bash
# 查看Element Web日志
kubectl logs -n ess deployment/ess-element-web

# 查看认证服务日志
kubectl logs -n ess deployment/ess-matrix-authentication-service

# 查看Synapse日志
kubectl logs -n ess ess-synapse-main-0

# 查看所有事件
kubectl get events -n ess --sort-by='.lastTimestamp'
```

#### 服务重启
```bash
# 重启Element Web
kubectl rollout restart deployment ess-element-web -n ess

# 重启认证服务
kubectl rollout restart deployment ess-matrix-authentication-service -n ess

# 重启所有服务
kubectl rollout restart deployment -n ess
```

## 🔧 故障排除

### 常见问题及解决方案

#### 1. 无法访问服务
**症状**: 浏览器无法打开Matrix服务地址

**排查步骤**:
```bash
# 1. 检查Pod状态
kubectl get pods -n ess

# 2. 检查端口监听
netstat -tuln | grep -E ':(8080|8443|30080|30443)'

# 3. 检查防火墙
# 确保已开放: 8080, 8443, 8448, 30152-30352

# 4. 检查DNS解析
nslookup app.yourdomain.com
```

**解决方案**:
- 确保防火墙已开放必需端口
- 验证DNS解析正确
- 检查端口转发服务状态: `systemctl status matrix-port-forward`

#### 2. SSL证书申请失败
**症状**: 网站显示证书错误或无法申请证书

**排查步骤**:
```bash
# 1. 检查证书状态
kubectl get certificates -n ess

# 2. 查看证书申请详情
kubectl describe certificates -n ess

# 3. 检查cert-manager日志
kubectl logs -n cert-manager deployment/cert-manager
```

**解决方案**:
- 验证Cloudflare API Token权限
- 确认域名DNS设置正确
- 检查ClusterIssuer状态: `kubectl get clusterissuer`

#### 3. Element Web无法登录
**症状**: 显示"无法连接到homeserver"

**排查步骤**:
```bash
# 1. 检查MAS配置
kubectl get configmap ess-matrix-authentication-service -n ess -o yaml

# 2. 测试OpenID配置
curl -k https://mas.yourdomain.com:8443/.well-known/openid-configuration

# 3. 检查Well-known配置
curl -k https://yourdomain.com:8443/.well-known/matrix/client
```

**解决方案**:
- 脚本会自动修复MAS配置端口问题
- 如仍有问题，重新运行脚本选择"修复配置"

#### 4. 音视频通话无法连接
**症状**: 无法进行语音或视频通话

**排查步骤**:
```bash
# 1. 检查RTC服务状态
kubectl get pods -n ess | grep rtc

# 2. 检查UDP端口
netstat -uln | grep -E ':(30152|30882)'

# 3. 测试RTC服务
curl -k https://rtc.yourdomain.com:8443
```

**解决方案**:
- 确保UDP端口范围已在防火墙开放
- 检查网络环境是否支持UDP通信
- 验证RTC服务配置

### 诊断工具

#### 自动诊断脚本
```bash
# 运行完整系统诊断
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
# 选择: 3) 服务管理 -> 4) 系统诊断
```

#### 手动诊断命令
```bash
# 系统资源检查
df -h                    # 磁盘空间
free -h                  # 内存使用
top                      # CPU使用

# 网络连通性检查
ping google.com          # 外网连通性
curl -I https://ghcr.io  # 容器仓库连通性

# Kubernetes集群状态
kubectl cluster-info     # 集群信息
kubectl get nodes        # 节点状态
kubectl get namespaces   # 命名空间列表
```

## 📈 性能优化

### 系统优化
```bash
# 调整系统参数
echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
echo 'fs.file-max=65536' >> /etc/sysctl.conf
sysctl -p

# 优化网络参数
echo 'net.core.rmem_max=134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' >> /etc/sysctl.conf
```

### 资源监控
```bash
# 监控Pod资源使用
kubectl top pods -n ess

# 监控节点资源
kubectl top nodes

# 查看资源限制
kubectl describe pods -n ess | grep -A5 "Limits\|Requests"
```

## 🔄 备份与恢复

### 数据备份
```bash
# 备份PostgreSQL数据
kubectl exec -n ess ess-postgres-0 -- pg_dumpall -U postgres > backup.sql

# 备份配置文件
tar -czf matrix-config-backup.tar.gz /opt/matrix/

# 备份Kubernetes配置
kubectl get all -n ess -o yaml > ess-backup.yaml
```

### 恢复数据
```bash
# 恢复PostgreSQL数据
kubectl exec -i -n ess ess-postgres-0 -- psql -U postgres < backup.sql

# 恢复配置文件
tar -xzf matrix-config-backup.tar.gz -C /

# 重新部署服务
kubectl apply -f ess-backup.yaml
```

## 🆙 升级指南

### ESS版本升级
```bash
# 1. 备份当前配置
kubectl get all -n ess -o yaml > ess-backup.yaml

# 2. 更新Helm Chart
helm upgrade ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
  --namespace ess \
  --values /opt/matrix/ess-values.yaml \
  --version NEW_VERSION

# 3. 验证升级
kubectl get pods -n ess
```

### 系统组件升级
```bash
# 重新运行脚本进行升级
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
# 选择: 2) 升级组件
```

## 📊 组件版本

| 组件 | 版本 | 说明 |
|------|------|------|
| **Matrix ESS** | 25.6.1 | Element Server Suite |
| **K3s** | v1.32.5+k3s1 | 轻量级Kubernetes |
| **Helm** | v3.18.2 | Kubernetes包管理器 |
| **cert-manager** | v1.18.0 | 证书管理器 |
| **Traefik** | 3.3.6 | 反向代理和负载均衡 |

## 🔒 安全最佳实践

### 系统安全
- ✅ 定期更新系统: `apt update && apt upgrade`
- ✅ 使用强密码策略
- ✅ 限制SSH访问
- ✅ 配置防火墙规则
- ✅ 启用自动安全更新

### Matrix安全
- ✅ 使用生产环境SSL证书
- ✅ 定期更新ESS版本
- ✅ 监控异常登录
- ✅ 配置房间权限
- ✅ 限制联邦服务器

## 🤝 社区支持

### 获取帮助
- 📖 **官方文档**: [Element Server Suite文档](https://element-hq.github.io/ess-docs/)
- 💬 **Matrix房间**: [#ess-community:element.io](https://matrix.to/#/#ess-community:element.io)
- 🐛 **问题反馈**: [GitHub Issues](https://github.com/niublab/aiya/issues)

### 贡献指南
欢迎提交：
- 🐛 Bug报告
- 💡 功能建议  
- 📝 文档改进
- 🔧 代码贡献

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

---

**🎉 享受您的私有Matrix服务器！**

> 💡 **提示**: 首次部署建议使用staging证书环境进行测试，确认一切正常后再切换到production环境。
