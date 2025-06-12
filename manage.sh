#!/bin/bash

# Matrix ESS Community 管理工具
# 版本: 1.2.0
# 用途: 管理已部署的Matrix ESS实例
# 命令: manage

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# 配置文件路径
readonly INSTALL_DIR="/opt/matrix"
readonly CONFIG_FILE="$INSTALL_DIR/matrix-config.env"

# 打印函数
print_header() {
    echo -e "\n${BLUE}==================== $1 ====================${NC}\n"
}

print_step() {
    echo -e "${WHITE}>>> $1${NC}\n"
}

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查环境
check_environment() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi

    # 检查配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "未找到配置文件: $CONFIG_FILE"
        print_info "请先运行部署脚本完成Matrix ESS部署"
        exit 1
    fi

    # 检查k3s
    if ! command -v k3s &> /dev/null; then
        print_error "未找到k3s命令，请确保Matrix ESS已正确部署"
        exit 1
    fi

    # 检查ess命名空间
    if ! k3s kubectl get namespace ess &> /dev/null; then
        print_error "未找到ess命名空间，请确保Matrix ESS已正确部署"
        exit 1
    fi

    # 加载配置
    source "$CONFIG_FILE" 2>/dev/null || true
}

# 获取MAS Pod名称
get_mas_pod() {
    k3s kubectl get pods -n ess -l app.kubernetes.io/name=matrix-authentication-service --no-headers -o custom-columns=":metadata.name" | head -1
}

# 主菜单
main_menu() {
    while true; do
        clear
        print_header "Matrix ESS Community 管理工具 v1.1.0"
        echo -e "${WHITE}当前服务器:${NC} $SERVER_NAME"
        echo -e "${WHITE}Element Web:${NC} https://$WEB_HOST:$HTTPS_PORT"
        echo
        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 用户管理"
        echo -e "  ${GREEN}2)${NC} 系统配置"
        echo -e "  ${GREEN}3)${NC} 服务管理"
        echo -e "  ${GREEN}4)${NC} 系统诊断"
        echo -e "  ${GREEN}5)${NC} 查看系统信息"
        echo -e "  ${RED}0)${NC} 退出"
        echo
        read -p "请选择操作 (0-5): " choice

        case $choice in
            1) user_management_menu ;;
            2) system_config_menu ;;
            3) service_management_menu ;;
            4) system_diagnostics_menu ;;
            5) show_system_info ;;
            0) 
                print_info "退出管理工具"
                exit 0
                ;;
            *) 
                print_error "无效选择，请输入 0-5"
                sleep 2
                ;;
        esac
    done
}

# 用户管理菜单
user_management_menu() {
    while true; do
        clear
        print_header "用户管理"
        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 创建普通用户"
        echo -e "  ${GREEN}2)${NC} 创建管理员用户"
        echo -e "  ${GREEN}3)${NC} 设置用户密码"
        echo -e "  ${GREEN}4)${NC} 锁定用户"
        echo -e "  ${GREEN}5)${NC} 解锁用户"
        echo -e "  ${GREEN}6)${NC} 添加用户邮箱"
        echo -e "  ${GREEN}7)${NC} 查看用户列表"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        read -p "请选择操作 (0-7): " choice

        case $choice in
            1)
                create_user_interactive
                ;;
            2)
                create_admin_user_interactive
                ;;
            3)
                set_user_password_interactive
                ;;
            4)
                lock_user_interactive
                ;;
            5)
                unlock_user_interactive
                ;;
            6)
                add_user_email_interactive
                ;;
            7)
                list_users
                ;;
            0) break ;;
            *)
                print_error "无效选择，请输入 0-7"
                sleep 2
                ;;
        esac
    done
}

# 系统配置菜单
system_config_menu() {
    while true; do
        clear
        print_header "系统配置"
        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 查看注册状态"
        echo -e "  ${GREEN}2)${NC} 查看当前配置"
        echo -e "  ${GREEN}3)${NC} 修复Well-known配置"
        echo -e "  ${GREEN}4)${NC} 修复Element Web配置"
        echo -e "  ${GREEN}5)${NC} 重新申请SSL证书"
        echo -e "  ${GREEN}6)${NC} 更新系统配置"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        read -p "请选择操作 (0-6): " choice

        case $choice in
            1)
                show_registration_status
                read -p "按回车键继续..."
                ;;
            2)
                show_current_config
                read -p "按回车键继续..."
                ;;
            3)
                fix_wellknown_configuration
                read -p "按回车键继续..."
                ;;
            4)
                fix_element_web_configuration
                read -p "按回车键继续..."
                ;;
            5)
                recreate_ssl_certificates
                read -p "按回车键继续..."
                ;;
            6)
                update_system_config
                read -p "按回车键继续..."
                ;;
            0) break ;;
            *)
                print_error "无效选择，请输入 0-6"
                sleep 2
                ;;
        esac
    done
}

