# 🚀 ESS-Helm一键部署快速指南

## 📋 支持的curl一键部署命令

### 🌟 **基础一键安装**
```bash
# 交互式安装 (推荐)
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### 🎯 **自动化部署选项**

#### 1. 仅部署ESS-Helm外部Nginx反代
```bash
AUTO_DEPLOY=1 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

#### 2. 仅部署IP自动更新系统
```bash
AUTO_DEPLOY=2 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

#### 3. 完整部署 (ESS + IP更新系统)
```bash
AUTO_DEPLOY=3 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### 🔧 **调试模式**
```bash
# 启用调试输出
DEBUG=true bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 调试模式 + 自动完整部署
DEBUG=true AUTO_DEPLOY=3 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

## 📱 **部署流程**

### 交互式部署流程
1. **运行命令**: 执行curl一键安装命令
2. **选择方案**: 从菜单中选择部署方案
3. **自动下载**: 系统自动下载所有必需文件
4. **配置设置**: 根据提示配置相关参数
5. **自动部署**: 系统自动完成部署过程
6. **验证结果**: 检查部署状态和服务运行情况

### 自动化部署流程
1. **设置变量**: 通过环境变量指定部署方案
2. **执行命令**: 运行带参数的curl命令
3. **无人值守**: 系统自动完成整个部署过程
4. **查看结果**: 检查部署日志和服务状态

## 🎛️ **部署选项说明**

### 选项1: ESS-Helm外部Nginx反代方案
- ✅ 安装K3s Kubernetes
- ✅ 部署ESS Community版本
- ✅ 配置外部Nginx反向代理
- ✅ 设置SSL证书
- ✅ 配置非标准端口 (8080/8443)
- ✅ 支持自定义域名和路径

### 选项2: IP自动更新系统
- ✅ 安装systemd定时器服务
- ✅ 配置dig命令IP获取 (@8.8.8.8 @1.1.1.1)
- ✅ 设置配置模板系统
- ✅ 启用自动服务重载
- ✅ 配置日志和监控

### 选项3: 完整部署
- ✅ 包含选项1的所有功能
- ✅ 包含选项2的所有功能
- ✅ 自动配置IP更新系统管理ESS服务
- ✅ 完整的集成解决方案

### 选项4: 仅下载文件
- ✅ 下载所有脚本和配置文件到本地
- ✅ 支持离线部署
- ✅ 可自定义配置后手动部署

## 🔧 **环境变量配置**

### 常用环境变量
```bash
# 调试模式
export DEBUG=true

# 自动部署模式
export AUTO_DEPLOY=3

# 自定义域名 (ESS部署时使用)
export DOMAIN="your-domain.com"
export HTTP_PORT="8080"
export HTTPS_PORT="8443"

# DDNS域名 (IP更新系统使用)
export DDNS_DOMAIN="ip.your-domain.com"
```

### 高级配置
```bash
# 自定义安装目录
export INSTALL_DIR="/opt/custom-ess"

# 跳过系统检查
export SKIP_REQUIREMENTS_CHECK=true

# 使用备用下载源
export REPO_URL="https://your-mirror.com/path"
```

## 📊 **部署后验证**

### ESS服务验证
```bash
# 检查K3s状态
kubectl get nodes
kubectl get pods -n ess

# 检查Nginx状态
systemctl status nginx
nginx -t

# 测试访问
curl -I https://your-domain.com:8443
```

### IP更新系统验证
```bash
# 检查定时器状态
systemctl status ip-update.timer
systemctl list-timers ip-update.timer

# 检查配置
/opt/ip-updater/bin/ip-update.sh --check-config

# 测试IP获取
dig +short ip.your-domain.com @8.8.8.8
```

## 🚨 **常见问题解决**

### 问题1: 下载失败
```bash
# 检查网络连接
curl -I https://raw.githubusercontent.com

# 使用代理
export https_proxy=http://proxy:port
bash <(curl -fsSL ...)
```

### 问题2: 权限不足
```bash
# 确保使用sudo
sudo bash <(curl -fsSL ...)

# 或切换到root用户
su -
bash <(curl -fsSL ...)
```

### 问题3: 系统不兼容
```bash
# 检查系统版本
cat /etc/os-release

# 手动安装依赖
apt update && apt install -y curl wget
```

## 📱 **使用示例**

### 示例1: 家庭网络快速部署
```bash
# 设置域名
export DOMAIN="home.example.com"
export DDNS_DOMAIN="ip.home.example.com"

# 一键完整部署
AUTO_DEPLOY=3 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### 示例2: 企业环境分步部署
```bash
# 第一步: 部署ESS
AUTO_DEPLOY=1 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

# 第二步: 配置完成后部署IP更新
AUTO_DEPLOY=2 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

### 示例3: 调试模式部署
```bash
# 启用详细日志
DEBUG=true AUTO_DEPLOY=3 bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)
```

## 🔗 **相关链接**

- **GitHub仓库**: https://github.com/niublab/aiya
- **问题反馈**: https://github.com/niublab/aiya/issues
- **ESS官方文档**: https://github.com/element-hq/ess-helm
- **Matrix官方网站**: https://matrix.org

## 📞 **技术支持**

如果您在使用过程中遇到问题:

1. 查看部署日志和错误信息
2. 参考故障排除文档
3. 在GitHub提交Issue
4. 联系技术支持

---

**注意**: 请确保在生产环境部署前先在测试环境验证配置的正确性。
