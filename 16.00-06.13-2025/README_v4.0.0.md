# Matrix ESS Community 自动部署脚本 v4.0.0

## 🎯 重大更新说明

本版本基于**ESS官方最新规范25.6.1**完全重写，严格遵循"基于事实，严禁推测"原则。

### ✨ 主要特性

- **官方规范**: 基于Element Server Suite Community 25.6.1官方最新规范
- **OCI部署**: 使用官方OCI registry `oci://ghcr.io/element-hq/ess-helm/matrix-stack`
- **分阶段部署**: 基于需求文档的分阶段开发规划实现
- **小白友好**: 层级最少，逻辑清晰的菜单设计
- **稳定可靠**: 版本锁定，严格的错误处理和验证

## 🚀 分阶段部署流程

### 第一阶段：基础服务功能实现
- ✅ K3s Kubernetes集群部署
- ✅ Helm包管理器安装
- ✅ cert-manager证书管理器
- ✅ Traefik负载均衡器配置
- ✅ 基础环境验证

### 第二阶段：ESS核心部署
- ✅ 基于官方最新schema的ESS部署
- ✅ 域名配置和SSL证书管理
- ✅ PostgreSQL数据库自动配置
- ✅ HAProxy负载均衡配置
- ✅ 初始管理员用户创建

### 第三阶段：用户体验和高级功能
- ✅ Element Web客户端配置
- ✅ Matrix Authentication Service配置
- ✅ Matrix RTC视频会议配置
- ✅ Well-known委托配置
- ✅ 网络访问优化

### 第四阶段：完善和优化
- ✅ 部署验证和健康检查
- ✅ 性能优化配置
- ✅ 文档和使用指南
- ✅ 故障排除工具

## 📋 使用方法

### 快速开始
```bash
# 下载脚本
wget https://your-domain/setup.sh
chmod +x setup.sh

# 运行脚本
sudo ./setup.sh
```

### 推荐流程
1. **选择菜单项1**: 分阶段部署 Matrix ESS (推荐)
2. **按顺序执行**: 第一阶段 → 第二阶段 → 第三阶段 → 第四阶段
3. **验证部署**: 使用验证脚本检查各阶段状态
4. **访问服务**: 通过配置的域名访问Matrix服务

### 一键部署
如果您熟悉Matrix部署，也可以选择**菜单项2**进行一键完整部署。

## 🔧 配置要求

### 系统要求
- **操作系统**: Debian 11+ / Ubuntu 20.04+
- **内存**: 最少4GB，推荐8GB+
- **存储**: 最少20GB可用空间
- **网络**: 稳定的互联网连接

### 域名要求
需要准备4个子域名：
- `matrix.yourdomain.com` - Synapse服务器
- `element.yourdomain.com` - Element Web客户端
- `auth.yourdomain.com` - 认证服务
- `rtc.yourdomain.com` - 视频会议服务

### 证书要求
- 支持Let's Encrypt自动证书
- 支持Cloudflare DNS验证
- 支持自定义证书

## 📁 文件结构

```
/opt/matrix/                    # 安装目录
├── ess-values.yaml            # ESS配置文件
├── config/                    # 配置文件目录
├── certs/                     # 证书文件目录
└── logs/                      # 日志文件目录

setup.sh                       # 主部署脚本
setup.sh.backup.*             # 备份文件
test_setup.sh                 # 测试脚本
verify_deployment.sh           # 验证脚本
CHANGELOG_v4.0.0.md           # 更新日志
```

## 🛠️ 故障排除

### 常见问题

1. **网络连接问题**
   ```bash
   # 检查网络连通性
   curl -s https://ghcr.io
   ```

2. **K3s安装失败**
   ```bash
   # 查看K3s日志
   journalctl -u k3s -f
   ```

3. **ESS部署失败**
   ```bash
   # 查看ESS状态
   k3s kubectl get pods -n ess
   helm status ess -n ess
   ```

### 验证部署
```bash
# 运行验证脚本
./verify_deployment.sh
```

## 📚 技术规范

### 基于官方文档
- [Element Server Suite Documentation](https://element-hq.github.io/ess-helm/)
- [ESS Helm Chart](https://github.com/element-hq/ess-helm)
- [Matrix Specification](https://spec.matrix.org/)

### 版本信息
- **脚本版本**: 4.0.0
- **ESS版本**: 25.6.1 (官方最新稳定版)
- **K3s版本**: v1.32.5+k3s1
- **Helm版本**: v3.18.2
- **cert-manager版本**: v1.18.0

## ⚠️ 重要说明

1. **许可证**: 仅限非商业用途 (AGPL-3.0)
2. **官方规范**: 严格基于ESS官方最新文档实现
3. **测试环境**: 建议先在测试环境验证
4. **备份重要**: 部署前请备份重要数据

## 🤝 支持与反馈

如果您在使用过程中遇到问题：

1. 查看详细的错误信息和日志
2. 运行验证脚本检查部署状态
3. 参考故障排除文档
4. 检查是否遵循了官方最新规范

---

**版本**: 4.0.0  
**发布日期**: 2025-06-13  
**基于**: ESS Community 25.6.1 官方规范  
**兼容性**: Debian/Ubuntu 系统  
**许可证**: AGPL-3.0 (仅限非商业用途)
