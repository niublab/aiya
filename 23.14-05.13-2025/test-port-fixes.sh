#!/bin/bash

# ESS端口修复测试脚本
# 用于验证所有配置文件中的端口是否正确设置

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $timestamp - $message" >&2
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $timestamp - $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $timestamp - $message"
            ;;
        *)
            echo "$timestamp - $message"
            ;;
    esac
}

# 配置变量
DOMAIN="${DOMAIN:-your-domain.com}"
HTTP_PORT="${HTTP_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
FEDERATION_PORT="${FEDERATION_PORT:-8448}"
WEB_SUBDOMAIN="${WEB_SUBDOMAIN:-app}"
AUTH_SUBDOMAIN="${AUTH_SUBDOMAIN:-mas}"
RTC_SUBDOMAIN="${RTC_SUBDOMAIN:-rtc}"
MATRIX_SUBDOMAIN="${MATRIX_SUBDOMAIN:-matrix}"
NAMESPACE="${NAMESPACE:-ess}"

# 测试well-known端点
test_wellknown_endpoints() {
    log "INFO" "测试well-known端点..."
    
    local errors=0
    
    # 测试Matrix服务器发现
    log "INFO" "测试 /.well-known/matrix/server"
    local server_url="https://localhost:$HTTPS_PORT/.well-known/matrix/server"
    local server_response=$(curl -s -k "$server_url" 2>/dev/null || echo "ERROR")
    
    if [[ "$server_response" == "ERROR" ]]; then
        log "ERROR" "无法访问Matrix服务器发现端点"
        ((errors++))
    elif [[ "$server_response" == *"$MATRIX_SUBDOMAIN.$DOMAIN:$FEDERATION_PORT"* ]]; then
        log "SUCCESS" "Matrix服务器发现端点配置正确"
    else
        log "WARNING" "Matrix服务器发现端点可能配置错误"
        log "INFO" "期望包含: $MATRIX_SUBDOMAIN.$DOMAIN:$FEDERATION_PORT"
        log "INFO" "实际响应: $server_response"
        ((errors++))
    fi
    
    # 测试Matrix客户端配置
    log "INFO" "测试 /.well-known/matrix/client"
    local client_url="https://localhost:$HTTPS_PORT/.well-known/matrix/client"
    local client_response=$(curl -s -k "$client_url" 2>/dev/null || echo "ERROR")
    
    if [[ "$client_response" == "ERROR" ]]; then
        log "ERROR" "无法访问Matrix客户端配置端点"
        ((errors++))
    elif [[ "$client_response" == *"$MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"* ]]; then
        log "SUCCESS" "Matrix客户端配置端点配置正确"
    else
        log "WARNING" "Matrix客户端配置端点可能配置错误"
        log "INFO" "期望包含: $MATRIX_SUBDOMAIN.$DOMAIN:$HTTPS_PORT"
        log "INFO" "实际响应: $client_response"
        ((errors++))
    fi
    
    return $errors
}

# 测试HTTP重定向
test_http_redirect() {
    log "INFO" "测试HTTP重定向..."
    
    local errors=0
    
    # 测试主域名重定向
    for subdomain in "" "$WEB_SUBDOMAIN." "$AUTH_SUBDOMAIN." "$RTC_SUBDOMAIN." "$MATRIX_SUBDOMAIN."; do
        local test_domain="${subdomain}${DOMAIN}"
        local test_url="http://$test_domain:$HTTP_PORT"
        
        log "INFO" "测试重定向: $test_url"
        local response=$(curl -s -I "$test_url" -H "Host: $test_domain" 2>/dev/null | head -1 || echo "ERROR")
        
        if [[ "$response" == "ERROR" ]]; then
            log "ERROR" "无法访问 $test_url"
            ((errors++))
        elif [[ "$response" == *"301"* ]] || [[ "$response" == *"302"* ]]; then
            log "SUCCESS" "$test_domain HTTP重定向正常"
        else
            log "WARNING" "$test_domain HTTP重定向可能有问题"
            log "INFO" "响应: $response"
            ((errors++))
        fi
    done
    
    return $errors
}