# 服务管理菜单
service_management_menu() {
    while true; do
        clear
        print_header "服务管理"
        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 查看服务状态"
        echo -e "  ${GREEN}2)${NC} 重启所有服务"
        echo -e "  ${GREEN}3)${NC} 重启Element Web"
        echo -e "  ${GREEN}4)${NC} 重启认证服务"
        echo -e "  ${GREEN}5)${NC} 重启Synapse"
        echo -e "  ${GREEN}6)${NC} 查看服务日志"
        echo -e "  ${GREEN}7)${NC} 清理重启Pod"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        read -p "请选择操作 (0-7): " choice

        case $choice in
            1)
                show_service_status
                read -p "按回车键继续..."
                ;;
            2)
                restart_all_services
                read -p "按回车键继续..."
                ;;
            3)
                restart_element_web
                read -p "按回车键继续..."
                ;;
            4)
                restart_auth_service
                read -p "按回车键继续..."
                ;;
            5)
                restart_synapse
                read -p "按回车键继续..."
                ;;
            6)
                show_service_logs
                ;;
            7)
                cleanup_restart_pods
                read -p "按回车键继续..."
                ;;
            0) break ;;
            *)
                print_error "无效选择，请输入 0-7"
                sleep 2
                ;;
        esac
    done
}

# 系统诊断菜单
system_diagnostics_menu() {
    while true; do
        clear
        print_header "系统诊断"
        echo -e "${WHITE}请选择操作:${NC}"
        echo -e "  ${GREEN}1)${NC} 完整系统检查"
        echo -e "  ${GREEN}2)${NC} 网络连通性测试"
        echo -e "  ${GREEN}3)${NC} SSL证书检查"
        echo -e "  ${GREEN}4)${NC} Well-known配置检查"
        echo -e "  ${GREEN}5)${NC} 服务健康检查"
        echo -e "  ${GREEN}6)${NC} 存储空间检查"
        echo -e "  ${GREEN}7)${NC} 性能监控"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo
        read -p "请选择操作 (0-7): " choice

        case $choice in
            1)
                full_system_check
                read -p "按回车键继续..."
                ;;
            2)
                network_connectivity_test
                read -p "按回车键继续..."
                ;;
            3)
                ssl_certificate_check
                read -p "按回车键继续..."
                ;;
            4)
                wellknown_config_check
                read -p "按回车键继续..."
                ;;
            5)
                service_health_check
                read -p "按回车键继续..."
                ;;
            6)
                storage_space_check
                read -p "按回车键继续..."
                ;;
            7)
                performance_monitoring
                read -p "按回车键继续..."
                ;;
            0) break ;;
            *)
                print_error "无效选择，请输入 0-7"
                sleep 2
                ;;
        esac
    done
}

# 检查环境并启动主菜单
main() {
    check_environment
    main_menu
}

# 创建普通用户
create_user_interactive() {
    print_step "创建新用户"

    read -p "请输入用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    read -s -p "请输入密码: " password
    echo
    if [[ -z "$password" ]]; then
        print_error "密码不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_info "创建用户: $username"
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage register-user \
        --yes \
        "$username" \
        --password "$password"; then
        print_success "用户 $username 创建成功"
        print_info "Matrix ID: @$username:$SERVER_NAME"
    else
        print_error "用户创建失败"
    fi
}

# 创建管理员用户
create_admin_user_interactive() {
    print_step "创建管理员用户"

    read -p "请输入管理员用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    read -s -p "请输入密码: " password
    echo
    if [[ -z "$password" ]]; then
        print_error "密码不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_info "创建管理员用户: $username"
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage register-user \
        --yes \
        "$username" \
        --password "$password" \
        --admin; then
        print_success "管理员用户 $username 创建成功"
        print_info "Matrix ID: @$username:$SERVER_NAME"
    else
        print_error "管理员用户创建失败"
    fi

    read -p "按回车键继续..."
}

