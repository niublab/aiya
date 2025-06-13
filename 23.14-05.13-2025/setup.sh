#!/bin/bash

# ESS-Helm外部Nginx反代 + IP自动更新系统 一键部署脚本
# 版本: v1.0.0
# 作者: Augment Agent
# 支持curl一键安装: bash <(curl -fsSL https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025/setup.sh)

set -euo pipefail

# 配置变量
REPO_URL="https://raw.githubusercontent.com/niublab/aiya/main/23.14-05.13-2025"
TEMP_DIR="/tmp/ess-installer-$$"
INSTALL_DIR="/opt/ess-installer"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
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
                echo -e "${PURPLE}[DEBUG]${NC} $message"
            fi
            ;;
        "STEP")
            echo -e "${CYAN}[STEP]${NC} $message"
            ;;
    esac
}

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                    ESS-Helm 一键部署系统                          ║
║                                                                  ║
║  🌐 ESS-Helm外部Nginx反代方案                                     ║
║  🔄 IP自动更新系统                                                ║
║  🚀 支持非标准端口、自定义域名、自定义路径                          ║
║                                                                  ║
║  版本: v1.0.0                                                    ║
║  作者: Augment Agent                                             ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "此脚本需要root权限运行"
        log "INFO" "请使用: sudo bash <(curl -fsSL $REPO_URL/setup.sh)"
        exit 1
    fi
}

# 检查系统要求
check_requirements() {
    log "STEP" "检查系统要求..."
    
    # 检查操作系统
    if ! command -v apt &> /dev/null && ! command -v yum &> /dev/null; then
        log "ERROR" "不支持的操作系统，仅支持Debian/Ubuntu/CentOS/RHEL"
        exit 1
    fi
    
    # 检查curl
    if ! command -v curl &> /dev/null; then
        log "INFO" "安装curl..."
        if command -v apt &> /dev/null; then
            apt update && apt install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        fi
    fi
    
    # 检查wget
    if ! command -v wget &> /dev/null; then
        log "INFO" "安装wget..."
        if command -v apt &> /dev/null; then
            apt install -y wget
        elif command -v yum &> /dev/null; then
            yum install -y wget
        fi
    fi
    
    log "SUCCESS" "系统要求检查完成"
}

# 下载文件
download_file() {
    local file_name="$1"
    local target_dir="$2"
    local url="${REPO_URL}/${file_name}"
    
    log "DEBUG" "下载文件: $file_name"
    
    if curl -fsSL "$url" -o "${target_dir}/${file_name}"; then
        log "DEBUG" "下载成功: $file_name"
        return 0
    else
        log "ERROR" "下载失败: $file_name"
        return 1
    fi
}

# 创建临时目录并下载所有文件
download_all_files() {
    log "STEP" "下载安装文件..."
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # 文件列表
    local files=(
        "ess-nginx-proxy-config.md"
        "deploy-ess-nginx-proxy.sh"
        "ess-config-template.env"
        "ess-helm-best-practices.md"
        "ip-update-system.md"
        "ip-update.sh"
        "ip-update.conf"
        "ip-update.service"
        "ip-update.timer"
        "install-ip-updater.sh"
        "nginx.conf.template"
        "ess-values.template"
        "ip-updater-usage-examples.md"
        "check-config.sh"
    )
    
    # 下载所有文件
    local failed_files=()
    for file in "${files[@]}"; do
        if ! download_file "$file" "$TEMP_DIR"; then
            failed_files+=("$file")
        fi
    done
    
    # 检查下载结果
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log "ERROR" "以下文件下载失败:"
        for file in "${failed_files[@]}"; do
            log "ERROR" "  - $file"
        done
        exit 1
    fi
    
    log "SUCCESS" "所有文件下载完成"
}

