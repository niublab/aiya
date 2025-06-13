# IP自动更新系统使用示例

## 🎯 完整部署示例

### 场景1: 家庭网络Matrix服务器

#### 环境信息
- 域名: `home.example.com`
- 公网IP通过DDNS获取: `ip.home.example.com`
- 路由器端口映射: 8080→8080, 8443→8443, 8448→8448
- 服务: Nginx + ESS Matrix

#### 1. 安装系统
```bash
# 下载安装脚本
wget https://github.com/your-repo/ip-updater/releases/latest/download/install-ip-updater.sh
chmod +x install-ip-updater.sh

# 运行安装
sudo ./install-ip-updater.sh
```

#### 2. 配置DDNS域名
```bash
# 编辑配置文件
sudo nano /opt/ip-updater/config/ip-update.conf

# 设置关键配置
DDNS_DOMAIN="ip.home.example.com"
UPDATE_INTERVAL="300"  # 5分钟检查一次
SERVICES_TO_RELOAD=("nginx" "matrix-ess")
BACKUP_ENABLED="true"
NOTIFICATION_METHODS=("syslog")
```

#### 3. 配置Nginx模板
```bash
# 编辑Nginx模板
sudo nano /opt/ip-updater/templates/nginx.conf.template

# 关键变量设置
DOMAIN="home.example.com"
WEB_SUBDOMAIN="app"
AUTH_SUBDOMAIN="mas"
RTC_SUBDOMAIN="rtc"
MATRIX_SUBDOMAIN="matrix"
HTTP_PORT="8080"
HTTPS_PORT="8443"
FEDERATION_PORT="8448"
```

#### 4. 启动服务
```bash
# 重启定时器
sudo systemctl restart ip-update.timer

# 检查状态
sudo systemctl status ip-update.timer
sudo systemctl list-timers ip-update.timer

# 手动测试
sudo /opt/ip-updater/bin/ip-update.sh --test --debug
```

#### 5. 验证运行
```bash
# 查看当前IP
dig +short ip.home.example.com @8.8.8.8

# 检查配置更新
grep "{{PUBLIC_IP}}" /etc/nginx/sites-available/matrix-ess || echo "配置已更新"

# 查看日志
tail -f /opt/ip-updater/logs/ip-update.log
```

---

### 场景2: 云服务器企业部署

#### 环境信息
- 域名: `matrix.company.com`
- 公网IP通过API获取: `api.company.com/public-ip`
- 标准端口: 80→8080, 443→8443
- 服务: Nginx + ESS + 监控

#### 1. 高级配置
```bash
# 企业级配置
sudo nano /opt/ip-updater/config/ip-update.conf

DDNS_DOMAIN="api.company.com"  # 返回纯IP的API端点
UPDATE_INTERVAL="180"  # 3分钟检查
SERVICES_TO_RELOAD=("nginx" "matrix-ess" "docker-monitoring")
BACKUP_ENABLED="true"
BACKUP_RETENTION_COUNT="30"
NOTIFICATION_ENABLED="true"
NOTIFICATION_METHODS=("email" "webhook")
EMAIL_TO="admin@company.com"
WEBHOOK_URL="https://monitoring.company.com/webhook/ip-change"
MONITORING_ENABLED="true"
```

#### 2. 自定义更新脚本
```bash
# 创建企业定制脚本
sudo nano /opt/ip-updater/scripts/post-update.sh

#!/bin/bash
# 企业定制更新后脚本

NEW_IP="$1"
OLD_IP="$2"

# 更新监控系统
curl -X POST "https://monitoring.company.com/api/server-ip" \
  -H "Content-Type: application/json" \
  -d "{\"server\":\"matrix\",\"old_ip\":\"$OLD_IP\",\"new_ip\":\"$NEW_IP\"}"

# 更新DNS记录 (如果使用API管理)
curl -X PUT "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records/RECORD_ID" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"A\",\"name\":\"matrix.company.com\",\"content\":\"$NEW_IP\"}"

# 通知团队
curl -X POST "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"Matrix服务器IP已更新: $OLD_IP → $NEW_IP\"}"

sudo chmod +x /opt/ip-updater/scripts/post-update.sh
```

#### 3. 配置模板变量
```bash
# 设置环境变量用于模板
sudo nano /opt/ip-updater/config/template-vars.env

DOMAIN="matrix.company.com"
WEB_SUBDOMAIN="app"
AUTH_SUBDOMAIN="auth"
RTC_SUBDOMAIN="rtc"
MATRIX_SUBDOMAIN="matrix"
HTTP_PORT="8080"
HTTPS_PORT="8443"
FEDERATION_PORT="8448"
SSL_CERT_PATH="/etc/letsencrypt/live/matrix.company.com/fullchain.pem"
SSL_KEY_PATH="/etc/letsencrypt/live/matrix.company.com/privkey.pem"
MAX_UPLOAD_SIZE="100M"
```

---

### 场景3: 多服务器集群部署

#### 环境信息
- 主域名: `matrix.cluster.com`
- 多个服务器节点
- 负载均衡配置
- 集中式IP管理

#### 1. 集群配置
```bash
# 主节点配置
DDNS_DOMAIN="cluster-ip.matrix.cluster.com"
SERVICES_TO_RELOAD=("nginx" "matrix-ess" "haproxy")
CLUSTER_MODE="true"
CLUSTER_NODES=("node1.matrix.cluster.com" "node2.matrix.cluster.com")
```