# 设置用户密码
set_user_password_interactive() {
    print_step "设置用户密码"

    read -p "请输入用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    read -s -p "请输入新密码: " password
    echo
    if [[ -z "$password" ]]; then
        print_error "密码不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_info "设置用户 $username 的密码..."
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    # 修正命令格式：set-password 需要用户名作为位置参数
    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage set-password \
        --password "$password" \
        "$username"; then
        print_success "用户 $username 密码设置成功"
    else
        print_error "密码设置失败"
    fi

    read -p "按回车键继续..."
}

# 锁定用户
lock_user_interactive() {
    print_step "锁定用户"

    read -p "请输入要锁定的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_warning "确认要锁定用户 $username 吗？"
    read -p "输入 'yes' 确认: " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "操作已取消"
        read -p "按回车键继续..."
        return 0
    fi

    print_info "锁定用户: $username"
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage lock-user \
        "$username"; then
        print_success "用户 $username 已被锁定"
    else
        print_error "用户锁定失败"
    fi

    read -p "按回车键继续..."
}

# 解锁用户
unlock_user_interactive() {
    print_step "解锁用户"

    read -p "请输入要解锁的用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_info "解锁用户: $username"
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage unlock-user \
        "$username"; then
        print_success "用户 $username 已被解锁"
    else
        print_error "用户解锁失败"
    fi

    read -p "按回车键继续..."
}

# 添加用户邮箱
add_user_email_interactive() {
    print_step "添加用户邮箱"

    read -p "请输入用户名: " username
    if [[ -z "$username" ]]; then
        print_error "用户名不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    read -p "请输入邮箱地址: " email
    if [[ -z "$email" ]]; then
        print_error "邮箱地址不能为空"
        read -p "按回车键继续..."
        return 1
    fi

    print_info "为用户 $username 添加邮箱: $email"
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    if k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage add-email \
        "$username" \
        --email "$email"; then
        print_success "邮箱添加成功"
    else
        print_error "邮箱添加失败"
    fi

    read -p "按回车键继续..."
}

# 查看用户列表
list_users() {
    print_step "查看用户列表"

    print_info "获取用户列表..."
    local mas_pod=$(get_mas_pod)

    if [[ -z "$mas_pod" ]]; then
        print_error "未找到MAS服务Pod"
        read -p "按回车键继续..."
        return 1
    fi

    # 使用Synapse Admin API获取用户列表（MAS环境下仍然可用）
    print_info "通过Synapse Admin API获取用户列表..."

    # 尝试获取管理员令牌
    print_info "生成管理员访问令牌..."
    local admin_token=$(k3s kubectl exec -n ess "$mas_pod" -- \
        mas-cli manage issue-compatibility-token \
        --yes-i-want-to-grant-synapse-admin-privileges \
        2>/dev/null | grep -o 'syt_[^[:space:]]*' | head -1)

    if [[ -n "$admin_token" ]]; then
        print_info "获取用户列表..."
        # 使用Synapse Admin API
        local synapse_url="http://ess-synapse:8008"
        k3s kubectl exec -n ess "$mas_pod" -- \
            curl -s -H "Authorization: Bearer $admin_token" \
            "$synapse_url/_synapse/admin/v2/users?limit=50" | jq -r '.users[] | "\(.name) - \(.displayname // "无显示名") - 管理员: \(.admin) - 已停用: \(.deactivated)"' 2>/dev/null || {
            print_warning "无法获取用户列表，请检查Synapse Admin API"
        }
    else
        print_warning "无法生成管理员令牌"
        print_info "您可以通过以下方式查看用户："
        echo "1. 登录Element Web管理界面"
        echo "2. 使用Synapse Admin工具"
        echo "3. 直接查询数据库"
    fi

    read -p "按回车键继续..."
}

