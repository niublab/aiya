# Matrix ESS Community UDP端口配置说明

## 🎯 UDP端口要求

### 需求文档指定的UDP端口范围
根据需求文档要求，Matrix ESS Community必须使用以下UDP端口配置：

```bash
# 主要WebRTC媒体端口范围 (必需)
30152-30352/udp    # 共201个UDP端口

# 固定WebRTC端口 (可选)
30881/tcp          # ICE/TCP fallback
30882/udp          # 固定UDP端口
```

## 🔧 脚本配置实现

### 配置文件中的UDP端口设置
脚本已正确配置需求文档指定的UDP端口范围：

```yaml
# Matrix RTC配置
matrixRTC:
  sfu:
    config:
      rtc:
        # UDP端口范围 (需求文档指定)
        port_range_start: 30152
        port_range_end: 30352
        
        # TCP端口 (ICE/TCP fallback)
        tcp_port: 30881

# 网络策略配置
networkPolicy:
  ingress:
    - ports:
        - protocol: UDP
          port: 30152
          endPort: 30352
        - protocol: TCP
          port: 30881
        - protocol: UDP
          port: 30882

# 主机网络配置
hostNetwork:
  udpPortRange:
    start: 30152
    end: 30352
```

### 环境变量配置
```bash
# UDP端口范围 (用于WebRTC)
UDP_RANGE="30152-30352"

# 固定WebRTC端口
WEBRTC_TCP_PORT="30881"
WEBRTC_UDP_PORT="30882"
```

## 🚪 路由器防火墙配置

### 必需放行的UDP端口
```bash
# 主要WebRTC端口范围 (必需)
30152-30352/udp → 服务器IP:30152-30352

# 固定端口 (可选，用于特定场景)
30881/tcp → 服务器IP:30881
30882/udp → 服务器IP:30882
```

### 路由器配置示例

#### 方式1: 端口范围映射
```
规则名称: Matrix WebRTC UDP Range
协议: UDP
外部端口: 30152-30352
内部端口: 30152-30352  
内部IP: [服务器内网IP]
状态: 启用
```

#### 方式2: 逐个端口配置
如果路由器不支持端口范围，需要逐个配置201个UDP端口：
```bash
# 这种方式比较繁琐，建议使用支持端口范围的路由器
30152/udp → 服务器IP:30152
30153/udp → 服务器IP:30153
...
30352/udp → 服务器IP:30352
```

## 🔍 为什么需要这些UDP端口？

### WebRTC工作原理
1. **媒体传输**: 音视频数据通过UDP传输，延迟更低
2. **NAT穿透**: 客户端之间建立直接连接需要多个端口
3. **并发连接**: 每个参与者可能使用2个UDP端口
4. **端口协商**: WebRTC通过ICE协商选择最佳端口

### 端口使用场景
- **点对点通话**: 2个参与者，约4个UDP端口
- **小组会议**: 5个参与者，约10个UDP端口  
- **大型会议**: 20个参与者，约40个UDP端口
- **并发会议**: 多个房间同时进行，需要更多端口

### LiveKit端口分配
根据LiveKit官方文档：
- **默认范围**: 50000-60000 (10001个端口)
- **需求文档**: 30152-30352 (201个端口)
- **每参与者**: 约2个UDP端口
- **理论支持**: 约100个并发参与者

## ⚠️ 重要注意事项

### 1. 端口范围必须完整开放
```bash
# ✅ 正确 - 完整范围
30152-30352/udp

# ❌ 错误 - 部分端口
30152-30200/udp  # 范围不完整
30152,30200,30300/udp  # 离散端口
```

### 2. 防火墙配置顺序
```bash
# 1. 路由器端口映射
30152-30352/udp → 服务器IP:30152-30352

# 2. 服务器防火墙
ufw allow 30152:30352/udp

# 3. Kubernetes网络策略
# (脚本自动配置)
```

### 3. 网络性能考虑
- **带宽要求**: 每路视频约1-3Mbps
- **延迟要求**: WebRTC对延迟敏感，建议<100ms
- **丢包率**: UDP丢包率应<1%

## 🧪 测试验证

### 端口开放测试
```bash
# 测试UDP端口范围
nmap -sU -p 30152-30352 your-public-ip

# 测试特定端口
nc -u -v your-public-ip 30152
nc -u -v your-public-ip 30352

# 批量测试脚本
for port in {30152..30352}; do
    timeout 1 nc -u -v your-public-ip $port 2>&1 | grep -q "succeeded" && echo "Port $port: Open"
done
```

### WebRTC连接测试
```bash
# 1. 部署完成后访问Element Web
https://app.your-domain.com

# 2. 创建房间并邀请用户
# 3. 发起视频通话
# 4. 检查浏览器开发者工具的网络连接
# 5. 确认UDP连接建立成功
```

### 连接状态检查
在浏览器开发者工具中检查：
```javascript
// 检查WebRTC连接状态
pc.getStats().then(stats => {
    stats.forEach(report => {
        if (report.type === 'candidate-pair' && report.state === 'succeeded') {
            console.log('Local port:', report.localCandidate.port);
            console.log('Remote port:', report.remoteCandidate.port);
        }
    });
});
```

## 🛠️ 故障排除

### UDP端口不通
1. **检查路由器配置**: 确认端口范围映射正确
2. **检查防火墙**: 确认服务器防火墙允许UDP端口
3. **检查ISP限制**: 某些ISP可能限制大量UDP端口
4. **检查网络设备**: 交换机、防火墙等中间设备

### WebRTC连接失败
1. **检查STUN/TURN配置**: 确认NAT穿透服务正常
2. **检查证书**: HTTPS是WebRTC的必需条件
3. **检查域名解析**: 确认RTC域名解析正确
4. **检查端口冲突**: 确认端口没有被其他服务占用

### 性能问题
1. **减少端口范围**: 如果不需要大量并发，可以减少端口范围
2. **优化网络**: 检查带宽、延迟、丢包率
3. **负载均衡**: 大量用户时考虑多实例部署

## 📊 配置总结

| 配置项 | 值 | 说明 |
|--------|-----|------|
| UDP端口范围 | 30152-30352 | 需求文档指定，共201个端口 |
| TCP端口 | 30881 | ICE/TCP fallback |
| UDP固定端口 | 30882 | 可选的固定UDP端口 |
| 理论并发数 | ~100用户 | 基于201个端口，每用户2端口 |
| 路由器配置 | 端口范围映射 | 30152-30352/udp → 服务器IP |
| 防火墙配置 | ufw allow | 30152:30352/udp |

---

**更新时间**: 2025-06-13  
**适用版本**: Matrix ESS Community v5.0.0  
**遵循标准**: 需求文档UDP端口范围要求
