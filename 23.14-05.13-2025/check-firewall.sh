#!/bin/bash

# 防火墙状态检查脚本
# 检查UFW配置和端口状态

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查UFW状态
check_ufw_status() {
    print_info "=== UFW防火墙状态检查 ==="
    
    if command -v ufw >/dev/null 2>&1; then
        print_success "UFW已安装"
        
        # 检查UFW状态
        local ufw_status=$(ufw status | head -1)
        echo "UFW状态: $ufw_status"
        
        if ufw status | grep -q "Status: active"; then
            print_success "UFW防火墙已启用"
            
            echo
            print_info "UFW规则列表:"
            ufw status numbered
            
        elif ufw status | grep -q "Status: inactive"; then
            print_warning "UFW防火墙未启用"
            print_info "可以使用以下命令启用: sudo ufw enable"
        else
            print_error "无法确定UFW状态"
        fi
    else
        print_error "UFW未安装"
        print_info "可以使用以下命令安装: sudo apt install ufw"
    fi
}

# 检查iptables规则
check_iptables_rules() {
    print_info "=== iptables规则检查 ==="
    
    if command -v iptables >/dev/null 2>&1; then
        print_success "iptables可用"
        
        echo
        print_info "INPUT链规则 (前20条):"
        iptables -L INPUT -n --line-numbers | head -25
        
        echo
        print_info "检查关键端口规则:"
        
        # 检查SSH端口
        if iptables -L INPUT -n | grep -q ":22 "; then
            print_success "SSH端口(22)规则存在"
        else
            print_warning "SSH端口(22)规则可能缺失"
        fi
        
        # 检查HTTP/HTTPS端口
        local http_port="${HTTP_PORT:-8080}"
        local https_port="${HTTPS_PORT:-8443}"
        
        if iptables -L INPUT -n | grep -q ":$http_port "; then
            print_success "HTTP端口($http_port)规则存在"
        else
            print_warning "HTTP端口($http_port)规则可能缺失"
        fi
        
        if iptables -L INPUT -n | grep -q ":$https_port "; then
            print_success "HTTPS端口($https_port)规则存在"
        else
            print_warning "HTTPS端口($https_port)规则可能缺失"
        fi
        
    else
        print_error "iptables不可用"
    fi
}

# 检查端口监听状态
check_port_listening() {
    print_info "=== 端口监听状态检查 ==="
    
    if command -v netstat >/dev/null 2>&1; then
        print_info "使用netstat检查端口监听:"
        netstat -tulnp | grep -E ":(22|80|443|8080|8443|8448|30881|30882)" | sort
    elif command -v ss >/dev/null 2>&1; then
        print_info "使用ss检查端口监听:"
        ss -tulnp | grep -E ":(22|80|443|8080|8443|8448|30881|30882)" | sort
    else
        print_warning "netstat和ss都不可用，无法检查端口监听状态"
    fi
}

# 检查服务状态
check_services() {
    print_info "=== 相关服务状态检查 ==="
    
    # 检查SSH服务
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_success "SSH服务运行正常"
    else
        print_error "SSH服务未运行"
    fi
    
    # 检查Nginx服务
    if systemctl is-active --quiet nginx; then
        print_success "Nginx服务运行正常"
    else
        print_warning "Nginx服务未运行"
    fi
    
    # 检查K3s服务
    if systemctl is-active --quiet k3s; then
        print_success "K3s服务运行正常"
    else
        print_warning "K3s服务未运行"
    fi
    
    # 检查UFW服务
    if systemctl is-active --quiet ufw; then
        print_success "UFW服务运行正常"
    else
        print_warning "UFW服务未运行"
    fi
}

# 测试端口连通性
test_port_connectivity() {
    print_info "=== 端口连通性测试 ==="
    
    local test_ports=("22" "80" "443")
    
    # 添加自定义端口
    if [[ -n "${HTTP_PORT:-}" && "$HTTP_PORT" != "80" ]]; then
        test_ports+=("$HTTP_PORT")
    fi
    
    if [[ -n "${HTTPS_PORT:-}" && "$HTTPS_PORT" != "443" ]]; then
        test_ports+=("$HTTPS_PORT")
    fi
    
    if [[ -n "${FEDERATION_PORT:-}" ]]; then
        test_ports+=("$FEDERATION_PORT")
    fi
    
    for port in "${test_ports[@]}"; do
        if nc -z localhost "$port" 2>/dev/null; then
            print_success "端口 $port 可连接"
        else
            print_warning "端口 $port 不可连接"
        fi
    done
}

# 显示防火墙配置建议
show_firewall_recommendations() {
    print_info "=== 防火墙配置建议 ==="
    
    echo "基础UFW配置命令:"
    echo "sudo ufw allow ssh"
    echo "sudo ufw allow 80/tcp"
    echo "sudo ufw allow 443/tcp"
    
    if [[ -n "${HTTP_PORT:-}" && "$HTTP_PORT" != "80" ]]; then
        echo "sudo ufw allow $HTTP_PORT/tcp"
    fi
    
    if [[ -n "${HTTPS_PORT:-}" && "$HTTPS_PORT" != "443" ]]; then
        echo "sudo ufw allow $HTTPS_PORT/tcp"
    fi
    
    if [[ -n "${FEDERATION_PORT:-}" ]]; then
        echo "sudo ufw allow $FEDERATION_PORT/tcp"
    fi
    
    if [[ -n "${WEBRTC_TCP_PORT:-}" ]]; then
        echo "sudo ufw allow $WEBRTC_TCP_PORT/tcp"
    fi
    
    if [[ -n "${WEBRTC_UDP_PORT:-}" ]]; then
        echo "sudo ufw allow $WEBRTC_UDP_PORT/udp"
    fi
    
    echo "sudo ufw enable"
    
    echo
    print_info "查看UFW状态: sudo ufw status numbered"
    print_info "删除规则: sudo ufw delete [规则编号]"
    print_info "重置UFW: sudo ufw --force reset"
}

# 主函数
main() {
    print_info "=== 防火墙状态检查工具 ==="
    echo
    
    # 从配置文件读取端口设置
    if [[ -f "/opt/matrix-ess/ess-config-template.env" ]]; then
        print_info "从配置文件读取端口设置..."
        source "/opt/matrix-ess/ess-config-template.env" 2>/dev/null || true
    fi
    
    # 从环境变量设置默认值
    HTTP_PORT="${HTTP_PORT:-8080}"
    HTTPS_PORT="${HTTPS_PORT:-8443}"
    FEDERATION_PORT="${FEDERATION_PORT:-8448}"
    WEBRTC_TCP_PORT="${WEBRTC_TCP_PORT:-30881}"
    WEBRTC_UDP_PORT="${WEBRTC_UDP_PORT:-30882}"
    
    print_info "检查端口配置:"
    print_info "  HTTP端口: $HTTP_PORT"
    print_info "  HTTPS端口: $HTTPS_PORT"
    print_info "  联邦端口: $FEDERATION_PORT"
    print_info "  WebRTC TCP端口: $WEBRTC_TCP_PORT"
    print_info "  WebRTC UDP端口: $WEBRTC_UDP_PORT"
    echo
    
    # 执行检查
    check_ufw_status
    echo
    check_iptables_rules
    echo
    check_port_listening
    echo
    check_services
    echo
    test_port_connectivity
    echo
    show_firewall_recommendations
    
    print_success "防火墙检查完成！"
}

# 脚本入口
main "$@"