# 查看注册状态
show_registration_status() {
    print_step "查看用户注册状态"

    # 检查当前状态
    local current_status=$(k3s kubectl get configmap ess-element-web -n ess -o jsonpath='{.data.config\.json}' | jq -r '.setting_defaults."UIFeature.registration"' 2>/dev/null)

    echo -e "${WHITE}当前注册状态:${NC}"
    if [[ "$current_status" == "true" ]]; then
        echo -e "  ${GREEN}✓ 用户注册已启用${NC}"
        echo "  用户可以在Element Web中自行注册账户"
    else
        echo -e "  ${RED}✗ 用户注册已禁用${NC}"
        echo "  只能由管理员手动创建用户账户"
    fi

    echo
    echo -e "${WHITE}注册方式说明:${NC}"
    echo "1. Element Web注册 - 通过Web界面自助注册"
    echo "2. 管理员创建 - 使用本工具的用户管理功能"
    echo "3. 外部SSO - 配置第三方身份提供商"
    echo
    print_info "注意: MAS环境下不支持注册令牌功能"
}



# 查看当前配置
show_current_config() {
    print_step "当前系统配置"

    echo -e "${WHITE}基本信息:${NC}"
    echo "服务器名: $SERVER_NAME"
    echo "Element Web: https://$WEB_HOST:$HTTPS_PORT"
    echo "认证服务: https://$AUTH_HOST:$HTTPS_PORT"
    echo "RTC服务: https://$RTC_HOST:$HTTPS_PORT"
    echo "Synapse: https://$SYNAPSE_HOST:$HTTPS_PORT"
    echo

    echo -e "${WHITE}端口配置:${NC}"
    echo "HTTP端口: $HTTP_PORT"
    echo "HTTPS端口: $HTTPS_PORT"
    echo "联邦端口: $FEDERATION_PORT"
    echo

    echo -e "${WHITE}证书配置:${NC}"
    echo "证书环境: $CERT_ENVIRONMENT"
    echo "证书邮箱: $CERT_EMAIL"
    echo

    # 检查注册状态
    local reg_status=$(k3s kubectl get configmap ess-element-web -n ess -o jsonpath='{.data.config\.json}' | jq -r '.setting_defaults."UIFeature.registration"')
    echo -e "${WHITE}功能状态:${NC}"
    echo "用户注册: $([ "$reg_status" = "true" ] && echo "启用" || echo "禁用")"

    read -p "按回车键继续..."
}

# 查看服务状态
show_service_status() {
    print_step "服务状态检查"

    print_info "检查Pod状态..."
    k3s kubectl get pods -n ess
    echo

    print_info "检查服务状态..."
    k3s kubectl get svc -n ess
    echo

    print_info "检查Ingress状态..."
    k3s kubectl get ingress -n ess
    echo

    print_info "检查证书状态..."
    k3s kubectl get certificates -n ess

    read -p "按回车键继续..."
}

# 重启所有服务
restart_all_services() {
    print_step "重启所有服务"

    print_warning "确认要重启所有Matrix服务吗？"
    read -p "输入 'yes' 确认: " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "操作已取消"
        read -p "按回车键继续..."
        return 0
    fi

    print_info "重启Element Web..."
    k3s kubectl rollout restart deployment ess-element-web -n ess

    print_info "重启认证服务..."
    k3s kubectl rollout restart deployment ess-matrix-authentication-service -n ess

    print_info "重启Synapse..."
    k3s kubectl rollout restart statefulset ess-synapse-main -n ess

    print_info "重启RTC服务..."
    k3s kubectl rollout restart deployment ess-matrix-rtc-sfu -n ess
    k3s kubectl rollout restart deployment ess-matrix-rtc-authorisation-service -n ess

    print_info "重启HAProxy..."
    k3s kubectl rollout restart deployment ess-haproxy -n ess

    print_success "所有服务重启命令已发送"
    print_info "请等待服务重启完成..."

    read -p "按回车键继续..."
}

# 重启单个服务
restart_element_web() {
    print_step "重启Element Web"
    k3s kubectl rollout restart deployment ess-element-web -n ess
    print_success "Element Web重启命令已发送"
    read -p "按回车键继续..."
}

restart_auth_service() {
    print_step "重启认证服务"
    k3s kubectl rollout restart deployment ess-matrix-authentication-service -n ess
    print_success "认证服务重启命令已发送"
    read -p "按回车键继续..."
}

restart_synapse() {
    print_step "重启Synapse"
    k3s kubectl rollout restart statefulset ess-synapse-main -n ess
    print_success "Synapse重启命令已发送"
    read -p "按回车键继续..."
}

