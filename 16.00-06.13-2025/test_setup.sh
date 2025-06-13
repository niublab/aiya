#!/bin/bash

# Matrix ESS Community 部署脚本测试
# 用于验证脚本的主要功能

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_info() {
    echo -e "${BLUE}[测试]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 测试脚本语法
test_syntax() {
    print_info "测试脚本语法..."
    if bash -n setup.sh; then
        print_success "脚本语法检查通过"
    else
        print_error "脚本语法检查失败"
        return 1
    fi
}

# 测试版本信息
test_version_info() {
    print_info "测试版本信息..."
    
    local script_version=$(grep "readonly SCRIPT_VERSION" setup.sh | cut -d'"' -f2)
    local ess_version=$(grep "readonly ESS_VERSION" setup.sh | cut -d'"' -f2)
    local chart_oci=$(grep "readonly ESS_CHART_OCI" setup.sh | cut -d'"' -f2)
    
    print_info "脚本版本: $script_version"
    print_info "ESS版本: $ess_version"
    print_info "Chart OCI: $chart_oci"
    
    if [[ "$script_version" == "4.0.0" ]] && [[ "$ess_version" == "25.6.1" ]]; then
        print_success "版本信息正确"
    else
        print_error "版本信息不正确"
        return 1
    fi
}

# 测试函数定义
test_function_definitions() {
    print_info "测试关键函数定义..."
    
    local functions=(
        "phased_deployment_menu"
        "deploy_phase_1"
        "deploy_phase_2" 
        "deploy_phase_3"
        "deploy_phase_4"
        "deploy_all_phases"
        "generate_ess_values"
        "verify_ess_chart"
        "deploy_ess"
    )
    
    for func in "${functions[@]}"; do
        if grep -q "^${func}() {" setup.sh; then
            print_success "函数 $func 已定义"
        else
            print_error "函数 $func 未找到"
            return 1
        fi
    done
}

# 测试配置变量
test_config_variables() {
    print_info "测试配置变量..."
    
    local variables=(
        "ESS_CHART_OCI"
        "DEPLOYMENT_PHASE"
        "DEFAULT_WEBRTC_TCP_PORT"
        "DEFAULT_WEBRTC_UDP_PORT"
    )
    
    for var in "${variables[@]}"; do
        if grep -q "readonly $var\|$var=" setup.sh; then
            print_success "变量 $var 已定义"
        else
            print_error "变量 $var 未找到"
            return 1
        fi
    done
}

# 测试菜单结构
test_menu_structure() {
    print_info "测试菜单结构..."
    
    # 检查分阶段部署菜单
    if grep -q "分阶段部署 Matrix ESS" setup.sh; then
        print_success "分阶段部署菜单已添加"
    else
        print_error "分阶段部署菜单未找到"
        return 1
    fi
    
    # 检查阶段选择
    if grep -q "第一阶段: 基础服务部署" setup.sh; then
        print_success "阶段选择菜单已添加"
    else
        print_error "阶段选择菜单未找到"
        return 1
    fi
}

# 主测试函数
main() {
    echo "========================================"
    echo "Matrix ESS Community 部署脚本测试"
    echo "========================================"
    echo
    
    # 检查setup.sh是否存在
    if [[ ! -f "setup.sh" ]]; then
        print_error "setup.sh 文件不存在"
        exit 1
    fi
    
    # 运行所有测试
    local tests=(
        "test_syntax"
        "test_version_info"
        "test_function_definitions"
        "test_config_variables"
        "test_menu_structure"
    )
    
    local passed=0
    local total=${#tests[@]}
    
    for test in "${tests[@]}"; do
        echo
        if $test; then
            ((passed++))
        fi
    done
    
    echo
    echo "========================================"
    echo "测试结果: $passed/$total 通过"
    echo "========================================"
    
    if [[ $passed -eq $total ]]; then
        print_success "所有测试通过！脚本已成功更新"
        echo
        echo "主要更新内容："
        echo "- 升级到ESS 25.6.1官方最新版本"
        echo "- 基于官方OCI registry部署"
        echo "- 新增分阶段部署功能"
        echo "- 优化用户体验和错误处理"
        echo "- 严格遵循官方最新规范"
        return 0
    else
        print_error "部分测试失败，请检查脚本"
        return 1
    fi
}

# 运行测试
main "$@"
