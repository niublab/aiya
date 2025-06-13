#!/bin/bash

# IP自动更新脚本
# 使用dig命令获取公网IP并更新相关服务配置
# 作者: Matrix ESS 部署脚本
# 版本: 1.0.0

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/ip-update.conf"
DOMAINS_FILE="${BASE_DIR}/config/domains.conf"
LOG_FILE="${BASE_DIR}/logs/ip-update.log"
BACKUP_DIR="${BASE_DIR}/backup"
TEMPLATES_DIR="${BASE_DIR}/templates"

# 默认配置
DEFAULT_DDNS_DOMAIN="ip.example.com"
DEFAULT_UPDATE_INTERVAL="300"
DEFAULT_DNS_SERVERS=("8.8.8.8" "1.1.1.1")
DEFAULT_SERVICES_TO_RELOAD=("nginx" "matrix-ess")
DEFAULT_BACKUP_ENABLED="true"
DEFAULT_LOG_LEVEL="INFO"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 输出到日志文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # 根据级别输出到控制台
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
    esac
}

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "DEBUG" "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log "WARN" "配置文件不存在，使用默认配置: $CONFIG_FILE"
    fi
    
    # 设置默认值
    DDNS_DOMAIN="${DDNS_DOMAIN:-$DEFAULT_DDNS_DOMAIN}"
    UPDATE_INTERVAL="${UPDATE_INTERVAL:-$DEFAULT_UPDATE_INTERVAL}"
    BACKUP_ENABLED="${BACKUP_ENABLED:-$DEFAULT_BACKUP_ENABLED}"
    LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
    
    # DNS服务器数组
    if [[ -z "${DNS_SERVERS:-}" ]]; then
        DNS_SERVERS=("${DEFAULT_DNS_SERVERS[@]}")
    fi
    
    # 需要重载的服务数组
    if [[ -z "${SERVICES_TO_RELOAD:-}" ]]; then
        SERVICES_TO_RELOAD=("${DEFAULT_SERVICES_TO_RELOAD[@]}")
    fi
    
    log "DEBUG" "配置加载完成 - DDNS域名: $DDNS_DOMAIN"
}

