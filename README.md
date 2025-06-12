# Matrix ESS Community 内网部署自动化脚本

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Version](https://img.shields.io/badge/Version-1.1.0-green.svg)](https://github.com/niublab/aiya)

## 📋 项目简介

Matrix ESS Community 内网部署自动化脚本是一个完全自动化的Matrix视频会议服务部署解决方案，基于Element Server Suite Community Edition (ESS Community)，支持50人以下的视频会议需求，具备菜单式交互界面，支持内网部署和外网访问。

### ✨ 主要特性

- 🚀 **一键部署** - 通过单一命令完成完整部署
- 🎯 **小白友好** - 菜单式交互界面，层级最少，0为返回/退出
- 🔒 **安全可靠** - 自动生成32位密码，DNS验证证书，权限控制
- 🌐 **网络适配** - 支持动态公网IP + DDNS，自定义端口配置
- 🛠️ **维护便捷** - 支持重启、清理、备份等维护功能
- 📊 **实时监控** - 服务状态检查，日志查看，网络诊断

### 🏗️ 技术架构

基于官方ESS Community最新版本，包含以下核心组件：

- **Synapse** - Matrix服务器核心
- **Matrix Authentication Service (MAS)** - 基于OIDC的下一代认证系统
- **Element Call's Matrix RTC Backend** - 视频会议后端服务
- **Element Web** - Web客户端界面
- **PostgreSQL** - 数据库服务
- **HAProxy** - 负载均衡和路由
- **cert-manager** - 自动证书管理
- **K3s** - 轻量级Kubernetes集群

## 🚀 快速开始

### 系统要求

- **操作系统**: Debian/Ubuntu系列
- **硬件要求**: 最少2 CPU核心，2GB内存
- **网络要求**: 公网IP（动态IP + DDNS支持）
- **权限要求**: sudo/root权限

### 端口要求

- **HTTP端口**: 8080 (可自定义，替代80)
- **HTTPS端口**: 8443 (可自定义，替代443)
- **联邦端口**: 8448 (Matrix联邦通信)
- **UDP端口段**: 30152-30352 (WebRTC通信)

### 域名要求

需要准备以下域名（均需要A记录指向服务器IP）：

- 主域名: `example.com` (Matrix服务器名)
- Synapse: `matrix.example.com`
- MAS认证: `account.example.com`
- RTC后端: `mrtc.example.com`
- Web客户端: `chat.example.com`

### 证书要求

- **Cloudflare API Token** (用于DNS验证)
- **邮箱地址** (用于Let's Encrypt证书申请)

## 📦 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/setup.sh)
```

## 📖 使用指南

### 1. 部署流程

脚本会引导您完成以下步骤：

1. **环境检查** - 系统兼容性、网络连通性
2. **基础配置** - 域名、邮箱、目录设置
3. **网络配置** - 端口设置、公网IP获取
4. **证书配置** - 证书类型、Cloudflare API Token
5. **服务配置** - 数据库、存储路径
6. **部署确认** - 配置预览、确认部署
7. **自动部署** - K3s、cert-manager、ESS安装
8. **用户创建** - 创建初始管理员用户
9. **服务验证** - 验证所有服务正常运行
10. **完成总结** - 提供访问信息和后续指导

### 2. 主要功能

#### 🔧 配置管理
- 新建配置
- 加载配置
- 查看当前配置
- 保存配置

#### 🛠️ 服务管理
- 查看服务状态
- 重启服务
- 查看日志
- 验证部署

#### 🧹 清理环境
- 清理ESS服务 (保留K3s和cert-manager)
- 清理应用 (保留K3s集群)
- 完全清理 (删除所有组件)

#### 🔍 系统工具
- 系统信息查看
- 网络诊断
- 备份配置
- 检查更新

### 3. 配置示例

```yaml
# 端口配置
ports:
  http: 8080
  https: 8443
  federation: 8448
  udp_range: "30152-30250"

# 域名配置
domains:
  server_name: "example.com"
  synapse: "matrix.example.com"
  auth: "account.example.com"
  rtc: "mrtc.example.com"
  web: "chat.example.com"

# 管理员配置
admin:
  username: "admin"
  password: "auto-generated-32-chars"
  email: "admin@example.com"  # 可选

# 证书配置
certificates:
  email: "certs@example.com"  # 必需
  environment: "production"   # 或 "staging"
```

## 🔒 安全说明

### 许可证限制

⚠️ **重要提醒**: 本脚本基于AGPL-3.0许可证，**仅限个人、学习、研究等非商业用途**，禁止用于任何商业目的。

### 安全特性

- **密码安全**: 自动生成32位强密码
- **证书安全**: Let's Encrypt正式证书，DNS验证
- **网络安全**: 仅开放必要端口，内网部署
- **权限控制**: 严格控制文件访问权限

## 🛠️ 维护指南

### 服务重启

```bash
# 通过脚本菜单
./setup.sh -> 3) 服务管理 -> 2) 重启服务

# 手动重启
kubectl rollout restart deployment -n ess
```

### 查看日志

```bash
# 通过脚本菜单
./setup.sh -> 3) 服务管理 -> 3) 查看日志

# 手动查看
kubectl logs -n ess -l app.kubernetes.io/name=synapse -f
```

### 备份配置

```bash
# 通过脚本菜单
./setup.sh -> 7) 备份配置

# 手动备份
cp -r /opt/matrix /backup/matrix-$(date +%Y%m%d)
```

### 完全卸载

```bash
# 通过脚本菜单
./setup.sh -> 4) 清理环境 -> 3) 完全清理

# 手动卸载
helm uninstall ess -n ess
kubectl delete namespace ess
/usr/local/bin/k3s-uninstall.sh
```

## 🐛 故障排除

### 常见问题

1. **端口被占用**
   - 检查端口占用: `netstat -tuln | grep :8080`
   - 修改端口配置或停止占用进程

2. **域名解析失败**
   - 检查DNS记录: `nslookup matrix.example.com`
   - 确认A记录指向正确IP

3. **证书申请失败**
   - 检查Cloudflare API Token权限
   - 确认域名在Cloudflare托管

4. **服务启动失败**
   - 查看Pod状态: `kubectl get pods -n ess`
   - 查看事件: `kubectl get events -n ess`

### 获取帮助

- 查看详细日志: `kubectl logs -n ess <pod-name>`
- 检查服务状态: `kubectl describe pod -n ess <pod-name>`
- 网络诊断: 使用脚本内置网络诊断功能

## 📚 相关文档

- [Element Server Suite官方文档](https://github.com/element-hq/ess-helm)
- [Matrix协议文档](https://matrix.org/docs/)
- [K3s官方文档](https://docs.k3s.io/)
- [cert-manager文档](https://cert-manager.io/docs/)

## 🤝 贡献指南

欢迎提交Issue和Pull Request来改进这个项目。

## 📄 许可证

本项目基于 [AGPL-3.0](LICENSE-AGPL-3.0-only) 许可证，仅限非商业用途。

---

**⚠️ 免责声明**: 本脚本仅供学习和研究使用，使用者需自行承担使用风险。
