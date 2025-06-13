# ESS-Helm外部Nginx反代最佳部署方案

## 🎯 方案特点

- ✅ 支持外部Nginx反代
- ✅ 使用非标准端口 (8080/8443)
- ✅ 自定义域名配置
- ✅ 自定义部署路径
- ✅ 完整的SSL证书管理
- ✅ WebRTC端口优化配置

## 📋 部署步骤

### 1. K3s配置 - 非标准端口设置

创建K3s Traefik配置文件：

```bash
# 创建配置目录
sudo mkdir -p /var/lib/rancher/k3s/server/manifests

# 创建Traefik配置
sudo tee /var/lib/rancher/k3s/server/manifests/traefik-config.yaml << 'EOF'
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        exposedPort: 8080
      websecure:
        exposedPort: 8443
    service:
      spec:
        externalIPs:
        - "YOUR_SERVER_INTERNAL_IP"
EOF
```

### 2. ESS Values配置 - 外部反代模式

```yaml
# ess-values-external-proxy.yaml
serverName: "your-domain.com"

# 全局Ingress配置 - 禁用TLS (由外部Nginx处理)
ingress:
  tlsEnabled: false
  annotations:
    # 不使用cert-manager，由外部Nginx处理证书
    nginx.ingress.kubernetes.io/ssl-redirect: "false"

# Element Web配置
elementWeb:
  ingress:
    host: "app.your-domain.com"
    tlsEnabled: false

# Matrix Authentication Service配置
matrixAuthenticationService:
  ingress:
    host: "mas.your-domain.com"
    tlsEnabled: false

# Matrix RTC配置
matrixRTC:
  ingress:
    host: "rtc.your-domain.com"
    tlsEnabled: false
  sfu:
    exposedServices:
      rtcTcp:
        enabled: true
        portType: NodePort
        port: 30881
      rtcMuxedUdp:
        enabled: true
        portType: NodePort
        port: 30882
      rtcUdp:
        enabled: false

# Synapse配置
synapse:
  ingress:
    host: "matrix.your-domain.com"
    tlsEnabled: false

# Well-known配置
wellKnownDelegation:
  ingress:
    host: "your-domain.com"
    tlsEnabled: false
```

### 3. 外部Nginx配置

#### 主配置文件
```nginx
# /etc/nginx/sites-available/matrix-ess
server {
    listen 8080;
    server_name app.your-domain.com mas.your-domain.com rtc.your-domain.com matrix.your-domain.com your-domain.com;
    return 301 https://$host:8443$request_uri;
}

server {
    listen 8443 ssl http2;
    server_name app.your-domain.com mas.your-domain.com rtc.your-domain.com matrix.your-domain.com your-domain.com;

    # SSL配置
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # 代理到K3s Traefik
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # 文件上传大小
        client_max_body_size 50M;
    }
}

# Matrix联邦端口
server {
    listen 8448 ssl http2;
    server_name your-domain.com matrix.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 4. 自定义路径部署配置

如果需要在子路径部署（如 `/matrix`），可以使用以下配置：

```nginx
# 子路径部署示例
server {
    listen 8443 ssl http2;
    server_name your-domain.com;

    # 根路径重定向到Matrix
    location = / {
        return 301 https://$host:8443/matrix/;
    }

    # Matrix服务路径
    location /matrix/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host app.your-domain.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 重写路径
        rewrite ^/matrix/(.*)$ /$1 break;
    }

    # 认证服务路径
    location /auth/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host mas.your-domain.com;
        rewrite ^/auth/(.*)$ /$1 break;
    }
}
```

### 5. 防火墙和端口配置

```bash
# 服务器防火墙配置
sudo ufw allow 8080/tcp   # HTTP
sudo ufw allow 8443/tcp   # HTTPS
sudo ufw allow 8448/tcp   # Matrix联邦
sudo ufw allow 30881/tcp  # WebRTC TCP
sudo ufw allow 30882/udp  # WebRTC UDP
sudo ufw allow 30152:30352/udp  # WebRTC UDP范围

# 路由器端口映射
# 8080 -> 服务器IP:8080
# 8443 -> 服务器IP:8443
# 8448 -> 服务器IP:8448
# 30881 -> 服务器IP:30881
# 30882 -> 服务器IP:30882
# 30152-30352 -> 服务器IP:30152-30352
```

## 🚀 部署命令

### 1. 安装K3s
```bash
curl -sfL https://get.k3s.io | sh -
```

### 2. 配置kubectl
```bash
mkdir ~/.kube
export KUBECONFIG=~/.kube/config
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
```

### 3. 部署ESS
```bash
# 创建命名空间
kubectl create namespace ess

# 部署ESS (使用外部代理配置)
helm upgrade --install --namespace "ess" ess \
  oci://ghcr.io/element-hq/ess-helm/matrix-stack \
  -f ess-values-external-proxy.yaml \
  --wait
```

### 4. 配置Nginx
```bash
# 启用站点
sudo ln -s /etc/nginx/sites-available/matrix-ess /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## 🔍 验证部署

### 1. 检查K3s服务
```bash
kubectl get svc -n kube-system | grep traefik
kubectl get pods -n ess
```

### 2. 检查Nginx配置
```bash
sudo nginx -t
curl -I http://localhost:8080
```

### 3. 测试Matrix联邦
访问: https://federationtester.matrix.org/

## 📊 配置优势

### ✅ 优点
1. **灵活性**: 完全控制反代配置
2. **性能**: 优化的Nginx配置
3. **安全性**: 自定义SSL和安全头
4. **兼容性**: 支持各种网络环境
5. **可扩展**: 易于添加其他服务