# 显示部署选项菜单
show_menu() {
    echo
    log "INFO" "请选择部署方案:"
    echo
    echo -e "${CYAN}1)${NC} ESS-Helm外部Nginx反代方案"
    echo -e "${CYAN}2)${NC} IP自动更新系统"
    echo -e "${CYAN}3)${NC} 完整部署 (ESS + IP更新系统)"
    echo -e "${CYAN}4)${NC} 测试模式部署 (使用测试证书)"
    echo -e "${CYAN}5)${NC} 检查配置"
    echo -e "${CYAN}6)${NC} 仅下载文件到本地"
    echo -e "${CYAN}7)${NC} 显示帮助信息"
    echo -e "${CYAN}0)${NC} 退出"
    echo
}

# 配置环境变量
configure_environment() {
    log "STEP" "配置环境变量..."

    # 检查是否已有环境变量
    if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "your-domain.com" ]]; then
        log "INFO" "检测到环境变量 DOMAIN=$DOMAIN"
        return 0
    fi

    # 检查配置文件
    if [[ -f "ess-config-template.env" ]]; then
        log "INFO" "发现配置模板文件"
        log "INFO" "配置文件: $TEMP_DIR/ess-config-template.env"

        # 在自动部署模式下，如果没有设置域名，则提示用户
        if [[ -n "${AUTO_DEPLOY:-}" ]]; then
            if [[ -z "${DOMAIN:-}" || "$DOMAIN" == "your-domain.com" ]]; then
                log "ERROR" "自动部署模式需要设置 DOMAIN 环境变量"
                log "INFO" "请使用: DOMAIN=your-actual-domain.com AUTO_DEPLOY=3 bash <(curl -fsSL ...)"
                log "INFO" "或者先设置环境变量:"
                log "INFO" "  export DOMAIN=your-actual-domain.com"
                log "INFO" "  export HTTP_PORT=8080"
                log "INFO" "  export HTTPS_PORT=8443"
                exit 1
            fi
        else
            # 交互模式
            read -p "是否现在编辑配置文件? (y/N): " edit_config
            if [[ "$edit_config" =~ ^[Yy]$ ]]; then
                ${EDITOR:-nano} ess-config-template.env
                source ess-config-template.env
            else
                # 提示用户手动设置关键变量
                log "INFO" "请设置关键环境变量:"

                if [[ -z "${DOMAIN:-}" || "$DOMAIN" == "your-domain.com" ]]; then
                    read -p "请输入您的域名 (例如: example.com): " user_domain
                    if [[ -n "$user_domain" ]]; then
                        export DOMAIN="$user_domain"
                        log "SUCCESS" "域名设置为: $DOMAIN"
                    else
                        log "ERROR" "域名不能为空"
                        exit 1
                    fi
                fi

                if [[ -z "${HTTP_PORT:-}" ]]; then
                    read -p "HTTP端口 [8080]: " user_http_port
                    export HTTP_PORT="${user_http_port:-8080}"
                fi

                if [[ -z "${HTTPS_PORT:-}" ]]; then
                    read -p "HTTPS端口 [8443]: " user_https_port
                    export HTTPS_PORT="${user_https_port:-8443}"
                fi

                log "SUCCESS" "环境变量配置完成"
                log "INFO" "域名: $DOMAIN"
                log "INFO" "HTTP端口: $HTTP_PORT"
                log "INFO" "HTTPS端口: $HTTPS_PORT"
            fi
        fi
    fi
}

