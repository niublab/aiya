# Systemd定时IP更新系统

## 🎯 系统概述

基于systemd timer的自动化IP更新系统，严格使用 `dig +short 自定义域名 @8.8.8.8` 和 `@1.1.1.1` 获取公网IP并自动更新相关服务配置。

## 📋 系统架构

```
systemd timer → ip-update.service → ip-update.sh → 更新服务配置
     ↓              ↓                    ↓              ↓
  定时触发      服务单元           更新脚本        重载服务
```

## 🔧 核心组件

### 1. IP更新脚本 (`ip-update.sh`)
- 严格使用dig命令获取IP
- 支持多DNS服务器备用
- 自动配置文件更新
- 服务重载管理

### 2. Systemd服务单元 (`ip-update.service`)
- 一次性执行服务
- 安全权限控制
- 资源限制配置

### 3. Systemd定时器 (`ip-update.timer`)
- 可配置执行间隔
- 启动延迟设置
- 持久化任务支持

### 4. 配置文件 (`ip-update.conf`)
- 完整的配置选项
- 环境变量支持
- 安全配置管理

### 5. 配置模板系统
- Nginx配置模板
- ESS配置模板
- 变量替换支持

## 📁 文件结构

```
/opt/ip-updater/
├── bin/
│   └── ip-update.sh           # 主更新脚本
├── config/
│   ├── ip-update.conf         # 主配置文件
│   └── last_ip                # 上次IP记录
├── templates/
│   ├── nginx.conf.template    # Nginx配置模板
│   └── ess-values.template    # ESS配置模板
├── backup/
│   └── [按时间戳自动备份]
├── logs/
│   └── ip-update.log          # 详细日志
├── scripts/
│   ├── pre-update.sh          # 更新前脚本
│   └── post-update.sh         # 更新后脚本
└── metrics/
    └── ip-update.metrics      # 性能指标

/etc/systemd/system/
├── ip-update.service          # 服务单元
└── ip-update.timer            # 定时器单元

/etc/logrotate.d/
└── ip-updater                 # 日志轮转配置
```

## 🚀 快速部署

### 方法1: 自动安装
```bash
# 下载安装脚本
wget https://raw.githubusercontent.com/your-repo/install-ip-updater.sh
chmod +x install-ip-updater.sh

# 运行安装
sudo ./install-ip-updater.sh
```

### 方法2: 手动安装
```bash
# 1. 创建目录
sudo mkdir -p /opt/ip-updater/{bin,config,templates,backup,logs}

# 2. 复制文件
sudo cp ip-update.sh /opt/ip-updater/bin/
sudo cp ip-update.conf /opt/ip-updater/config/
sudo cp nginx.conf.template /opt/ip-updater/templates/
sudo cp ess-values.template /opt/ip-updater/templates/

# 3. 设置权限
sudo chmod 755 /opt/ip-updater/bin/ip-update.sh
sudo chmod 644 /opt/ip-updater/config/ip-update.conf

# 4. 安装systemd服务
sudo cp ip-update.service /etc/systemd/system/
sudo cp ip-update.timer /etc/systemd/system/
sudo systemctl daemon-reload

# 5. 启用服务
sudo systemctl enable ip-update.timer
sudo systemctl start ip-update.timer
```

### 配置步骤
1. **编辑配置文件**
   ```bash
   sudo nano /opt/ip-updater/config/ip-update.conf
   ```

2. **设置DDNS域名** (必需)
   ```bash
   DDNS_DOMAIN="ip.your-domain.com"
   ```

3. **配置服务列表**
   ```bash
   SERVICES_TO_RELOAD=("nginx" "matrix-ess")
   ```

4. **重启定时器**
   ```bash
   sudo systemctl restart ip-update.timer
   ```

## ⚙️ 配置说明

### 🔑 关键配置项
- **DDNS_DOMAIN**: IP解析域名 (必需配置)
- **DNS_SERVERS**: DNS服务器列表 (固定为8.8.8.8和1.1.1.1)
- **UPDATE_INTERVAL**: 更新检查间隔 (秒)
- **SERVICES_TO_RELOAD**: 需要重载的服务列表
- **BACKUP_ENABLED**: 是否启用配置备份

### 📋 支持的服务类型
- **nginx**: Nginx Web服务器
- **matrix-ess/ess**: Matrix ESS服务
- **docker-容器名**: Docker容器 (如: docker-app)
- **其他systemd服务**: 任何systemd管理的服务