### ⚠️ 注意事项
1. **证书管理**: 需要手动管理SSL证书
2. **配置复杂**: 需要维护两层代理配置
3. **调试难度**: 问题排查相对复杂
4. **资源消耗**: 额外的Nginx进程开销

## 🛠️ 故障排除

### 常见问题
1. **502错误**: 检查K3s Traefik状态
2. **证书问题**: 验证SSL证书路径
3. **WebSocket失败**: 检查Upgrade头配置
4. **联邦失败**: 验证8448端口配置

### 调试命令
```bash
# 检查ESS状态
kubectl get pods -n ess
kubectl logs -n ess deployment/ess-synapse

# 检查Traefik状态
kubectl get svc -n kube-system traefik
kubectl logs -n kube-system deployment/traefik

# 检查Nginx状态
sudo nginx -t
sudo systemctl status nginx
tail -f /var/log/nginx/error.log
```

## 🔧 高级配置选项

### 1. 负载均衡配置
```nginx
# 多实例负载均衡
upstream ess_backend {
    server 127.0.0.1:8080 weight=1 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8081 weight=1 max_fails=3 fail_timeout=30s backup;
}

server {
    listen 8443 ssl http2;
    server_name your-domain.com;

    location / {
        proxy_pass http://ess_backend;
        # 其他配置...
    }
}
```

### 2. 缓存优化配置
```nginx
# 静态资源缓存
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
    proxy_pass http://127.0.0.1:8080;
    proxy_cache_valid 200 1d;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    add_header X-Cache-Status $upstream_cache_status;
    expires 1d;
}

# API请求不缓存
location /_matrix/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_no_cache 1;
    proxy_cache_bypass 1;
}
```

### 3. 安全增强配置
```nginx
# 限制请求频率
limit_req_zone $binary_remote_addr zone=matrix_login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=matrix_api:10m rate=100r/m;

server {
    # 登录接口限制
    location /_matrix/client/r0/login {
        limit_req zone=matrix_login burst=3 nodelay;
        proxy_pass http://127.0.0.1:8080;
    }

    # API接口限制
    location /_matrix/ {
        limit_req zone=matrix_api burst=20 nodelay;
        proxy_pass http://127.0.0.1:8080;
    }
}
```

### 4. 监控和日志配置
```nginx
# 自定义日志格式
log_format matrix_log '$remote_addr - $remote_user [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     '"$http_referer" "$http_user_agent" '
                     '$request_time $upstream_response_time';

server {
    access_log /var/log/nginx/matrix_access.log matrix_log;
    error_log /var/log/nginx/matrix_error.log warn;

    # 健康检查端点
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

## 📈 性能优化建议

### 1. Nginx性能调优
```nginx
# /etc/nginx/nginx.conf
worker_processes auto;
worker_connections 1024;
keepalive_timeout 65;
keepalive_requests 100;

# 启用gzip压缩
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
```

### 2. K3s资源限制
```yaml
# 在ESS values中添加资源限制
synapse:
  resources:
    requests:
      memory: "512Mi"
      cpu: "200m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

elementWeb:
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
```

### 3. 数据库优化
```yaml
# 使用外部PostgreSQL
postgresql:
  enabled: false

synapse:
  postgres:
    host: "your-postgres-host"
    port: 5432
    database: "synapse"
    username: "synapse_user"
    password:
      secret: "postgres-secret"
      secretKey: "password"

matrixAuthenticationService:
  postgres:
    host: "your-postgres-host"
    port: 5432
    database: "mas"
    username: "mas_user"
    password:
      secret: "postgres-secret"
      secretKey: "mas_password"
```

## 🔐 SSL证书自动化

### 1. Certbot自动续期
```bash
# 安装certbot
sudo apt install certbot python3-certbot-nginx

# 获取证书
sudo certbot certonly --nginx -d your-domain.com -d app.your-domain.com -d mas.your-domain.com -d rtc.your-domain.com -d matrix.your-domain.com

# 设置自动续期
sudo crontab -e
# 添加: 0 12 * * * /usr/bin/certbot renew --quiet --reload-hook "systemctl reload nginx"
```

### 2. DNS验证方式
```bash
# 使用DNS验证（适合防火墙限制环境）
sudo certbot certonly --manual --preferred-challenges dns \
  -d your-domain.com -d "*.your-domain.com"
```

## 🌐 多域名支持

### 1. 多域名配置
```nginx
# 支持多个域名
server {
    listen 8443 ssl http2;
    server_name domain1.com app.domain1.com domain2.com app.domain2.com;

    # 根据域名路由
    if ($host ~ ^(.+\.)?domain1\.com$) {
        set $backend_host app.domain1.com;
    }
    if ($host ~ ^(.+\.)?domain2\.com$) {
        set $backend_host app.domain2.com;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $backend_host;
    }
}
```

### 2. 子域名通配符
```yaml
# ESS配置支持通配符证书
ingress:
  annotations:
    nginx.ingress.kubernetes.io/server-alias: "*.your-domain.com"
```

## 📋 部署检查清单

### 部署前检查
- [ ] 域名DNS解析配置正确
- [ ] 服务器防火墙端口开放
- [ ] 路由器端口映射配置
- [ ] SSL证书准备就绪
- [ ] K3s安装和配置完成

### 部署后验证
- [ ] ESS所有Pod运行正常
- [ ] Nginx配置测试通过
- [ ] 各服务域名访问正常
- [ ] Matrix联邦测试通过
- [ ] WebRTC通话功能正常

### 监控设置
- [ ] 日志轮转配置
- [ ] 监控告警设置
- [ ] 备份策略制定
- [ ] 性能基线建立

---

**最佳实践总结**: 这个方案提供了完整的外部Nginx反代解决方案，支持非标准端口、自定义域名和灵活的部署路径配置。通过合理的配置优化，可以获得优秀的性能和安全性。