# 部署ESS-Helm方案
deploy_ess() {
    log "STEP" "部署ESS-Helm外部Nginx反代方案..."

    # 配置环境变量
    configure_environment

    # 设置执行权限
    chmod +x deploy-ess-nginx-proxy.sh

    # 导出环境变量供子脚本使用
    export DOMAIN="${DOMAIN:-your-domain.com}"
    export HTTP_PORT="${HTTP_PORT:-8080}"
    export HTTPS_PORT="${HTTPS_PORT:-8443}"
    export FEDERATION_PORT="${FEDERATION_PORT:-8448}"

    # 从ess-config-template.env读取更多配置
    if [[ -f "ess-config-template.env" ]]; then
        log "DEBUG" "从配置模板读取额外配置..."
        # 读取配置但不覆盖已设置的环境变量
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z $key ]] && continue

            # 移除引号
            value=$(echo "$value" | sed 's/^"//;s/"$//')

            # 只设置未定义的变量
            if [[ -z "${!key:-}" ]]; then
                export "$key"="$value"
                log "DEBUG" "设置配置: $key=$value"
            fi
        done < <(grep -E '^[A-Z_]+=.*' ess-config-template.env || true)
    fi

    log "INFO" "使用配置:"
    log "INFO" "  域名: $DOMAIN"
    log "INFO" "  HTTP端口: $HTTP_PORT"
    log "INFO" "  HTTPS端口: $HTTPS_PORT"
    log "INFO" "  联邦端口: $FEDERATION_PORT"

    # 最后验证关键配置
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        log "ERROR" "域名仍为默认值，请设置正确的域名"
        log "INFO" "使用方法: DOMAIN=your-actual-domain.com AUTO_DEPLOY=3 bash <(curl ...)"
        return 1
    fi

    # 运行部署脚本，显式传递环境变量
    log "INFO" "开始部署ESS-Helm..."
    if env DOMAIN="$DOMAIN" \
           HTTP_PORT="$HTTP_PORT" \
           HTTPS_PORT="$HTTPS_PORT" \
           FEDERATION_PORT="$FEDERATION_PORT" \
           ./deploy-ess-nginx-proxy.sh; then
        log "SUCCESS" "ESS-Helm部署完成!"
    else
        log "ERROR" "ESS-Helm部署失败"
        return 1
    fi
}

# 部署IP更新系统
deploy_ip_updater() {
    log "STEP" "部署IP自动更新系统..."
    
    # 设置执行权限
    chmod +x install-ip-updater.sh
    
    # 运行安装脚本
    log "INFO" "开始安装IP更新系统..."
    if ./install-ip-updater.sh; then
        log "SUCCESS" "IP更新系统安装完成!"
        log "INFO" "请编辑配置文件: /opt/ip-updater/config/ip-update.conf"
        log "INFO" "然后重启服务: systemctl restart ip-update.timer"
    else
        log "ERROR" "IP更新系统安装失败"
        return 1
    fi
}

# 完整部署
deploy_full() {
    log "STEP" "开始完整部署..."

    # 先部署ESS
    if deploy_ess; then
        log "SUCCESS" "ESS部署完成，继续安装IP更新系统..."

        # 再部署IP更新系统
        if deploy_ip_updater; then
            log "SUCCESS" "完整部署成功!"

            # 配置IP更新系统管理ESS服务
            log "INFO" "配置IP更新系统管理ESS服务..."
            if [[ -f "/opt/ip-updater/config/ip-update.conf" ]]; then
                sed -i 's/SERVICES_TO_RELOAD=("nginx")/SERVICES_TO_RELOAD=("nginx" "matrix-ess")/' /opt/ip-updater/config/ip-update.conf
                systemctl restart ip-update.timer
                log "SUCCESS" "IP更新系统已配置为管理ESS服务"
            fi
        else
            log "ERROR" "IP更新系统安装失败"
            return 1
        fi
    else
        log "ERROR" "ESS部署失败"
        return 1
    fi
}

