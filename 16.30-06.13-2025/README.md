# Matrix ESS Community 一键部署脚本

## 🚀 **快速安装**

### **方式1: curl一键安装 (推荐)**

```bash
# 一键安装并运行
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/16.30-06.13-2025/setup.sh)
```

### **方式2: 下载后安装**

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/16.30-06.13-2025/setup.sh -o setup.sh

# 运行脚本
chmod +x setup.sh
sudo ./setup.sh
```

## 📋 **系统要求**

- **操作系统**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- **内存**: 最少4GB，推荐8GB+
- **存储**: 最少20GB可用空间
- **网络**: 公网IP和域名
- **权限**: root权限

## 🎯 **功能特性**

### **✅ 完整的Matrix ESS部署**
- Matrix Synapse服务器
- Element Web客户端
- Matrix Authentication Service (MAS)
- Matrix RTC (视频会议)
- 自动SSL证书管理

### **✅ 智能配置**
- 自动域名配置和验证
- 智能端口配置
- 公网IP自动检测
- DNS配置验证

### **✅ 安全可靠**
- Let's Encrypt自动证书
- Cloudflare DNS验证
- 安全的端口配置
- 完整的权限管理

## 🔧 **配置说明**

### **域名配置**
脚本支持智能域名配置：

```bash
主域名: example.com

自动生成的子域名:
- Element Web: chat.example.com
- 认证服务: account.example.com  
- RTC服务: mrtc.example.com
- Synapse: matrix.example.com
- Matrix服务器: example.com (用户ID: @username:example.com)
```

### **端口配置**
默认端口配置（可自定义）：

```bash
- HTTP端口: 8080
- HTTPS端口: 8443
- 联邦端口: 8448
- WebRTC TCP: 30881
- WebRTC UDP: 30152-30352
```

### **DNS要求**
需要配置以下DNS记录：

```bash
# A记录 (指向服务器IP)
chat.example.com     → 服务器IP
account.example.com  → 服务器IP
mrtc.example.com     → 服务器IP
matrix.example.com   → 服务器IP

# 特殊记录 (用于IP检测)
ip.example.com       → 服务器IP
```

## 📖 **使用指南**

### **1. 运行安装脚本**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/16.30-06.13-2025/setup.sh)
```

### **2. 选择部署选项**
```bash
Matrix ESS Community 部署脚本

请选择操作:
  1) 一键部署 - 完整部署Matrix ESS
  2) 管理现有部署 - 管理已部署的服务
  3) 完全清理 - 清理所有数据和配置
  4) 系统信息 - 显示系统和服务状态

请选择 (1-4): 1
```

### **3. 配置信息**
按提示输入：
- 安装目录 (默认: /opt/matrix)
- 主域名 (如: example.com)
- 管理员用户名和密码
- Let's Encrypt证书邮箱
- Cloudflare API Token

### **4. 自动部署**
脚本将自动：
- 安装K3s Kubernetes
- 安装Helm包管理器
- 部署cert-manager
- 部署Matrix ESS
- 配置SSL证书
- 创建管理员用户

## 🛠️ **管理命令**

### **查看服务状态**
```bash
# 查看所有Pod状态
kubectl get pods -A

# 查看ESS服务状态
kubectl get pods -n ess

# 查看服务日志
kubectl logs -n ess deployment/synapse
```

### **管理用户**
```bash
# 创建新用户
kubectl exec -n ess deployment/synapse -- register_new_matrix_user \
  -u username -p password -a -c /data/homeserver.yaml \
  http://localhost:8008
```

## 🔍 **故障排除**

### **常见问题**

#### **1. DNS解析失败**
```bash
# 检查DNS配置
dig +short chat.example.com
dig +short ip.example.com

# 确保所有域名都指向服务器IP
```

#### **2. 证书申请失败**
```bash
# 检查cert-manager状态
kubectl get certificaterequests -A
kubectl describe certificate -n ess

# 检查Cloudflare API Token权限
```

#### **3. 服务无法访问**
```bash
# 检查端口开放
netstat -tlnp | grep -E "(8080|8443|8448)"

# 检查防火墙设置
ufw status
```

## 📞 **支持**

- **GitHub**: https://github.com/niublab/aiya
- **文档**: 查看项目README和Wiki
- **问题反馈**: 提交GitHub Issues

## 📄 **许可证**

本项目基于MIT许可证开源。

---

**Matrix ESS Community 部署脚本 v5.0.0**  
**支持ESS版本: 25.6.1**  
**更新时间: 2025-06-13**
