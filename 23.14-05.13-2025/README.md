# ESS-Helm外部Nginx反代 + IP自动更新系统

**创建时间**: 2025年1月13日 23:14  
**版本**: v1.0.0  
**作者**: Augment Agent

## 📋 目录内容

本目录包含两套完整的解决方案：

### 🌐 ESS-Helm外部Nginx反代方案
- **ess-nginx-proxy-config.md** - 详细配置指南和技术文档
- **deploy-ess-nginx-proxy.sh** - 全自动部署脚本
- **ess-config-template.env** - 完整配置模板
- **ess-helm-best-practices.md** - 最佳实践总结

### 🔄 IP自动更新系统
- **ip-update-system.md** - 系统概述和文档
- **ip-update.sh** - 主更新脚本
- **ip-update.conf** - 配置文件
- **ip-update.service** - Systemd服务单元
- **ip-update.timer** - Systemd定时器
- **install-ip-updater.sh** - 自动安装脚本
- **ip-updater-usage-examples.md** - 使用示例和故障排除

### 📄 配置模板
- **nginx.conf.template** - Nginx配置模板
- **ess-values.template** - ESS配置模板

## 🎯 方案特点

### ESS-Helm外部Nginx反代
- ✅ 支持非标准端口 (8080/8443)
- ✅ 自定义域名配置
- ✅ 自定义部署路径
- ✅ 完整SSL证书管理
- ✅ WebRTC端口优化
- ✅ 高性能和高安全性

### IP自动更新系统
- ✅ 严格使用dig命令 (@8.8.8.8 @1.1.1.1)
- ✅ Systemd定时器集成
- ✅ 自动服务重载
- ✅ 配置模板系统
- ✅ 完整日志和监控
- ✅ 安全备份机制

## 🚀 快速开始

### 方案1: ESS-Helm外部Nginx反代
```bash
# 1. 配置环境变量
export DOMAIN="your-domain.com"
export HTTP_PORT="8080"
export HTTPS_PORT="8443"

# 2. 运行部署脚本
chmod +x deploy-ess-nginx-proxy.sh
sudo ./deploy-ess-nginx-proxy.sh
```

### 方案2: IP自动更新系统
```bash
# 1. 运行安装脚本
chmod +x install-ip-updater.sh
sudo ./install-ip-updater.sh

# 2. 配置DDNS域名
sudo nano /opt/ip-updater/config/ip-update.conf
# 设置: DDNS_DOMAIN="ip.your-domain.com"

# 3. 启动服务
sudo systemctl restart ip-update.timer
```

### 方案3: 组合使用
```bash
# 1. 先部署ESS-Helm
sudo ./deploy-ess-nginx-proxy.sh

# 2. 再安装IP更新系统
sudo ./install-ip-updater.sh

# 3. 配置IP更新系统管理ESS服务
sudo nano /opt/ip-updater/config/ip-update.conf
# 设置: SERVICES_TO_RELOAD=("nginx" "matrix-ess")
```

## 📊 文件说明

| 文件名 | 类型 | 功能描述 |
|--------|------|----------|
| `ess-nginx-proxy-config.md` | 文档 | ESS外部Nginx反代完整配置指南 |
| `deploy-ess-nginx-proxy.sh` | 脚本 | ESS自动部署脚本 |
| `ess-config-template.env` | 配置 | ESS环境变量配置模板 |
| `ess-helm-best-practices.md` | 文档 | ESS部署最佳实践总结 |
| `ip-update-system.md` | 文档 | IP更新系统完整文档 |
| `ip-update.sh` | 脚本 | IP更新核心脚本 |
| `ip-update.conf` | 配置 | IP更新系统配置文件 |
| `ip-update.service` | 系统 | Systemd服务单元文件 |
| `ip-update.timer` | 系统 | Systemd定时器配置 |
| `install-ip-updater.sh` | 脚本 | IP更新系统安装脚本 |
| `nginx.conf.template` | 模板 | Nginx配置模板文件 |
| `ess-values.template` | 模板 | ESS Helm values模板 |
| `ip-updater-usage-examples.md` | 文档 | 使用示例和故障排除 |

## 🔧 技术架构

### ESS-Helm架构
```
Internet → Router:8080/8443 → Server:Nginx → K3s:Traefik → ESS Services
```

### IP更新系统架构
```
systemd timer → ip-update.service → ip-update.sh → 更新服务配置
```

### 组合架构
```
Internet → Router → Nginx → K3s → ESS
    ↑                ↑
IP更新系统 ←→ 配置模板系统
```

## 🛡️ 安全特性

- **权限控制**: 最小权限原则
- **SSL/TLS**: 现代加密配置
- **防火墙**: UFW自动配置
- **访问控制**: 请求频率限制
- **配置备份**: 自动备份恢复
- **日志审计**: 完整操作记录

## 📈 性能优化

- **HTTP/2**: 启用HTTP/2协议
- **Gzip压缩**: 自动内容压缩
- **缓存策略**: 静态资源缓存
- **连接复用**: Keep-Alive优化
- **资源限制**: Systemd资源控制

## 🧹 清理和卸载

### 清理脚本使用
```bash
# 交互式清理 (推荐)
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/cleanup.sh)

# 完全清理 (保留SSL证书)
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/cleanup.sh) --full

# 仅清理ESS部署
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/cleanup.sh) --ess-only
```

### 清理选项
1. 清理ESS Helm部署
2. 清理K3s集群
3. 清理Nginx配置
4. 清理SSL证书
5. 清理systemd服务
6. 清理安装目录
7. 清理配置文件
8. 清理临时文件
9. 完全清理 (所有组件)

## 🔍 监控和维护

### 状态检查
```bash
# ESS服务状态
kubectl get pods -n ess
systemctl status nginx

# IP更新系统状态
systemctl status ip-update.timer
tail -f /opt/ip-updater/logs/ip-update.log
```

### 日志查看
```bash
# ESS日志
kubectl logs -n ess deployment/ess-synapse
journalctl -u nginx

# IP更新日志
journalctl -u ip-update.service -f
```

## 🚨 故障排除

### 常见问题
1. **502错误**: 检查K3s和Traefik状态
2. **SSL证书**: 验证证书路径和有效期
3. **DNS解析**: 检查域名解析配置
4. **端口占用**: 验证端口映射配置
5. **权限问题**: 检查文件和目录权限

### 调试命令
```bash
# ESS调试
kubectl describe pods -n ess
nginx -t

# IP更新调试
/opt/ip-updater/bin/ip-update.sh --test --debug
dig +short ip.your-domain.com @8.8.8.8
```

## 📞 支持和反馈

如果您在使用过程中遇到问题，请：

1. 查看相关文档和示例
2. 检查日志文件
3. 运行调试命令
4. 提交Issue或联系支持

## 📝 更新日志

### v1.0.0 (2025-01-13)
- 初始版本发布
- ESS-Helm外部Nginx反代方案
- IP自动更新系统
- 完整文档和示例
- 自动化部署脚本

---

**注意**: 这些脚本和配置文件经过精心设计和测试，适用于生产环境部署。请根据您的具体需求调整配置参数。