#### 2. 集群同步脚本
```bash
# 创建集群同步脚本
sudo nano /opt/ip-updater/scripts/cluster-sync.sh

#!/bin/bash
# 集群IP同步脚本

NEW_IP="$1"
CLUSTER_NODES=("node1.matrix.cluster.com" "node2.matrix.cluster.com")

for node in "${CLUSTER_NODES[@]}"; do
    echo "同步IP到节点: $node"
    ssh root@$node "echo '$NEW_IP' > /opt/ip-updater/config/cluster_ip"
    ssh root@$node "systemctl start ip-update.service"
done
```

---

## 🔧 常用命令参考

### 日常管理命令
```bash
# 查看服务状态
systemctl status ip-update.timer
systemctl status ip-update.service

# 查看定时器列表
systemctl list-timers --all | grep ip-update

# 查看最近执行记录
journalctl -u ip-update.service --since "24 hours ago"

# 查看实时日志
journalctl -u ip-update.service -f
tail -f /opt/ip-updater/logs/ip-update.log
```

### 手动操作命令
```bash
# 立即执行IP检查更新
sudo systemctl start ip-update.service

# 测试模式 (不实际更新)
sudo /opt/ip-updater/bin/ip-update.sh --test

# 调试模式
sudo /opt/ip-updater/bin/ip-update.sh --debug

# 检查配置
sudo /opt/ip-updater/bin/ip-update.sh --check-config

# 查看当前IP
dig +short your-ddns-domain.com @8.8.8.8
dig +short your-ddns-domain.com @1.1.1.1
```

### 配置管理命令
```bash
# 编辑主配置
sudo nano /opt/ip-updater/config/ip-update.conf

# 编辑Nginx模板
sudo nano /opt/ip-updater/templates/nginx.conf.template

# 编辑ESS模板
sudo nano /opt/ip-updater/templates/ess-values.template

# 重载配置
sudo systemctl restart ip-update.timer
```

### 备份和恢复命令
```bash
# 查看备份
ls -la /opt/ip-updater/backup/

# 手动备份
sudo /opt/ip-updater/bin/ip-update.sh --backup-only

# 恢复配置 (示例)
sudo cp /opt/ip-updater/backup/20250113_143022/nginx-matrix-ess.conf /etc/nginx/sites-available/matrix-ess
sudo nginx -t && sudo systemctl reload nginx
```

---

## 🚨 故障处理实例

### 问题1: DNS查询失败
```bash
# 现象
[ERROR] 所有DNS服务器查询失败，无法获取IP地址

# 排查
dig +short ip.your-domain.com @8.8.8.8
dig +short ip.your-domain.com @1.1.1.1
nslookup ip.your-domain.com 8.8.8.8

# 解决
# 1. 检查域名DNS记录
# 2. 确认网络连接
# 3. 验证防火墙设置
# 4. 检查域名是否过期
```

### 问题2: 服务重载失败
```bash
# 现象
[ERROR] Nginx服务重载失败

# 排查
sudo nginx -t
sudo systemctl status nginx
sudo journalctl -u nginx --since "1 hour ago"

# 解决
# 1. 修复Nginx配置语法错误
# 2. 检查SSL证书路径
# 3. 验证端口占用情况
# 4. 重启Nginx服务
```

### 问题3: 权限问题
```bash
# 现象
[ERROR] 权限不足，无法更新配置文件

# 排查
ls -la /opt/ip-updater/bin/ip-update.sh
ls -la /etc/nginx/sites-available/
whoami

# 解决
sudo chown root:root /opt/ip-updater/bin/ip-update.sh
sudo chmod 755 /opt/ip-updater/bin/ip-update.sh
sudo chown root:root /etc/nginx/sites-available/matrix-ess
```

---

## 📊 监控和告警设置

### 系统监控
```bash
# 创建监控脚本
sudo nano /opt/ip-updater/scripts/monitor.sh

#!/bin/bash
# IP更新系统监控脚本

# 检查定时器状态
if ! systemctl is-active --quiet ip-update.timer; then
    echo "CRITICAL: IP更新定时器未运行"
    exit 2
fi

# 检查最近执行时间
LAST_RUN=$(systemctl show ip-update.timer --property=LastTriggerUSec --value)
if [[ -z "$LAST_RUN" || "$LAST_RUN" == "0" ]]; then
    echo "WARNING: IP更新定时器从未执行"
    exit 1
fi

# 检查日志错误
ERROR_COUNT=$(grep -c "ERROR" /opt/ip-updater/logs/ip-update.log | tail -100)
if [[ $ERROR_COUNT -gt 5 ]]; then
    echo "WARNING: 最近100行日志中有 $ERROR_COUNT 个错误"
    exit 1
fi

echo "OK: IP更新系统运行正常"
exit 0
```

### 告警配置
```bash
# 添加到crontab进行定期检查
sudo crontab -e

# 每10分钟检查一次
*/10 * * * * /opt/ip-updater/scripts/monitor.sh || logger "IP更新系统异常"
```

---

## 📈 性能优化建议

### 1. 减少检查频率
```bash
# 对于稳定的网络环境，可以增加检查间隔
UPDATE_INTERVAL="600"  # 10分钟
```

### 2. 启用缓存
```bash
# 启用DNS查询缓存
DNS_CACHE_ENABLED="true"
DNS_CACHE_TTL="300"
```

### 3. 并行处理
```bash
# 启用并行配置更新
PARALLEL_UPDATE="true"
MAX_PARALLEL_JOBS="3"
```

### 4. 资源限制
```bash
# 在systemd服务中设置资源限制
MemoryMax=128M
CPUQuota=25%
```

这个完整的IP自动更新系统严格按照您的要求，使用 `dig +short 自定义域名 @8.8.8.8` 和 `@1.1.1.1` 来获取IP地址，并通过systemd定时器自动更新相关服务配置。