# 获取当前公网IP - 严格使用dig命令
get_current_ip() {
    local current_ip=""
    local dns_server=""
    
    log "DEBUG" "开始获取公网IP地址..."
    
    # 遍历DNS服务器
    for dns_server in "${DNS_SERVERS[@]}"; do
        log "DEBUG" "尝试使用DNS服务器: $dns_server"
        
        # 使用dig命令获取IP - 严格按照要求
        if current_ip=$(dig +short "$DDNS_DOMAIN" @"$dns_server" 2>/dev/null); then
            # 验证返回的是有效IP地址
            if [[ $current_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log "SUCCESS" "成功获取IP地址: $current_ip (DNS: $dns_server)"
                echo "$current_ip"
                return 0
            else
                log "WARN" "DNS服务器 $dns_server 返回无效IP: $current_ip"
            fi
        else
            log "WARN" "DNS服务器 $dns_server 查询失败"
        fi
    done
    
    log "ERROR" "所有DNS服务器查询失败，无法获取IP地址"
    return 1
}

# 获取上次记录的IP
get_last_ip() {
    local last_ip_file="${BASE_DIR}/config/last_ip"
    
    if [[ -f "$last_ip_file" ]]; then
        cat "$last_ip_file"
    else
        echo ""
    fi
}

# 保存当前IP
save_current_ip() {
    local ip="$1"
    local last_ip_file="${BASE_DIR}/config/last_ip"
    
    echo "$ip" > "$last_ip_file"
    log "DEBUG" "IP地址已保存: $ip"
}

# 备份配置文件
backup_config() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_subdir="${BACKUP_DIR}/${timestamp}"
    
    log "INFO" "创建配置备份..."
    mkdir -p "$backup_subdir"
    
    # 备份Nginx配置
    if [[ -f "/etc/nginx/sites-available/matrix-ess" ]]; then
        cp "/etc/nginx/sites-available/matrix-ess" "$backup_subdir/nginx-matrix-ess.conf"
        log "DEBUG" "已备份Nginx配置"
    fi
    
    # 备份ESS配置
    if [[ -f "/opt/matrix-ess/ess-values.yaml" ]]; then
        cp "/opt/matrix-ess/ess-values.yaml" "$backup_subdir/ess-values.yaml"
        log "DEBUG" "已备份ESS配置"
    fi
    
    # 清理旧备份 (保留最近10个)
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" | sort -r | tail -n +11 | xargs rm -rf 2>/dev/null || true
    
    log "SUCCESS" "配置备份完成: $backup_subdir"
}

# 更新Nginx配置
update_nginx_config() {
    local new_ip="$1"
    local nginx_config="/etc/nginx/sites-available/matrix-ess"
    local nginx_template="${TEMPLATES_DIR}/nginx.conf.template"
    
    if [[ ! -f "$nginx_config" ]]; then
        log "WARN" "Nginx配置文件不存在: $nginx_config"
        return 0
    fi
    
    log "INFO" "更新Nginx配置中的IP地址..."
    
    # 如果有模板文件，使用模板生成
    if [[ -f "$nginx_template" ]]; then
        log "DEBUG" "使用模板生成Nginx配置"
        sed "s/{{PUBLIC_IP}}/$new_ip/g" "$nginx_template" > "$nginx_config"
    else
        # 直接替换现有配置中的IP
        log "DEBUG" "直接替换Nginx配置中的IP"
        # 这里可以根据具体的Nginx配置格式进行替换
        # 示例：替换 set $public_ip "old_ip"; 为 set $public_ip "new_ip";
        sed -i "s/set \$public_ip \"[^\"]*\";/set \$public_ip \"$new_ip\";/g" "$nginx_config" || true
    fi
    
    # 测试Nginx配置
    if nginx -t 2>/dev/null; then
        log "SUCCESS" "Nginx配置更新成功"
        return 0
    else
        log "ERROR" "Nginx配置测试失败"
        return 1
    fi
}

# 更新ESS配置
update_ess_config() {
    local new_ip="$1"
    local ess_config="/opt/matrix-ess/ess-values.yaml"
    local ess_template="${TEMPLATES_DIR}/ess-values.template"
    
    if [[ ! -f "$ess_config" ]]; then
        log "WARN" "ESS配置文件不存在: $ess_config"
        return 0
    fi
    
    log "INFO" "更新ESS配置中的IP地址..."
    
    # 如果有模板文件，使用模板生成
    if [[ -f "$ess_template" ]]; then
        log "DEBUG" "使用模板生成ESS配置"
        sed "s/{{PUBLIC_IP}}/$new_ip/g" "$ess_template" > "$ess_config"
    else
        # 直接替换现有配置中的IP
        log "DEBUG" "直接替换ESS配置中的IP"
        # 替换YAML配置中的IP地址
        sed -i "s/publicIP: \"[^\"]*\"/publicIP: \"$new_ip\"/g" "$ess_config" || true
        sed -i "s/externalIP: \"[^\"]*\"/externalIP: \"$new_ip\"/g" "$ess_config" || true
    fi
    
    log "SUCCESS" "ESS配置更新成功"
}

# 重载服务
reload_services() {
    log "INFO" "重载相关服务..."
    
    for service in "${SERVICES_TO_RELOAD[@]}"; do
        log "DEBUG" "重载服务: $service"
        
        case "$service" in
            "nginx")
                if systemctl is-active --quiet nginx; then
                    if systemctl reload nginx; then
                        log "SUCCESS" "Nginx服务重载成功"
                    else
                        log "ERROR" "Nginx服务重载失败"
                    fi
                else
                    log "WARN" "Nginx服务未运行"
                fi
                ;;
            "matrix-ess"|"ess")
                # 重新部署ESS
                if command -v helm &> /dev/null; then
                    if helm upgrade ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
                        -f /opt/matrix-ess/ess-values.yaml -n ess 2>/dev/null; then
                        log "SUCCESS" "ESS服务重载成功"
                    else
                        log "ERROR" "ESS服务重载失败"
                    fi
                else
                    log "WARN" "Helm未安装，跳过ESS重载"
                fi
                ;;
            "docker-"*)
                # Docker容器重启
                local container_name="${service#docker-}"
                if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
                    if docker restart "$container_name" &>/dev/null; then
                        log "SUCCESS" "Docker容器 $container_name 重启成功"
                    else
                        log "ERROR" "Docker容器 $container_name 重启失败"
                    fi
                else
                    log "WARN" "Docker容器 $container_name 不存在或未运行"
                fi
                ;;
            *)
                # 通用systemd服务
                if systemctl is-active --quiet "$service"; then
                    if systemctl reload-or-restart "$service"; then
                        log "SUCCESS" "服务 $service 重载成功"
                    else
                        log "ERROR" "服务 $service 重载失败"
                    fi
                else
                    log "WARN" "服务 $service 未运行"
                fi
                ;;
        esac
    done
}

