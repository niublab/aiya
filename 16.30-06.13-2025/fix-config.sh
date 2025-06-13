#!/bin/bash

# Matrix ESS Community 配置文件修复工具
# 用于修复readonly变量冲突问题

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

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

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/matrix-config.env"

# 检查配置文件
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "未找到配置文件: $CONFIG_FILE"
    exit 1
fi

print_info "Matrix ESS Community 配置文件修复工具"
print_info "配置文件: $CONFIG_FILE"
echo

# 检查是否有readonly变量问题
print_info "检查配置文件中的readonly变量..."

readonly_vars=("ESS_VERSION" "ESS_CHART_OCI" "K3S_VERSION" "HELM_VERSION")
found_readonly=false

for var in "${readonly_vars[@]}"; do
    if grep -q "^${var}=" "$CONFIG_FILE"; then
        print_warning "发现readonly变量: $var"
        found_readonly=true
    fi
done

if [[ "$found_readonly" == "false" ]]; then
    print_success "配置文件中没有readonly变量问题"
    exit 0
fi

echo
print_warning "发现readonly变量冲突问题！"
print_info "这些变量会导致脚本运行时出现 'readonly variable' 错误"
echo

# 询问是否修复
read -p "是否自动修复配置文件？[Y/n]: " fix_choice
fix_choice=${fix_choice:-Y}

if [[ ! "$fix_choice" =~ ^[Yy]$ ]]; then
    print_info "用户取消修复"
    exit 0
fi

# 备份原配置文件
backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$backup_file"
print_info "已备份原配置文件到: $backup_file"

# 修复配置文件
print_info "修复配置文件..."

# 创建临时文件
temp_file=$(mktemp)

# 处理配置文件，注释掉readonly变量
while IFS= read -r line; do
    # 检查是否是readonly变量行
    is_readonly=false
    for var in "${readonly_vars[@]}"; do
        if [[ "$line" =~ ^${var}= ]]; then
            echo "# $line  # 注释掉readonly变量，由脚本控制" >> "$temp_file"
            is_readonly=true
            break
        fi
    done
    
    # 如果不是readonly变量，保持原样
    if [[ "$is_readonly" == "false" ]]; then
        echo "$line" >> "$temp_file"
    fi
done < "$CONFIG_FILE"

# 替换原配置文件
mv "$temp_file" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

print_success "配置文件修复完成！"
echo

# 验证修复结果
print_info "验证修复结果..."
if source "$CONFIG_FILE" 2>/dev/null; then
    print_success "配置文件可以正常加载"
else
    print_warning "配置文件仍有问题，但readonly变量错误应该已解决"
fi

echo
print_info "修复摘要:"
echo "  原配置文件: 已备份到 $backup_file"
echo "  修复后配置: $CONFIG_FILE"
echo "  修复内容: 注释掉readonly变量行"
echo

print_success "现在可以正常运行 ./setup.sh 了！"

# 询问是否删除备份文件
echo
read -p "是否删除备份文件？[y/N]: " delete_backup
if [[ "$delete_backup" =~ ^[Yy]$ ]]; then
    rm -f "$backup_file"
    print_info "已删除备份文件"
else
    print_info "备份文件保留在: $backup_file"
fi