# 测试模式部署
deploy_test() {
    log "STEP" "开始测试模式部署..."
    log "WARNING" "测试模式将使用Let's Encrypt Staging证书或自签名证书"
    log "WARNING" "浏览器会显示不安全警告，这是正常的"

    # 配置环境变量
    configure_environment

    # 设置测试模式
    export TEST_MODE="true"
    export CERT_TYPE="${CERT_TYPE:-letsencrypt-staging}"

    # 询问证书类型
    echo
    log "INFO" "选择测试证书类型:"
    echo "  1) Let's Encrypt Staging (推荐，需要域名解析)"
    echo "  2) 自签名证书 (无需域名解析)"
    echo
    read -p "请选择 [1-2]: " cert_choice

    case "$cert_choice" in
        "1")
            export CERT_TYPE="letsencrypt-staging"
            log "INFO" "将使用Let's Encrypt Staging证书"
            ;;
        "2")
            export CERT_TYPE="self-signed"
            log "INFO" "将使用自签名证书"
            ;;
        *)
            log "WARNING" "无效选择，使用默认的Staging证书"
            export CERT_TYPE="letsencrypt-staging"
            ;;
    esac

    # 设置执行权限
    chmod +x deploy-ess-nginx-proxy.sh

    # 导出环境变量供子脚本使用
    export DOMAIN="${DOMAIN:-your-domain.com}"
    export HTTP_PORT="${HTTP_PORT:-8080}"
    export HTTPS_PORT="${HTTPS_PORT:-8443}"
    export FEDERATION_PORT="${FEDERATION_PORT:-8448}"

    log "INFO" "使用测试配置:"
    log "INFO" "  域名: $DOMAIN"
    log "INFO" "  证书类型: $CERT_TYPE"
    log "INFO" "  测试模式: $TEST_MODE"

    # 最后验证关键配置
    if [[ "$DOMAIN" == "your-domain.com" ]]; then
        log "ERROR" "域名仍为默认值，请设置正确的域名"
        return 1
    fi

    # 运行部署脚本
    log "INFO" "开始测试模式部署..."
    if env DOMAIN="$DOMAIN" \
           HTTP_PORT="$HTTP_PORT" \
           HTTPS_PORT="$HTTPS_PORT" \
           FEDERATION_PORT="$FEDERATION_PORT" \
           TEST_MODE="$TEST_MODE" \
           CERT_TYPE="$CERT_TYPE" \
           ./deploy-ess-nginx-proxy.sh; then
        log "SUCCESS" "测试模式部署完成!"
        log "WARNING" "请注意: 浏览器会显示证书不安全警告"
        log "INFO" "这是正常的，因为使用的是测试证书"
    else
        log "ERROR" "测试模式部署失败"
        return 1
    fi
}

# 检查配置
check_config() {
    log "STEP" "检查配置..."

    # 设置执行权限
    chmod +x check-config.sh

    # 运行配置检查
    if ./check-config.sh; then
        log "SUCCESS" "配置检查完成"
    else
        log "WARNING" "配置检查发现问题，请根据建议修复"
    fi
}

