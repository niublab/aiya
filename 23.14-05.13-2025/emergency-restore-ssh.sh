#!/bin/bash

# 紧急SSH连接恢复脚本
# 用于在清理脚本意外清除iptables规则后恢复SSH连接

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 恢复基础iptables规则
restore_basic_iptables() {
    print_info "恢复基础iptables规则..."
    
    # 清理现有规则
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    # 设置默认策略
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # 允许回环接口
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # 允许SSH (端口22)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # 允许HTTP和HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # 允许自定义端口 (如果设置了)
    if [[ -n "${HTTP_PORT:-}" && "$HTTP_PORT" != "80" ]]; then
        iptables -A INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT
        print_info "允许自定义HTTP端口: $HTTP_PORT"
    fi

    if [[ -n "${HTTPS_PORT:-}" && "$HTTPS_PORT" != "443" ]]; then
        iptables -A INPUT -p tcp --dport "$HTTPS_PORT" -j ACCEPT
        print_info "允许自定义HTTPS端口: $HTTPS_PORT"
    fi

    if [[ -n "${FEDERATION_PORT:-}" ]]; then
        iptables -A INPUT -p tcp --dport "$FEDERATION_PORT" -j ACCEPT
        print_info "允许联邦端口: $FEDERATION_PORT"
    fi

    # 允许WebRTC端口 (如果设置了)
    if [[ -n "${WEBRTC_TCP_PORT:-}" ]]; then
        iptables -A INPUT -p tcp --dport "$WEBRTC_TCP_PORT" -j ACCEPT
        print_info "允许WebRTC TCP端口: $WEBRTC_TCP_PORT"
    fi

    if [[ -n "${WEBRTC_UDP_PORT:-}" ]]; then
        iptables -A INPUT -p udp --dport "$WEBRTC_UDP_PORT" -j ACCEPT
        print_info "允许WebRTC UDP端口: $WEBRTC_UDP_PORT"
    fi

    # 允许WebRTC UDP端口范围 (如果设置了)
    if [[ -n "${WEBRTC_UDP_RANGE_START:-}" && -n "${WEBRTC_UDP_RANGE_END:-}" ]]; then
        iptables -A INPUT -p udp --dport "$WEBRTC_UDP_RANGE_START:$WEBRTC_UDP_RANGE_END" -j ACCEPT
        print_info "允许WebRTC UDP端口范围: $WEBRTC_UDP_RANGE_START-$WEBRTC_UDP_RANGE_END"
    fi
    
    print_success "基础iptables规则已恢复"
}

# 恢复UFW配置
restore_ufw() {
    print_info "恢复UFW防火墙配置..."

    # 检查是否需要启用UFW
    local enable_firewall="${ENABLE_FIREWALL:-false}"

    if [[ "$enable_firewall" == "true" ]]; then
        print_info "启用UFW防火墙..."

        # 重置UFW
        ufw --force reset

        # 设置默认策略
        ufw default deny incoming
        ufw default allow outgoing

        # 允许SSH
        ufw allow ssh
        ufw allow 22/tcp
    
    # 允许HTTP和HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # 允许自定义端口
    if [[ -n "${HTTP_PORT:-}" && "$HTTP_PORT" != "80" ]]; then
        ufw allow "$HTTP_PORT/tcp"
        print_info "UFW允许自定义HTTP端口: $HTTP_PORT"
    fi

    if [[ -n "${HTTPS_PORT:-}" && "$HTTPS_PORT" != "443" ]]; then
        ufw allow "$HTTPS_PORT/tcp"
        print_info "UFW允许自定义HTTPS端口: $HTTPS_PORT"
    fi

    if [[ -n "${FEDERATION_PORT:-}" ]]; then
        ufw allow "$FEDERATION_PORT/tcp"
        print_info "UFW允许联邦端口: $FEDERATION_PORT"
    fi

    # 允许WebRTC端口
    if [[ -n "${WEBRTC_TCP_PORT:-}" ]]; then
        ufw allow "$WEBRTC_TCP_PORT/tcp"
        print_info "UFW允许WebRTC TCP端口: $WEBRTC_TCP_PORT"
    fi

    if [[ -n "${WEBRTC_UDP_PORT:-}" ]]; then
        ufw allow "$WEBRTC_UDP_PORT/udp"
        print_info "UFW允许WebRTC UDP端口: $WEBRTC_UDP_PORT"
    fi

    # 允许WebRTC UDP端口范围
    if [[ -n "${WEBRTC_UDP_RANGE_START:-}" && -n "${WEBRTC_UDP_RANGE_END:-}" ]]; then
        ufw allow "$WEBRTC_UDP_RANGE_START:$WEBRTC_UDP_RANGE_END/udp"
        print_info "UFW允许WebRTC UDP端口范围: $WEBRTC_UDP_RANGE_START-$WEBRTC_UDP_RANGE_END"
    fi
    
        # 启用UFW
        ufw --force enable

        print_success "UFW防火墙配置已恢复"
    else
        print_info "ENABLE_FIREWALL=false，跳过UFW配置"
        print_info "如果UFW已启用，将保持当前状态"

        if ufw status | grep -q "Status: active"; then
            print_info "UFW当前状态:"
            ufw status numbered
        else
            print_info "UFW当前未启用"
        fi
    fi
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    
    # 检查网络接口
    print_info "网络接口状态:"
    ip addr show | grep -E "^[0-9]+:|inet "
    
    # 检查路由
    print_info "路由表:"
    ip route show
    
    # 检查DNS
    print_info "DNS解析测试:"
    nslookup google.com || print_warning "DNS解析可能有问题"
    
    print_success "网络检查完成"
}

# 恢复网络服务
restore_network_services() {
    print_info "重启网络相关服务..."
    
    # 重启网络服务
    systemctl restart networking || true
    systemctl restart systemd-networkd || true
    systemctl restart systemd-resolved || true
    
    # 重启SSH服务
    systemctl restart ssh || systemctl restart sshd || true
    
    print_success "网络服务已重启"
}

# 显示恢复状态
show_status() {
    print_info "=== 恢复状态检查 ==="
    
    # SSH服务状态
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_success "SSH服务运行正常"
    else
        print_error "SSH服务未运行"
    fi
    
    # 防火墙状态
    if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
        print_success "UFW防火墙已启用"
        ufw status numbered
    else
        print_warning "UFW防火墙未启用或不可用"
    fi
    
    # iptables规则
    print_info "当前iptables规则:"
    iptables -L -n | head -20
    
    print_info "=== 恢复完成 ==="
    print_success "SSH连接应该已经恢复"
    print_info "如果仍无法连接，请检查:"
    print_info "1. 网络连接是否正常"
    print_info "2. SSH服务是否运行"
    print_info "3. 防火墙规则是否正确"
    print_info "4. 路由器端口映射是否正确"
}

# 主函数
main() {
    print_info "=== 紧急SSH连接恢复脚本 ==="
    print_warning "此脚本将恢复基础网络和SSH连接"
    
    check_root
    
    # 从环境变量或配置文件读取端口
    if [[ -f "/opt/matrix-ess/ess-config-template.env" ]]; then
        print_info "从配置文件读取端口设置..."
        source "/opt/matrix-ess/ess-config-template.env" || true
    fi
    
    # 恢复网络连接
    restore_basic_iptables
    restore_ufw
    restore_network_services
    check_network
    
    # 显示状态
    show_status
    
    print_success "紧急恢复完成！"
}

# 脚本入口
main "$@"