# 测试HTTPS访问
test_https_access() {
    log "INFO" "测试HTTPS访问..."
    
    local errors=0
    
    # 测试各子域名HTTPS访问
    for subdomain in "" "$WEB_SUBDOMAIN." "$AUTH_SUBDOMAIN." "$RTC_SUBDOMAIN." "$MATRIX_SUBDOMAIN."; do
        local test_domain="${subdomain}${DOMAIN}"
        local test_url="https://$test_domain:$HTTPS_PORT"
        
        log "INFO" "测试HTTPS访问: $test_url"
        local response=$(curl -s -k -I "$test_url" -H "Host: $test_domain" 2>/dev/null | head -1 || echo "ERROR")
        
        if [[ "$response" == "ERROR" ]]; then
            log "ERROR" "无法访问 $test_url"
            ((errors++))
        elif [[ "$response" == *"200"* ]] || [[ "$response" == *"301"* ]] || [[ "$response" == *"302"* ]]; then
            log "SUCCESS" "$test_domain HTTPS访问正常"
        else
            log "WARNING" "$test_domain HTTPS访问可能有问题"
            log "INFO" "响应: $response"
            ((errors++))
        fi
    done
    
    return $errors
}

# 检查Kubernetes配置
check_k8s_config() {
    log "INFO" "检查Kubernetes配置..."
    
    local errors=0
    
    # 检查Pod状态
    if ! kubectl get pods -n "$NAMESPACE" &>/dev/null; then
        log "ERROR" "无法访问Kubernetes集群或命名空间不存在"
        return 1
    fi
    
    local running_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep Running | wc -l)
    local total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
    
    log "INFO" "Pod状态: $running_pods/$total_pods 运行中"
    
    if [[ $running_pods -eq $total_pods ]] && [[ $total_pods -gt 0 ]]; then
        log "SUCCESS" "所有Pod运行正常"
    else
        log "WARNING" "部分Pod可能有问题"
        kubectl get pods -n "$NAMESPACE"
        ((errors++))
    fi
    
    # 检查ConfigMap中的配置
    log "INFO" "检查ConfigMap配置..."
    local configmaps=$(kubectl get configmap -n "$NAMESPACE" -o name 2>/dev/null || true)
    
    for cm in $configmaps; do
        log "INFO" "检查 $cm"
        
        # 检查是否包含错误的端口配置
        if kubectl get "$cm" -n "$NAMESPACE" -o yaml | grep -q ":443\|:80\|:8448" | grep -v ":$HTTP_PORT\|:$HTTPS_PORT\|:$FEDERATION_PORT"; then
            log "WARNING" "$cm 可能包含硬编码端口"
            ((errors++))
        fi
    done
    
    return $errors
}

# 检查Nginx配置
check_nginx_config() {
    log "INFO" "检查Nginx配置..."
    
    local errors=0
    local nginx_config="/etc/nginx/sites-available/matrix-ess"
    
    if [[ ! -f "$nginx_config" ]]; then
        log "ERROR" "Nginx配置文件不存在: $nginx_config"
        return 1
    fi
    
    # 检查端口配置
    if grep -q "listen $HTTP_PORT" "$nginx_config" && grep -q "listen $HTTPS_PORT" "$nginx_config"; then
        log "SUCCESS" "Nginx端口配置正确"
    else
        log "ERROR" "Nginx端口配置错误"
        ((errors++))
    fi
    
    # 检查域名配置
    local expected_domains=("$DOMAIN" "$WEB_SUBDOMAIN.$DOMAIN" "$AUTH_SUBDOMAIN.$DOMAIN" "$RTC_SUBDOMAIN.$DOMAIN" "$MATRIX_SUBDOMAIN.$DOMAIN")
    
    for domain in "${expected_domains[@]}"; do
        if grep -q "$domain" "$nginx_config"; then
            log "SUCCESS" "域名 $domain 在Nginx配置中"
        else
            log "WARNING" "域名 $domain 可能不在Nginx配置中"
            ((errors++))
        fi
    done
    
    # 测试Nginx配置语法
    if nginx -t &>/dev/null; then
        log "SUCCESS" "Nginx配置语法正确"
    else
        log "ERROR" "Nginx配置语法错误"
        ((errors++))
    fi
    
    return $errors
}

# 主测试函数
main() {
    log "INFO" "开始ESS端口配置测试..."
    log "INFO" "测试域名: $DOMAIN"
    log "INFO" "测试端口: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, 联邦=$FEDERATION_PORT"
    
    local total_errors=0
    
    # 运行所有测试
    test_wellknown_endpoints || ((total_errors += $?))
    echo
    
    test_http_redirect || ((total_errors += $?))
    echo
    
    test_https_access || ((total_errors += $?))
    echo
    
    check_nginx_config || ((total_errors += $?))
    echo
    
    check_k8s_config || ((total_errors += $?))
    echo
    
    # 总结
    if [[ $total_errors -eq 0 ]]; then
        log "SUCCESS" "所有测试通过！端口配置正确。"
        exit 0
    else
        log "ERROR" "发现 $total_errors 个问题，请检查配置。"
        exit 1
    fi
}

# 脚本入口 - 直接执行主函数 (支持bash <(curl)方式)
main "$@"