# 下载文件到本地
download_to_local() {
    log "STEP" "下载文件到本地..."

    local local_dir="${HOME}/ess-installer-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$local_dir"

    # 复制所有文件
    cp -r "$TEMP_DIR"/* "$local_dir/"

    # 设置权限
    chmod +x "$local_dir"/*.sh

    log "SUCCESS" "文件已下载到: $local_dir"
    log "INFO" "您可以进入目录手动运行部署脚本:"
    log "INFO" "  cd $local_dir"
    log "INFO" "  ./check-config.sh  # 检查配置"
    log "INFO" "  sudo ./deploy-ess-nginx-proxy.sh"
    log "INFO" "  sudo ./install-ip-updater.sh"
}

# 显示帮助信息
show_help() {
    echo
    log "INFO" "ESS-Helm一键部署系统帮助"
    echo
    echo -e "${CYAN}使用方法:${NC}"
    echo "  bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo -e "${CYAN}环境变量:${NC}"
    echo "  DOMAIN=your-domain.com      # 您的域名 (必需)"
    echo "  HTTP_PORT=8080              # HTTP端口"
    echo "  HTTPS_PORT=8443             # HTTPS端口"
    echo "  FEDERATION_PORT=8448        # Matrix联邦端口"
    echo "  TEST_MODE=true              # 启用测试模式"
    echo "  CERT_TYPE=self-signed       # 证书类型"
    echo "  DEBUG=true                  # 启用调试模式"
    echo "  AUTO_DEPLOY=1               # 自动部署ESS方案"
    echo "  AUTO_DEPLOY=2               # 自动部署IP更新系统"
    echo "  AUTO_DEPLOY=3               # 自动完整部署"
    echo "  AUTO_DEPLOY=4               # 自动测试模式部署"
    echo
    echo -e "${CYAN}推荐使用方式:${NC}"
    echo "  # 交互式部署 (推荐新手)"
    echo "  bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo "  # 自动完整部署 (推荐有经验用户)"
    echo "  DOMAIN=your-domain.com AUTO_DEPLOY=3 bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo -e "${CYAN}完整示例:${NC}"
    echo "  # 生产环境完整部署"
    echo "  DOMAIN=matrix.example.com \\"
    echo "  HTTP_PORT=8080 \\"
    echo "  HTTPS_PORT=8443 \\"
    echo "  AUTO_DEPLOY=3 \\"
    echo "  bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo "  # 测试环境部署 (使用测试证书)"
    echo "  DOMAIN=test.example.com \\"
    echo "  TEST_MODE=true \\"
    echo "  CERT_TYPE=self-signed \\"
    echo "  AUTO_DEPLOY=4 \\"
    echo "  bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo "  # 调试模式"
    echo "  DEBUG=true DOMAIN=test.example.com AUTO_DEPLOY=test \\"
    echo "  bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo -e "${CYAN}重要提醒:${NC}"
    echo "  1. 确保域名DNS已正确解析到服务器IP"
    echo "  2. 确保防火墙已开放相应端口"
    echo "  3. 确保80端口可用于SSL证书验证"
    echo "  4. 建议先在测试环境验证配置"
    echo
    echo -e "${CYAN}文件说明:${NC}"
    echo "  ess-nginx-proxy-config.md     - ESS配置指南"
    echo "  deploy-ess-nginx-proxy.sh     - ESS部署脚本"
    echo "  ip-update-system.md           - IP更新系统文档"
    echo "  install-ip-updater.sh         - IP更新安装脚本"
    echo
    echo -e "${CYAN}支持和反馈:${NC}"
    echo "  GitHub: https://github.com/niublab/aiya"
    echo "  Issues: https://github.com/niublab/aiya/issues"
    echo
}

# 清理函数
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        log "DEBUG" "清理临时文件: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# 主函数
main() {
    # 设置清理函数
    trap cleanup EXIT
    
    # 显示横幅
    show_banner
    
    # 检查权限和系统要求
    check_root
    check_requirements
    
    # 下载所有文件
    download_all_files
    
    # 检查自动部署模式
    if [[ -n "${AUTO_DEPLOY:-}" ]]; then
        case "$AUTO_DEPLOY" in
            "1")
                deploy_ess
                ;;
            "2")
                deploy_ip_updater
                ;;
            "3")
                deploy_full
                ;;
            "4"|"test")
                deploy_test
                ;;
            *)
                log "ERROR" "无效的AUTO_DEPLOY值: $AUTO_DEPLOY"
                log "INFO" "支持的值: 1(ESS), 2(IP更新), 3(完整), 4/test(测试模式)"
                exit 1
                ;;
        esac
        return 0
    fi
    
    # 交互式菜单
    while true; do
        show_menu
        read -p "请选择 [1-5,0]: " choice
        
        case "$choice" in
            "1")
                deploy_ess
                break
                ;;
            "2")
                deploy_ip_updater
                break
                ;;
            "3")
                deploy_full
                break
                ;;
            "4")
                deploy_test
                break
                ;;
            "5")
                check_config
                ;;
            "6")
                download_to_local
                break
                ;;
            "7")
                show_help
                ;;
            "0")
                log "INFO" "退出安装程序"
                exit 0
                ;;
            *)
                log "ERROR" "无效选择，请输入 1-7 或 0"
                ;;
        esac
    done
    
    log "SUCCESS" "部署完成!"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