# 查看服务日志
show_service_logs() {
    print_step "查看服务日志"

    echo "可用的服务:"
    k3s kubectl get pods -n ess --no-headers | awk '{print NR") "$1}'
    echo

    read -p "请选择要查看日志的服务编号: " pod_num

    local pod_name=$(k3s kubectl get pods -n ess --no-headers | sed -n "${pod_num}p" | awk '{print $1}')

    if [[ -n "$pod_name" ]]; then
        print_info "查看 $pod_name 的日志 (按Ctrl+C退出):"
        k3s kubectl logs -n ess "$pod_name" -f --tail=100
    else
        print_error "无效的服务编号"
        read -p "按回车键继续..."
    fi
}

# 清理重启Pod
cleanup_restart_pods() {
    print_step "清理重启Pod"

    print_warning "这将删除所有失败的Pod并重新创建"
    read -p "输入 'yes' 确认: " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "操作已取消"
        read -p "按回车键继续..."
        return 0
    fi

    print_info "删除失败的Pod..."
    k3s kubectl delete pods -n ess --field-selector=status.phase=Failed

    print_info "删除Evicted状态的Pod..."
    k3s kubectl delete pods -n ess --field-selector=status.phase=Succeeded

    print_success "Pod清理完成"
    read -p "按回车键继续..."
}

# 系统诊断功能
full_system_check() {
    print_step "完整系统检查"

    print_info "检查K3s集群状态..."
    k3s kubectl get nodes
    echo

    print_info "检查ESS服务状态..."
    k3s kubectl get pods -n ess
    echo

    print_info "检查证书状态..."
    k3s kubectl get certificates -n ess
    echo

    print_info "检查存储状态..."
    df -h
    echo

    print_info "检查内存使用..."
    free -h

    read -p "按回车键继续..."
}

network_connectivity_test() {
    print_step "网络连通性测试"

    print_info "测试外网连接..."
    if ping -c 3 8.8.8.8 &> /dev/null; then
        print_success "外网连接正常"
    else
        print_error "外网连接失败"
    fi

    print_info "测试域名解析..."
    if nslookup $SERVER_NAME &> /dev/null; then
        print_success "域名解析正常"
    else
        print_error "域名解析失败"
    fi

    print_info "测试服务端口..."
    local services=("$WEB_HOST:$HTTPS_PORT" "$AUTH_HOST:$HTTPS_PORT" "$SYNAPSE_HOST:$HTTPS_PORT")

    for service in "${services[@]}"; do
        local host=$(echo "$service" | cut -d':' -f1)
        local port=$(echo "$service" | cut -d':' -f2)

        if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            print_success "$service - 端口连接正常"
        else
            print_warning "$service - 端口连接失败"
        fi
    done

    read -p "按回车键继续..."
}

ssl_certificate_check() {
    print_step "SSL证书检查"

    print_info "检查证书状态..."
    k3s kubectl get certificates -n ess
    echo

    print_info "检查证书详情..."
    for cert in $(k3s kubectl get certificates -n ess --no-headers -o custom-columns=":metadata.name"); do
        echo "证书: $cert"
        k3s kubectl describe certificate "$cert" -n ess | grep -A 5 "Status:"
        echo
    done

    read -p "按回车键继续..."
}

wellknown_config_check() {
    print_step "Well-known配置检查"

    print_info "检查Well-known客户端配置..."
    if curl -s "http://$SERVER_NAME:$HTTP_PORT/.well-known/matrix/client" | jq . 2>/dev/null; then
        print_success "Well-known客户端配置正常"
    else
        print_error "Well-known客户端配置异常"
    fi

    echo
    print_info "检查Well-known服务器配置..."
    if curl -s "http://$SERVER_NAME:$HTTP_PORT/.well-known/matrix/server" | jq . 2>/dev/null; then
        print_success "Well-known服务器配置正常"
    else
        print_error "Well-known服务器配置异常"
    fi

    read -p "按回车键继续..."
}

service_health_check() {
    print_step "服务健康检查"

    local services=("postgresql" "synapse" "matrix-authentication-service" "element-web")

    for service in "${services[@]}"; do
        local pod_status=$(k3s kubectl get pods -n ess -l app.kubernetes.io/name="$service" --no-headers 2>/dev/null | awk '{print $3}' | head -n1)
        if [[ "$pod_status" == "Running" ]]; then
            print_success "$service - 运行正常"
        else
            print_warning "$service - 状态: $pod_status"
        fi
    done

    read -p "按回车键继续..."
}

