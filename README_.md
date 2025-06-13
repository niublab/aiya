# Matrix ESS Community 自动部署脚本

一键部署 Matrix Element Server Suite (ESS) Community 版本的自动化脚本，支持内网和公网部署。

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
```

### 自定义仓库安装

如果您使用的是 fork 或其他仓库，只需修改仓库路径：

```bash
# 替换 YOUR_USERNAME/YOUR_REPO 为您的仓库路径
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/setup.sh)
```

脚本会自动检测源仓库，无需修改脚本内容。

## 📋 系统要求

- **操作系统**: Debian 11+ 或 Ubuntu 20.04+
- **内存**: 最低 2GB，推荐 4GB+
- **CPU**: 最低 2 核，推荐 4 核+
- **存储**: 最低 20GB 可用空间
- **网络**: 稳定的互联网连接
- **权限**: root 权限

## 🌐 网络配置

### 标准端口部署 (推荐)

如果您的 ISP 支持标准端口：

**路由器端口转发配置：**
- `80 → 30080` (HTTP)
- `443 → 30443` (HTTPS)
- `8448 → 30448` (Matrix 联邦)

### 非标准端口部署

如果您的 ISP 封锁了 80/443 端口，需要额外配置 DNS SRV 记录。

#### DNS SRV 记录配置

在您的 DNS 提供商（如 Cloudflare）中添加以下 SRV 记录：

**1. Matrix 客户端发现记录：**
- **类型**: `SRV`
- **名称**: `_matrix._tcp`
- **目标**: `matrix.${SERVER_NAME}` (例如: `matrix.example.com`)
- **端口**: `${HTTPS_PORT}` (例如: `8443`)
- **优先级**: `10`
- **权重**: `5`

**2. Matrix 联邦发现记录：**
- **类型**: `SRV`
- **名称**: `_matrix._tcp`
- **目标**: `matrix.${SERVER_NAME}` (例如: `matrix.example.com`)
- **端口**: `${FEDERATION_PORT}` (例如: `8448`)
- **优先级**: `10`
- **权重**: `5`

#### Cloudflare 配置示例

假设您的域名是 `example.com`，HTTPS 端口是 `8443`，联邦端口是 `8448`：

```
类型: SRV
名称: _matrix._tcp
目标: matrix.example.com
端口: 8443
优先级: 10
权重: 5

类型: SRV  
名称: _matrix._tcp
目标: matrix.example.com
端口: 8448
优先级: 10
权重: 5
```

**注意**: 两条记录的名称相同，但端口不同。一个用于客户端连接，一个用于服务器联邦。

### 路由器端口转发

无论使用哪种端口配置，都需要在路由器中设置端口转发：

```
外部端口 → 内部端口 (NodePort)
${HTTP_PORT} → 30080
${HTTPS_PORT} → 30443  
${FEDERATION_PORT} → 30448
```

## 🔧 功能特性

- ✅ **一键部署**: 全自动安装和配置
- ✅ **K3s 集群**: 轻量级 Kubernetes 环境
- ✅ **SSL 证书**: 自动申请 Let's Encrypt 证书
- ✅ **DNS 验证**: 支持 Cloudflare DNS 验证
- ✅ **多端口支持**: 支持标准和非标准端口
- ✅ **配置修复**: 自动修复常见配置问题
- ✅ **用户管理**: 自动创建管理员用户
- ✅ **健康检查**: 全面的服务状态检查
- ✅ **更新管理**: 支持脚本和服务更新
- ✅ **备份恢复**: 数据备份和恢复功能

## 📦 包含组件

- **Matrix Synapse**: Matrix 协议服务器
- **Element Web**: Web 客户端界面
- **Matrix Authentication Service (MAS)**: 认证服务
- **Matrix RTC**: 实时通信服务
- **PostgreSQL**: 数据库
- **HAProxy**: 负载均衡器
- **cert-manager**: 证书管理
- **Traefik**: 入口控制器

## 🎯 部署流程

1. **环境检查**: 验证系统要求和网络连接
2. **依赖安装**: 安装必要的系统软件包
3. **配置收集**: 交互式收集部署配置
4. **K3s 安装**: 部署轻量级 Kubernetes
5. **Helm 安装**: 安装包管理器
6. **cert-manager**: 配置证书管理
7. **ESS 部署**: 部署 Matrix 服务套件
8. **配置修复**: 自动修复端口和路由配置
9. **用户创建**: 创建管理员用户
10. **健康检查**: 验证所有服务状态

## 🔐 安全配置

### SSL 证书

脚本支持两种证书环境：

- **生产环境** (推荐): Let's Encrypt 正式证书，被所有浏览器信任
- **测试环境**: Let's Encrypt 测试证书，仅用于测试

### Cloudflare API Token

需要具有以下权限的 Cloudflare API Token：

- **Zone:Zone:Read**
- **Zone:DNS:Edit**

创建步骤：
1. 登录 Cloudflare Dashboard
2. 进入 "My Profile" → "API Tokens"
3. 点击 "Create Token"
4. 选择 "Custom token"
5. 设置权限和资源范围

## 📱 客户端连接

### 推荐客户端

- **Element Desktop**: 官方桌面客户端
- **Element Mobile**: iOS/Android 移动客户端
- **FluffyChat**: 第三方移动客户端
- **Nheko**: 第三方桌面客户端

### 连接配置

**服务器地址**: `${SERVER_NAME}` (例如: `example.com`)

大多数客户端会自动通过 well-known 发现或 SRV 记录找到正确的服务器配置。

### 手动配置

如果自动发现失败，可以手动配置：

- **Homeserver URL**: `https://matrix.${SERVER_NAME}:${HTTPS_PORT}`
- **Identity Server**: 留空或使用默认

## 🛠️ 管理命令

部署完成后，可以使用以下命令管理服务：

```bash
# 查看服务状态
manage status

# 重启服务
manage restart

# 查看日志
manage logs

# 备份数据
manage backup

# 更新服务
manage update
```

## 🐛 故障排除

### 常见问题

1. **证书申请失败**
   - 检查 DNS 记录是否正确
   - 验证 Cloudflare API Token 权限
   - 确认域名解析到正确的 IP

2. **客户端连接失败**
   - 检查 SRV 记录配置
   - 验证端口转发设置
   - 确认防火墙规则

3. **服务启动失败**
   - 检查系统资源使用情况
   - 查看 Kubernetes 事件日志
   - 验证配置文件语法

### 日志查看

```bash
# 查看所有服务状态
kubectl get pods -n ess

# 查看特定服务日志
kubectl logs -n ess deployment/ess-synapse-main

# 查看系统事件
kubectl get events -n ess --sort-by='.lastTimestamp'
```

## 📄 许可证

本项目采用 AGPL-3.0 许可证，仅限非商业用途。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 📞 支持

如果您遇到问题，请：

1. 查看本文档的故障排除部分
2. 在 GitHub 上提交 Issue
3. 提供详细的错误日志和系统信息

---

**注意**: 本脚本会自动检测源仓库，支持 fork 和自定义仓库部署。只需修改下载 URL 中的仓库路径即可。