### 🌐 DNS配置要求
系统严格按照要求使用以下DNS服务器:
- 主DNS: `8.8.8.8` (Google DNS)
- 备用DNS: `1.1.1.1` (Cloudflare DNS)

命令格式: `dig +short your-domain.com @8.8.8.8`

## 📊 监控和日志

### 🔍 状态检查
```bash
# 检查定时器状态
systemctl status ip-update.timer
systemctl list-timers ip-update.timer

# 检查服务状态
systemctl status ip-update.service

# 查看最近执行记录
journalctl -u ip-update.service --since "1 hour ago"

# 实时查看日志
journalctl -u ip-update.service -f
tail -f /opt/ip-updater/logs/ip-update.log
```

### 🚀 手动操作
```bash
# 手动触发IP更新
sudo systemctl start ip-update.service

# 测试模式运行 (不实际更新)
sudo /opt/ip-updater/bin/ip-update.sh --test

# 调试模式运行
sudo /opt/ip-updater/bin/ip-update.sh --test --debug

# 检查配置有效性
sudo /opt/ip-updater/bin/ip-update.sh --check-config

# 查看当前IP
dig +short ip.your-domain.com @8.8.8.8
```

### 📈 性能监控
```bash
# 查看执行统计
cat /opt/ip-updater/metrics/ip-update.metrics

# 查看备份历史
ls -la /opt/ip-updater/backup/

# 查看日志大小
du -sh /opt/ip-updater/logs/
```

## 🔧 高级配置

### 🎯 定时器配置
编辑 `/etc/systemd/system/ip-update.timer`:
```ini
[Timer]
# 每5分钟检查一次
OnUnitActiveSec=5min

# 或者使用日历格式
# OnCalendar=*:0/5  # 每5分钟
# OnCalendar=*:0,15,30,45  # 每15分钟
# OnCalendar=hourly  # 每小时
```

### 🔐 安全配置
```bash
# 设置严格的文件权限
sudo chmod 600 /opt/ip-updater/config/ip-update.conf
sudo chown root:root /opt/ip-updater/config/ip-update.conf

# 限制日志访问
sudo chmod 640 /opt/ip-updater/logs/ip-update.log
```

### 📧 通知配置
在配置文件中启用通知:
```bash
NOTIFICATION_ENABLED="true"
NOTIFICATION_METHODS=("syslog" "email")
EMAIL_TO="admin@your-domain.com"
```

## 🔍 故障排除

### ❌ 常见问题及解决方案

#### 1. DNS解析失败
```bash
# 问题: 无法获取IP地址
# 检查:
dig +short ip.your-domain.com @8.8.8.8
dig +short ip.your-domain.com @1.1.1.1

# 解决:
# - 确认域名DNS记录正确
# - 检查网络连接
# - 验证防火墙设置
```

#### 2. 服务重载失败
```bash
# 问题: Nginx或ESS重载失败
# 检查:
nginx -t  # 检查Nginx配置
systemctl status nginx
kubectl get pods -n ess

# 解决:
# - 检查配置文件语法
# - 验证服务运行状态
# - 查看详细错误日志
```

#### 3. 权限问题
```bash
# 问题: 权限不足
# 检查:
ls -la /opt/ip-updater/bin/ip-update.sh
ls -la /etc/nginx/sites-available/

# 解决:
sudo chown root:root /opt/ip-updater/bin/ip-update.sh
sudo chmod 755 /opt/ip-updater/bin/ip-update.sh
```

#### 4. 配置模板问题
```bash
# 问题: 模板变量未替换
# 检查:
grep "{{" /etc/nginx/sites-available/matrix-ess

# 解决:
# - 检查模板文件路径
# - 验证变量名称正确
# - 确认模板处理逻辑
```

### 🐛 调试模式
```bash
# 启用详细调试
sudo DEBUG=true /opt/ip-updater/bin/ip-update.sh --test

# 检查所有配置
sudo /opt/ip-updater/bin/ip-update.sh --check-config

# 验证DNS查询
sudo /opt/ip-updater/bin/ip-update.sh --debug 2>&1 | grep -i dns

# 测试服务重载
sudo systemctl dry-run reload nginx
```

### 📋 故障排除检查清单
- [ ] DDNS域名DNS记录正确
- [ ] 网络连接正常
- [ ] DNS服务器可访问 (8.8.8.8, 1.1.1.1)
- [ ] 配置文件语法正确
- [ ] 文件权限设置正确
- [ ] 目标服务运行正常
- [ ] 模板文件存在且有效
- [ ] 系统资源充足