storage_space_check() {
    print_step "存储空间检查"

    print_info "磁盘使用情况:"
    df -h
    echo

    print_info "目录大小:"
    du -sh /var/lib/rancher/k3s/ 2>/dev/null || echo "K3s数据目录不存在"
    du -sh $INSTALL_DIR/ 2>/dev/null || echo "配置目录不存在"

    read -p "按回车键继续..."
}

performance_monitoring() {
    print_step "性能监控"

    print_info "CPU使用情况:"
    top -bn1 | head -5
    echo

    print_info "内存使用情况:"
    free -h
    echo

    print_info "负载情况:"
    uptime

    read -p "按回车键继续..."
}

show_system_info() {
    clear
    print_header "系统信息"

    echo -e "${WHITE}Matrix ESS 信息:${NC}"
    echo "服务器名: $SERVER_NAME"
    echo "Element Web: https://$WEB_HOST:$HTTPS_PORT"
    echo "认证服务: https://$AUTH_HOST:$HTTPS_PORT"
    echo "配置目录: $INSTALL_DIR"
    echo

    echo -e "${WHITE}系统信息:${NC}"
    echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "内核版本: $(uname -r)"
    echo "运行时间: $(uptime -p)"
    echo

    echo -e "${WHITE}K3s信息:${NC}"
    k3s --version | head -1
    echo

    echo -e "${WHITE}服务状态:${NC}"
    local running_pods=$(k3s kubectl get pods -n ess --no-headers | grep Running | wc -l)
    local total_pods=$(k3s kubectl get pods -n ess --no-headers | wc -l)
    echo "运行中的Pod: $running_pods/$total_pods"

    read -p "按回车键继续..."
}

# 修复Well-known配置
fix_wellknown_configuration() {
    print_step "修复Well-known配置"

    print_info "检查当前Well-known配置..."
    if curl -s "http://$SERVER_NAME:$HTTP_PORT/.well-known/matrix/client" | jq . &>/dev/null; then
        print_success "Well-known配置可访问"
        curl -s "http://$SERVER_NAME:$HTTP_PORT/.well-known/matrix/client" | jq .
    else
        print_error "Well-known配置无法访问"
    fi

    echo
    print_info "要修复Well-known配置，请："
    echo "1. 重新运行部署脚本"
    echo "2. 选择配置管理选项"
    echo "3. 或联系系统管理员"

    read -p "按回车键继续..."
}

fix_element_web_configuration() {
    print_step "修复Element Web配置"

    print_info "检查Element Web配置..."
    local current_config=$(k3s kubectl get configmap ess-element-web -n ess -o jsonpath='{.data.config\.json}' 2>/dev/null)

    if echo "$current_config" | jq . &>/dev/null; then
        local base_url=$(echo "$current_config" | jq -r '.default_server_config.m.homeserver.base_url')
        print_info "当前homeserver配置: $base_url"

        if [[ "$base_url" == *":$HTTPS_PORT" ]]; then
            print_success "Element Web配置包含正确端口号"
        else
            print_warning "Element Web配置缺少端口号"
            print_info "需要手动修复或重新运行部署脚本"
        fi
    else
        print_error "无法读取Element Web配置"
    fi

    read -p "按回车键继续..."
}

recreate_ssl_certificates() {
    print_step "SSL证书管理"

    print_info "检查当前证书状态..."
    k3s kubectl get certificates -n ess
    echo

    print_info "证书管理操作："
    echo "1. 查看证书详情: kubectl describe certificates -n ess"
    echo "2. 删除证书重新申请: kubectl delete certificates <证书名> -n ess"
    echo "3. 检查证书申请状态: kubectl get certificaterequests -n ess"
    echo "4. 重新运行部署脚本进行完整证书管理"

    read -p "按回车键继续..."
}

update_system_config() {
    print_step "系统配置更新"

    print_info "当前配置文件位置: $CONFIG_FILE"
    print_info "要更新系统配置，请："
    echo "1. 编辑配置文件: nano $CONFIG_FILE"
    echo "2. 重新运行部署脚本应用更改"
    echo "3. 或使用本管理工具的其他配置选项"

    read -p "按回车键继续..."
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
