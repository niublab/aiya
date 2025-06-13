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
    echo -e "${CYAN}4)${NC} 仅下载文件到本地"
    echo -e "${CYAN}5)${NC} 显示帮助信息"
    echo -e "${CYAN}0)${NC} 退出"
    echo
}

# 部署ESS-Helm方案
deploy_ess() {
    log "STEP" "部署ESS-Helm外部Nginx反代方案..."
    
    # 设置执行权限
    chmod +x deploy-ess-nginx-proxy.sh
    
    # 检查配置文件
    if [[ -f "ess-config-template.env" ]]; then
        log "INFO" "发现配置模板文件，请先配置环境变量"
        log "INFO" "配置文件: $TEMP_DIR/ess-config-template.env"
        
        read -p "是否现在编辑配置文件? (y/N): " edit_config
        if [[ "$edit_config" =~ ^[Yy]$ ]]; then
            ${EDITOR:-nano} ess-config-template.env
            source ess-config-template.env
        fi
    fi
    
    # 运行部署脚本
    log "INFO" "开始部署ESS-Helm..."
    if ./deploy-ess-nginx-proxy.sh; then
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
    echo "  DEBUG=true          # 启用调试模式"
    echo "  AUTO_DEPLOY=1       # 自动部署ESS方案"
    echo "  AUTO_DEPLOY=2       # 自动部署IP更新系统"
    echo "  AUTO_DEPLOY=3       # 自动完整部署"
    echo
    echo -e "${CYAN}示例:${NC}"
    echo "  # 调试模式"
    echo "  DEBUG=true bash <(curl -fsSL $REPO_URL/setup.sh)"
    echo
    echo "  # 自动完整部署"
    echo "  AUTO_DEPLOY=3 bash <(curl -fsSL $REPO_URL/setup.sh)"
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
            *)
                log "ERROR" "无效的AUTO_DEPLOY值: $AUTO_DEPLOY"
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
                download_to_local
                break
                ;;
            "5")
                show_help
                ;;
            "0")
                log "INFO" "退出安装程序"
                exit 0
                ;;
            *)
                log "ERROR" "无效选择，请输入 1-5 或 0"
                ;;
        esac
    done
    
    log "SUCCESS" "部署完成!"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