# 发送通知
send_notification() {
    local old_ip="$1"
    local new_ip="$2"
    
    # 这里可以添加各种通知方式
    # 例如：邮件、Webhook、Telegram等
    
    log "INFO" "IP地址已更新: $old_ip -> $new_ip"
    
    # 示例：写入系统日志
    logger "Matrix ESS IP更新: $old_ip -> $new_ip"
}

# 主更新函数
update_ip() {
    log "INFO" "开始IP更新检查..."
    
    # 获取当前IP
    local current_ip
    if ! current_ip=$(get_current_ip); then
        log "ERROR" "无法获取当前IP地址"
        return 1
    fi
    
    # 获取上次记录的IP
    local last_ip
    last_ip=$(get_last_ip)
    
    log "DEBUG" "当前IP: $current_ip, 上次IP: $last_ip"
    
    # 检查IP是否发生变化
    if [[ "$current_ip" == "$last_ip" ]]; then
        log "INFO" "IP地址未发生变化: $current_ip"
        return 0
    fi
    
    log "INFO" "检测到IP地址变化: $last_ip -> $current_ip"
    
    # 备份配置
    backup_config
    
    # 更新配置文件
    update_nginx_config "$current_ip"
    update_ess_config "$current_ip"
    
    # 重载服务
    reload_services
    
    # 保存新IP
    save_current_ip "$current_ip"
    
    # 发送通知
    send_notification "$last_ip" "$current_ip"
    
    log "SUCCESS" "IP更新完成: $current_ip"
}

# 检查配置
check_config() {
    log "INFO" "检查配置..."
    
    # 检查必要的目录
    for dir in "$BASE_DIR" "$BACKUP_DIR" "$(dirname "$LOG_FILE")"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR" "目录不存在: $dir"
            return 1
        fi
    done
    
    # 检查DDNS域名
    if [[ -z "$DDNS_DOMAIN" ]]; then
        log "ERROR" "DDNS域名未配置"
        return 1
    fi
    
    # 测试DNS查询
    if ! get_current_ip >/dev/null; then
        log "ERROR" "DNS查询测试失败"
        return 1
    fi
    
    log "SUCCESS" "配置检查通过"
}

# 显示帮助信息
show_help() {
    cat << EOF
IP自动更新脚本

用法: $0 [选项]

选项:
    --update        执行IP更新检查
    --check-config  检查配置
    --test          测试模式（不实际更新）
    --debug         启用调试模式
    --help          显示此帮助信息

示例:
    $0 --update         # 执行IP更新
    $0 --test --debug   # 调试模式测试
    $0 --check-config   # 检查配置

配置文件: $CONFIG_FILE
日志文件: $LOG_FILE
EOF
}

# 主函数
main() {
    # 创建必要的目录
    mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR" "${BASE_DIR}/config"
    
    # 加载配置
    load_config
    
    # 解析命令行参数
    local action="update"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --update)
                action="update"
                shift
                ;;
            --check-config)
                action="check"
                shift
                ;;
            --test)
                TEST_MODE="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 执行相应操作
    case "$action" in
        "update")
            if [[ "${TEST_MODE:-false}" == "true" ]]; then
                log "INFO" "测试模式 - 不会实际更新配置"
                get_current_ip
            else
                update_ip
            fi
            ;;
        "check")
            check_config
            ;;
        *)
            log "ERROR" "未知操作: $action"
            exit 1
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
