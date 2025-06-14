# WebRTC端口配置说明

## 📋 WebRTC端口概述

WebRTC (Web Real-Time Communication) 是Matrix中用于音视频通话的技术。为了确保通话功能正常工作，需要正确配置和开放相关端口。

## 🔧 默认端口配置

### 标准端口
```bash
WEBRTC_TCP_PORT="30881"          # WebRTC TCP端口
WEBRTC_UDP_PORT="30882"          # WebRTC UDP端口  
WEBRTC_UDP_RANGE_START="30152"   # WebRTC UDP范围开始
WEBRTC_UDP_RANGE_END="30352"     # WebRTC UDP范围结束
```

### 端口用途说明
- **30881/tcp**: WebRTC信令和控制连接
- **30882/udp**: WebRTC媒体流传输 (主要端口)
- **30152-30352/udp**: WebRTC媒体流传输 (端口范围，用于多路通话)

## 🛡️ 防火墙配置

### 自动配置
部署脚本会自动配置防火墙规则：

```bash
# UFW规则
ufw allow 30881/tcp
ufw allow 30882/udp  
ufw allow 30152:30352/udp

# iptables规则
iptables -A INPUT -p tcp --dport 30881 -j ACCEPT
iptables -A INPUT -p udp --dport 30882 -j ACCEPT
iptables -A INPUT -p udp --dport 30152:30352 -j ACCEPT
```

### 手动配置
如果需要手动配置防火墙：

```bash
# 使用UFW
sudo ufw allow 30881/tcp
sudo ufw allow 30882/udp
sudo ufw allow 30152:30352/udp

# 使用iptables
sudo iptables -A INPUT -p tcp --dport 30881 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 30882 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 30152:30352 -j ACCEPT
```

## 🌐 路由器端口映射

### 必需的端口映射
在路由器中配置以下端口映射：

```
外部端口 -> 内部IP:内部端口
30881    -> 服务器IP:30881 (TCP)
30882    -> 服务器IP:30882 (UDP)
30152-30352 -> 服务器IP:30152-30352 (UDP范围)
```

### 路由器配置示例
1. 登录路由器管理界面
2. 找到"端口转发"或"虚拟服务器"设置
3. 添加以下规则：

| 服务名称 | 外部端口 | 内部端口 | 协议 | 内部IP |
|---------|---------|---------|------|--------|
| WebRTC-TCP | 30881 | 30881 | TCP | 192.168.1.100 |
| WebRTC-UDP | 30882 | 30882 | UDP | 192.168.1.100 |
| WebRTC-Range | 30152-30352 | 30152-30352 | UDP | 192.168.1.100 |

## 🔍 端口检查和测试

### 检查端口是否开放
```bash
# 检查TCP端口
nc -zv your-domain.com 30881

# 检查UDP端口 (需要在服务器上运行)
nc -u -zv localhost 30882

# 检查防火墙状态
sudo ufw status numbered
```

### 使用测试脚本
```bash
# 运行端口测试脚本
bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/test-port-fixes.sh)
```

## ⚙️ 自定义端口配置

### 修改默认端口
如果需要使用不同的端口，可以在部署前设置环境变量：

```bash
export WEBRTC_TCP_PORT="31881"
export WEBRTC_UDP_PORT="31882"
export WEBRTC_UDP_RANGE_START="31152"
export WEBRTC_UDP_RANGE_END="31352"
```

### 配置文件修改
编辑 `ess-config-template.env` 文件：

```bash
# WebRTC端口配置 (自定义)
WEBRTC_TCP_PORT="31881"
WEBRTC_UDP_PORT="31882"
WEBRTC_UDP_RANGE_START="31152"
WEBRTC_UDP_RANGE_END="31352"
```

## 🚨 故障排除

### 常见问题

#### 1. 无法建立音视频通话
**可能原因**: WebRTC端口未开放
**解决方案**:
```bash
# 检查防火墙状态
sudo ufw status
# 检查端口监听
sudo netstat -tulnp | grep -E "30881|30882"
```

#### 2. 通话质量差或断断续续
**可能原因**: UDP端口范围不足
**解决方案**: 确保30152-30352端口范围完全开放

#### 3. 路由器后无法接收通话
**可能原因**: 路由器端口映射配置错误
**解决方案**: 检查路由器端口转发配置

### 调试命令
```bash
# 检查ESS WebRTC服务状态
kubectl get pods -n ess | grep rtc
kubectl logs -n ess deployment/ess-matrix-rtc

# 检查端口占用
sudo ss -tulnp | grep -E "30881|30882"

# 测试端口连通性
telnet your-domain.com 30881
```

## 📝 注意事项

1. **UDP端口范围**: 30152-30352端口范围用于支持多人通话，建议完整开放
2. **防火墙优先级**: 确保WebRTC规则在防火墙中有正确的优先级
3. **NAT穿透**: 在复杂网络环境中，可能需要配置STUN/TURN服务器
4. **安全考虑**: 仅开放必要的端口，定期检查端口使用情况

## 🔗 相关链接

- [Matrix WebRTC官方文档](https://matrix.org/docs/guides/webrtc)
- [ESS Helm Chart配置](https://github.com/element-hq/ess-helm)
- [防火墙配置指南](./README.md#防火墙配置)

---

**提示**: 如果WebRTC功能仍然无法正常工作，请检查网络环境是否支持UDP通信，某些企业网络可能会阻止UDP流量。
