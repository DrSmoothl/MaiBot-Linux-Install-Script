#!/bin/bash

# =============================================================================
# Linux 一键安装+控制台脚本框架
# 支持主流Linux发行版，提供命令行GUI交互
# =============================================================================

set -euo pipefail

# =============================================================================
# 全局变量
# =============================================================================
SCRIPT_NAME="MaiBot Ecosystem Installer"
SCRIPT_VERSION="1.2.0"
SCRIPT_AUTHOR="MaiM-with-u"
SCRIPT_URL="https://github.com/MaiM-with-u/MaiBot"

# 日志配置
LOG_DIR="/var/log/maibot-installer"
LOG_FILE="$LOG_DIR/installer_$(date +%Y%m%d_%H%M%S).log"
DEBUG_MODE=false
VERBOSE_MODE=false

# 系统支持
SUPPORTED_DISTROS=("ubuntu" "debian" "centos" "rhel" "fedora" "opensuse" "arch" "alpine")
MIN_DISK_SPACE_GB=2
MIN_MEMORY_MB=512
REQUIRED_COMMANDS=("curl" "git" "python3" "unzip")

# UI配置
FORCE_YES=false
QUIET_MODE=false
DEBUG_MENU_MODE=false

# 安装模块定义
declare -A INSTALL_MODULES=(
    ["maibot"]="MaiBot本体"
    ["adapter"]="MaiBot-NapCat-Adapter"
    ["napcat"]="NapcatQQ"
)

# 仓库配置
MAIBOT_REPO="https://github.com/MaiM-with-u/MaiBot.git"
ADAPTER_REPO="https://github.com/MaiM-with-u/MaiBot-NapCat-Adapter.git"
NAPCAT_REPO="https://github.com/NapNeko/NapCatQQ"

# 安装路径配置
INSTALL_BASE_DIR="/opt/maibot"
MAIBOT_DIR="$INSTALL_BASE_DIR/maibot"
ADAPTER_DIR="$INSTALL_BASE_DIR/maibot-napcat-adapter"
NAPCAT_DIR="$INSTALL_BASE_DIR/napcatqq"
CONFIG_DIR="$INSTALL_BASE_DIR/config"
LOGS_DIR="$INSTALL_BASE_DIR/logs"
DATA_DIR="$INSTALL_BASE_DIR/data"

# 网络配置
GITHUB_MIRRORS=(
    "https://ghfast.top"
    "https://gh.wuliya.xin"
    "https://gh-proxy.com"
    "https://github.moeyy.xyz"
    "https://hub.fastgit.xyz"
    "https://gitclone.com"
)
NETWORK_TIMEOUT=30
MAX_RETRIES=3

# =============================================================================
# 颜色输出定义
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# 输出函数
# =============================================================================
print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_info() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
    log_message "INFO: $1"
}

print_success() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
    log_message "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log_message "ERROR: $1"
}

print_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${GRAY}[DEBUG]${NC} $1"
        log_message "DEBUG: $1"
    fi
}

print_verbose() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo -e "${PURPLE}[VERBOSE]${NC} $1"
        log_message "VERBOSE: $1"
    fi
}

# 进度条显示
show_progress() {
    local current=$1
    local total=$2
    local description=$3
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r${CYAN}[进度]${NC} ["
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %3d%% %s" $percent "$description"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 错误退出函数
fatal_error() {
    print_error "$1"
    print_error "安装失败，正在清理临时文件..."
    cleanup_on_exit
    exit 1
}

# 信号处理
trap_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "脚本异常退出 (退出码: $exit_code)"
        cleanup_on_exit
    fi
    exit $exit_code
}

# 设置信号处理
trap trap_exit EXIT
trap 'fatal_error "脚本被用户中断"' INT TERM

# =============================================================================
# 日志记录函数
# =============================================================================
init_logging() {
    # 尝试创建系统日志目录
    if [[ ! -d "$LOG_DIR" ]]; then
        if mkdir -p "$LOG_DIR" 2>/dev/null; then
            print_verbose "成功创建日志目录: $LOG_DIR"
        else
            # 如果无法创建系统日志目录，使用临时目录
            print_warning "无法创建系统日志目录，使用临时目录"
            LOG_DIR="/tmp/maibot-installer"
            LOG_FILE="$LOG_DIR/installer_$(date +%Y%m%d_%H%M%S).log"
            mkdir -p "$LOG_DIR" 2>/dev/null || {
                echo "错误: 无法创建日志目录，日志功能将被禁用"
                LOG_FILE="/dev/null"
                return
            }
        fi
    fi
    
    # 创建日志文件
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "警告: 无法创建日志文件，使用备用位置"
        LOG_FILE="/tmp/maibot_installer_$(date +%Y%m%d_%H%M%S).log"
        if ! touch "$LOG_FILE" 2>/dev/null; then
            echo "警告: 无法创建日志文件，日志将输出到控制台"
            LOG_FILE="/dev/null"
        fi
    fi
    
    # 记录脚本开始
    log_message "==============================================="
    log_message "MaiBot生态系统安装脚本开始运行"
    log_message "脚本版本: $SCRIPT_VERSION"
    log_message "运行时间: $(date)"
    log_message "运行用户: $(whoami)"
    log_message "系统信息: $(uname -a)"
    log_message "日志文件: $LOG_FILE"
    log_message "==============================================="
}

log_message() {
    local message="$1"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # 同时写入日志文件和标准输出（如果是调试模式）
    echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${GRAY}[LOG]${NC} $message"
    fi
}

log_command() {
    local command="$1"
    local description="${2:-执行命令}"
    
    log_message "执行命令: $command"
    print_verbose "$description: $command"
    
    # 执行命令并记录输出
    if [[ "$DEBUG_MODE" == "true" ]]; then
        eval "$command" 2>&1 | tee -a "$LOG_FILE"
        return ${PIPESTATUS[0]}
    else
        eval "$command" >> "$LOG_FILE" 2>&1
        return $?
    fi
}

# 清理函数
cleanup_on_exit() {
    local exit_code=$?
    
    print_debug "执行清理操作..."
    
    # 停止可能正在运行的进程
    pkill -f "Xvfb :1" 2>/dev/null || true
    
    # 清理临时文件
    local temp_files=(
        "/tmp/maibot_*"
        "/tmp/napcat_*"
        "/tmp/adapter_*"
        "/tmp/QQ.*"
        "/tmp/NapCat.*"
    )
    
    for pattern in "${temp_files[@]}"; do
        rm -rf $pattern 2>/dev/null || true
    done
    
    # 记录清理完成
    log_message "清理操作完成，退出码: $exit_code"
    log_message "==============================================="
    
    return $exit_code
}

# =============================================================================
# 系统检测函数
# =============================================================================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_LIKE=${ID_LIKE:-}
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
    elif [[ -f /etc/alpine-release ]]; then
        OS="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi
    
    print_debug "检测到操作系统: $OS $OS_VERSION"
    log_message "系统检测: $OS $OS_VERSION"
}

# =============================================================================
# 权限检查函数
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请使用 sudo 运行此脚本: sudo $0"
        exit 1
    fi
    print_success "权限检查通过"
    log_message "Root权限检查通过"
}

# =============================================================================
# 包管理器检测函数
# =============================================================================
detect_package_manager() {
    case "$OS" in
        ubuntu|debian)
            if command -v apt &> /dev/null; then
                PACKAGE_MANAGER="apt"
                INSTALL_CMD="apt install -y"
                UPDATE_CMD="apt update"
                UPGRADE_CMD="apt upgrade -y"
            else
                print_error "未找到apt包管理器"
                exit 1
            fi
            ;;
        centos|rhel)
            if command -v yum &> /dev/null; then
                PACKAGE_MANAGER="yum"
                INSTALL_CMD="yum install -y"
                UPDATE_CMD="yum update"
                UPGRADE_CMD="yum upgrade -y"
            elif command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf update"
                UPGRADE_CMD="dnf upgrade -y"
            else
                print_error "未找到yum或dnf包管理器"
                exit 1
            fi
            ;;
        fedora)
            if command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf update"
                UPGRADE_CMD="dnf upgrade -y"
            else
                print_error "未找到dnf包管理器"
                exit 1
            fi
            ;;
        opensuse)
            if command -v zypper &> /dev/null; then
                PACKAGE_MANAGER="zypper"
                INSTALL_CMD="zypper install -y"
                UPDATE_CMD="zypper refresh"
                UPGRADE_CMD="zypper update -y"
            else
                print_error "未找到zypper包管理器"
                exit 1
            fi
            ;;
        arch)
            if command -v pacman &> /dev/null; then
                PACKAGE_MANAGER="pacman"
                INSTALL_CMD="pacman -S --noconfirm"
                UPDATE_CMD="pacman -Sy"
                UPGRADE_CMD="pacman -Syu --noconfirm"
            else
                print_error "未找到pacman包管理器"
                exit 1
            fi
            ;;
        alpine)
            if command -v apk &> /dev/null; then
                PACKAGE_MANAGER="apk"
                INSTALL_CMD="apk add"
                UPDATE_CMD="apk update"
                UPGRADE_CMD="apk upgrade"
            else
                print_error "未找到apk包管理器"
                exit 1
            fi
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    print_success "包管理器检测: $PACKAGE_MANAGER"
    log_message "包管理器检测完成: $PACKAGE_MANAGER"
}

# =============================================================================
# 系统要求检查函数
# =============================================================================
check_system_requirements() {
    print_info "检查系统要求..."
    
    # 检查内存
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEMORY_GB -lt 1 ]]; then
        print_warning "系统内存不足1GB，可能影响性能"
    else
        print_success "内存检查通过: ${MEMORY_GB}GB"
    fi
    
    # 检查磁盘空间
    DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
    DISK_SPACE_GB=$((DISK_SPACE / 1024 / 1024))
    if [[ $DISK_SPACE_GB -lt 2 ]]; then
        print_error "磁盘空间不足2GB"
        exit 1
    else
        print_success "磁盘空间检查通过: ${DISK_SPACE_GB}GB可用"
    fi
    
    # 检查网络连接
    if ping -c 1 google.com &> /dev/null || ping -c 1 baidu.com &> /dev/null; then
        print_success "网络连接正常"
    else
        print_warning "网络连接异常，可能影响安装过程"
    fi
    
    log_message "系统要求检查完成"
}

# =============================================================================
# 依赖检查和安装函数
# =============================================================================
install_dependencies() {
    print_info "检查并安装依赖..."
    
    local dependencies=("curl" "wget" "unzip" "tar" "git" "g++" "xvfb" "screen" "xauth")
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_info "安装依赖: $dep"
            
            # 处理特殊的依赖包名映射
            local install_name="$dep"
            case "$dep" in
                "g++")
                    case "$PACKAGE_MANAGER" in
                        apt) install_name="g++" ;;
                        yum|dnf) install_name="gcc-c++" ;;
                        zypper) install_name="gcc-c++" ;;
                        pacman) install_name="gcc" ;;
                        apk) install_name="g++" ;;
                    esac
                    ;;
                "xvfb")
                    case "$PACKAGE_MANAGER" in
                        apt) install_name="xvfb" ;;
                        yum|dnf) install_name="xorg-x11-server-Xvfb" ;;
                        zypper) install_name="xorg-x11-server-extra" ;;
                        pacman) install_name="xorg-server-xvfb" ;;
                        apk) install_name="xvfb" ;;
                    esac
                    ;;
                "xauth")
                    case "$PACKAGE_MANAGER" in
                        apt) install_name="xauth" ;;
                        yum|dnf) install_name="xorg-x11-xauth" ;;
                        zypper) install_name="xauth" ;;
                        pacman) install_name="xorg-xauth" ;;
                        apk) install_name="xauth" ;;
                    esac
                    ;;
            esac
            
            $INSTALL_CMD "$install_name" || {
                print_warning "无法安装依赖: $dep (尝试安装: $install_name)"
                # 不退出，继续安装其他依赖
            }
        else
            print_success "依赖已存在: $dep"
        fi
    done
    
    # 安装额外的NapCat依赖
    print_info "安装NapCat专用依赖..."
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD jq procps || true
            ;;
        yum|dnf)
            $INSTALL_CMD epel-release || true
            $INSTALL_CMD jq procps-ng || true
            ;;
        zypper)
            $INSTALL_CMD jq procps || true
            ;;
        pacman)
            $INSTALL_CMD jq procps-ng || true
            ;;
        apk)
            $INSTALL_CMD jq procps || true
            ;;
    esac
    
    log_message "依赖安装完成"
}

# =============================================================================
# 命令行参数解析函数
# =============================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                DEBUG_MENU_MODE=true
                print_debug "调试模式已启用，将显示额外的菜单选项"
                ;;
            --help|-h)
                show_help_and_exit
                ;;
            --version|-v)
                echo "$SCRIPT_NAME v$SCRIPT_VERSION"
                exit 0
                ;;
            *)
                print_warning "未知参数: $1"
                print_info "使用 --help 查看可用参数"
                ;;
        esac
        shift
    done
}

show_help_and_exit() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "MaiBot生态系统Linux一键安装脚本"
    echo ""
    echo "用法:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --debug      启用调试模式，显示额外的菜单选项"
    echo "  --help, -h   显示此帮助信息"
    echo "  --version, -v 显示版本信息"
    echo ""
    echo "调试模式选项:"
    echo "  仅添加maibot命令脚本 - 只创建全局maibot命令而不安装其他组件"
    echo ""
    exit 0
}

# 仅添加maibot命令脚本的函数
only_add_maibot_command() {
    print_header "仅添加maibot命令脚本"
    print_info "此选项将只创建全局maibot命令脚本，而不安装其他组件"
    echo ""
    
    if ! confirm_action "确认仅创建maibot命令脚本？"; then
        print_info "操作已取消"
        return
    fi
    
    # 检查系统环境
    detect_os
    check_root
    
    # 创建必要的目录结构
    print_info "创建基础目录结构..."
    mkdir -p "$INSTALL_BASE_DIR" || {
        print_error "无法创建安装目录: $INSTALL_BASE_DIR"
        return 1
    }
    
    # 只调用创建全局命令的函数
    print_info "创建全局maibot命令..."
    if create_global_command; then
        print_success "maibot命令脚本创建成功！"
        print_info "现在您可以使用以下命令:"
        print_info "  maibot help           # 查看完整帮助"
        print_info "  maibot start all      # 启动所有组件（需要先安装组件）"
        print_info "  maibot status          # 查看组件状态"
        echo ""
        print_warning "注意: 此模式只创建了命令脚本，您仍需要安装实际的组件才能使用完整功能"
    else
        print_error "maibot命令脚本创建失败"
        return 1
    fi
    
    log_message "仅添加maibot命令脚本操作完成"
}

# =============================================================================
# 对话框函数（CLI界面）
# =============================================================================
show_welcome() {
    clear
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo -e "${WHITE}欢迎使用 $SCRIPT_NAME 安装脚本${NC}"
    echo -e "${GRAY}支持的系统: ${SUPPORTED_DISTROS[*]}${NC}"
    echo -e "${GRAY}当前系统: $OS $OS_VERSION${NC}"
    echo -e "${GRAY}包管理器: $PACKAGE_MANAGER${NC}"
    echo ""
}

show_menu() {
    echo ""
    echo -e "${BOLD}请选择操作:${NC}"
    echo -e "${GREEN}1)${NC} 完整安装"
    echo -e "${GREEN}2)${NC} 自定义安装"
    echo -e "${GREEN}3)${NC} 卸载"
    echo -e "${GREEN}4)${NC} 系统信息"
    echo -e "${GREEN}5)${NC} 查看日志"
    
    # 调试模式下显示额外选项
    if [[ "$DEBUG_MENU_MODE" == "true" ]]; then
        echo -e "${CYAN}6)${NC} 仅添加maibot命令脚本 ${YELLOW}(调试选项)${NC}"
    fi
    
    echo -e "${GREEN}0)${NC} 退出"
    echo ""
}

read_choice() {
    local choice
    local max_choice=5
    
    # 调试模式下允许选择6
    if [[ "$DEBUG_MENU_MODE" == "true" ]]; then
        max_choice=6
    fi
    
    while true; do
        read -p "请输入选择 [0-$max_choice]: " choice
        
        # 去除前后空白字符
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        # 验证输入
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 0 ]] && [[ "$choice" -le "$max_choice" ]]; then
            echo "$choice"
            return 0
        elif [[ -z "$choice" ]]; then
            print_error "输入不能为空，请输入0-$max_choice之间的数字"
        else
            print_error "无效选择，请输入0-$max_choice之间的数字"
        fi
    done
}

confirm_action() {
    local message="$1"
    
    local choice
    while true; do
        read -p "$message [y/N]: " choice
        case $choice in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                return 1
                ;;
            *)
                print_error "请输入 y 或 n"
                ;;
        esac
    done
}

# 获取最新日志行的函数
get_latest_log_line() {
    if [[ -f "$LOG_FILE" && -r "$LOG_FILE" ]]; then
        # 获取最新一行日志，去除时间戳和日志级别，限制长度
        local latest_log=$(tail -n 1 "$LOG_FILE" 2>/dev/null | sed 's/^\[[^]]*\] //' | cut -c1-50)
        if [[ -n "$latest_log" ]]; then
            echo "$latest_log"
        else
            echo "正在处理..."
        fi
    else
        echo "初始化中..."
    fi
}

show_progress() {
    local current=$1
    local total=$2
    local message="$3"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    printf "\r${BLUE}[INFO]${NC} $message "
    printf "${GREEN}"
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "${NC} ${percentage}%%"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

show_info_box() {
    local title="$1"
    local message="$2"
    
    print_header "$title"
    echo "$message"
    echo ""
    read -p "按任意键继续..." -n 1 -r
}

show_scrollable_text() {
    local title="$1"
    local file="$2"
    
    print_header "$title"
    if [[ -f "$file" ]]; then
        tail -20 "$file"
    else
        print_info "文件不存在: $file"
    fi
    echo ""
    read -p "按任意键继续..." -n 1 -r
}

input_box() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

# =============================================================================
# 模块安装函数
# =============================================================================

# GitHub镜像测试函数
test_github_mirrors() {
    local test_url="$1"
    local timeout=10
    
    print_info "测试GitHub网络连接..." >&2
    
    # GitHub镜像站点列表
    local mirrors=(
        "https://ghfast.top" 
        "https://gh.wuliya.xin" 
        "https://gh-proxy.com" 
        "https://github.moeyy.xyz"
        "https://hub.fastgit.xyz"
        "https://gitclone.com"
    )
    
    # 首先测试直连
    print_debug "测试GitHub直连..." >&2
    if curl -k --connect-timeout $timeout --max-time $((timeout*2)) -o /dev/null -s "$test_url" 2>/dev/null; then
        print_success "GitHub直连成功" >&2
        echo ""  # 返回空字符串表示直连
        return 0
    fi
    
    # 测试镜像站点
    for mirror in "${mirrors[@]}"; do
        print_debug "测试镜像站点: $mirror" >&2
        local mirror_url="$mirror/${test_url#https://}"
        
        if curl -k --connect-timeout $timeout --max-time $((timeout*2)) -o /dev/null -s "$mirror_url" 2>/dev/null; then
            print_success "找到可用的GitHub镜像: $mirror" >&2
            echo "$mirror"
            return 0
        fi
    done
    
    print_warning "无法找到可用的GitHub镜像，将尝试直连" >&2
    echo ""
    return 1
}

# 创建安装目录
create_install_directories() {
    print_info "创建安装目录..."
    
    # 创建基础目录
    mkdir -p "$INSTALL_BASE_DIR" || {
        print_error "无法创建基础安装目录: $INSTALL_BASE_DIR"
        return 1
    }
    
    # 创建各组件目录
    mkdir -p "$MAIBOT_DIR"
    mkdir -p "$ADAPTER_DIR" 
    mkdir -p "$NAPCAT_DIR"
    
    # 设置目录权限
    chmod 755 "$INSTALL_BASE_DIR"
    chmod 755 "$MAIBOT_DIR"
    chmod 755 "$ADAPTER_DIR"
    chmod 755 "$NAPCAT_DIR"
    
    print_success "安装目录创建完成"
    log_message "安装目录创建: $INSTALL_BASE_DIR"
}

# 安装Python和pip
install_python() {
    print_info "检查并安装Python..."
    
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version)
        print_success "Python已安装: $python_version"
        return 0
    fi
    
    print_info "正在安装Python..."
    case "$PACKAGE_MANAGER" in
        apt)
            $INSTALL_CMD python3 python3-pip python3-venv
            ;;
        yum|dnf)
            $INSTALL_CMD python3 python3-pip
            ;;
        zypper)
            $INSTALL_CMD python3 python3-pip
            ;;
        pacman)
            $INSTALL_CMD python3 python3-pip
            ;;
        apk)
            $INSTALL_CMD python3 py3-pip
            ;;
    esac
    
    if command -v python3 &> /dev/null; then
        print_success "Python安装成功: $(python3 --version)"
        log_message "Python安装完成: $(python3 --version)"
    else
        print_error "Python安装失败"
        return 1
    fi
}

# 创建全局maibot命令
create_global_command() {
    print_info "正在创建全局maibot命令..."
    
    # 创建maibot命令脚本
    local maibot_script="/usr/local/bin/maibot"
    
    # 检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        print_warning "需要sudo权限来创建全局命令，请输入密码"
    fi
    
    # 创建maibot命令脚本
    sudo tee "$maibot_script" > /dev/null << EOF
#!/bin/bash
# MaiBot全局命令脚本
# 版本: 2.0.0 - 支持Screen会话管理

MAIBOT_DIR="$MAIBOT_DIR"
ADAPTER_DIR="$ADAPTER_DIR"
NAPCAT_DIR="$NAPCAT_DIR"

# Screen会话名称
SESSION_MAIBOT="maibot-main"
SESSION_ADAPTER="maibot-adapter" 
SESSION_NAPCAT="maibot-napcat"

# 检查screen是否安装
check_screen() {
    if ! command -v screen >/dev/null 2>&1; then
        echo "错误: screen未安装，请先安装screen"
        echo "Ubuntu/Debian: sudo apt install screen"
        echo "CentOS/RHEL: sudo yum install screen"
        echo "Fedora: sudo dnf install screen"
        exit 1
    fi
}

show_help() {
    echo "MaiBot 管理工具 (Screen版本)"
    echo ""
    echo "用法: maibot <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  start [component]     启动组件 (使用Screen会话)"
    echo "    maibot               启动MaiBot本体"
    echo "    adapter              启动MaiBot-NapCat-Adapter"
    echo "    napcat               启动NapcatQQ"
    echo "    all                  启动所有组件"
    echo ""
    echo "  stop [component]      停止组件"
    echo "    maibot               停止MaiBot本体"
    echo "    adapter              停止MaiBot-NapCat-Adapter"
    echo "    napcat               停止NapcatQQ"
    echo "    all                  停止所有组件"
    echo ""
    echo "  switch <component>    切换到组件的Screen会话"
    echo "    maibot               切换到MaiBot本体会话"
    echo "    adapter              切换到MaiBot-NapCat-Adapter会话"
    echo "    napcat               切换到NapcatQQ会话"
    echo ""
    echo "  status [component]    查看组件状态"
    echo "    maibot               查看MaiBot本体状态"
    echo "    adapter              查看MaiBot-NapCat-Adapter状态"
    echo "    napcat               查看NapcatQQ状态"
    echo "    all                  查看所有组件状态"
    echo ""
    echo "  list                  列出所有MaiBot相关的Screen会话"
    echo ""
    echo "  restart [component]   重启组件"
    echo "    maibot               重启MaiBot本体"
    echo "    adapter              重启MaiBot-NapCat-Adapter"
    echo "    napcat               重启NapcatQQ"
    echo "    all                  重启所有组件"
    echo ""
    echo "  logs [component]      查看日志"
    echo "    maibot               查看MaiBot本体日志"
    echo "    adapter              查看MaiBot-NapCat-Adapter日志"
    echo "    napcat               查看NapcatQQ日志"
    echo ""
    echo "  update [component]    更新组件"
    echo "    maibot               更新MaiBot本体"
    echo "    adapter              更新MaiBot-NapCat-Adapter"
    echo "    napcat               更新NapcatQQ"
    echo "    all                  更新所有组件"
    echo ""
    echo "  help                  显示此帮助信息"
    echo ""
    echo "Screen会话管理说明:"
    echo "  - 使用 Ctrl+A 然后按 D 来脱离会话"
    echo "  - 使用 'maibot switch <component>' 重新连接到会话"
    echo "  - 会话在后台持续运行，即使SSH断开也不会停止"
    echo ""
    echo "示例:"
    echo "  maibot start all         # 启动所有组件"
    echo "  maibot switch maibot     # 切换到MaiBot本体会话"
    echo "  maibot list              # 查看所有会话"
    echo "  maibot status            # 查看所有组件状态"
}

start_maibot() {
    echo "在Screen会话中启动MaiBot本体..."
    if [[ -d "\$MAIBOT_DIR" ]]; then
        if screen -list | grep -q "\$SESSION_MAIBOT"; then
            echo "MaiBot本体会话已存在，使用 'maibot switch maibot' 连接"
            return 0
        fi
        
        cd "\$MAIBOT_DIR"
        # 检查bot.py文件是否存在
        if [[ -f "bot.py" ]]; then
            # 直接启动bot.py，确保虚拟环境激活
            screen -dmS "\$SESSION_MAIBOT" bash -c "cd '\$MAIBOT_DIR' && source venv/bin/activate && python3 bot.py"
            sleep 2
            if screen -list | grep -q "\$SESSION_MAIBOT"; then
                echo "MaiBot本体已在Screen会话 '\$SESSION_MAIBOT' 中启动"
                echo "使用 'maibot switch maibot' 连接到会话"
            else
                echo "错误: MaiBot本体启动失败"
                return 1
            fi
        else
            echo "错误: 未找到MaiBot启动文件 bot.py"
            echo "请确保MaiBot已正确安装"
            return 1
        fi
    else
        echo "错误: MaiBot安装目录不存在: \$MAIBOT_DIR"
        return 1
    fi
}

start_adapter() {
    echo "在Screen会话中启动MaiBot-NapCat-Adapter..."
    if [[ -d "\$ADAPTER_DIR" ]]; then
        if screen -list | grep -q "\$SESSION_ADAPTER"; then
            echo "MaiBot-NapCat-Adapter会话已存在，使用 'maibot switch adapter' 连接"
            return 0
        fi
        
        cd "\$ADAPTER_DIR"
        if [[ -f "start.sh" ]]; then
            # 创建启动脚本包装器，确保虚拟环境激活
            screen -dmS "\$SESSION_ADAPTER" bash -c "cd '\$ADAPTER_DIR' && source venv/bin/activate && ./start.sh"
            sleep 2
            if screen -list | grep -q "\$SESSION_ADAPTER"; then
                echo "MaiBot-NapCat-Adapter已在Screen会话 '\$SESSION_ADAPTER' 中启动"
                echo "使用 'maibot switch adapter' 连接到会话"
            else
                echo "错误: MaiBot-NapCat-Adapter启动失败"
                return 1
            fi
        else
            echo "错误: 未找到启动脚本 start.sh"
            return 1
        fi
    else
        echo "错误: Adapter安装目录不存在: \$ADAPTER_DIR"
        return 1
    fi
}

start_napcat() {
    echo "在Screen会话中启动NapcatQQ..."
    if [[ -d "\$NAPCAT_DIR" ]]; then
        if screen -list | grep -q "\$SESSION_NAPCAT"; then
            echo "NapcatQQ会话已存在，使用 'maibot switch napcat' 连接"
            return 0
        fi
        
        cd "\$NAPCAT_DIR"
        # 启动虚拟显示服务器和NapcatQQ
        screen -dmS "\$SESSION_NAPCAT" bash -c "
            cd '\$NAPCAT_DIR'
            # 启动虚拟显示服务器
            if ! pgrep -f 'Xvfb :1' > /dev/null; then
                Xvfb :1 -screen 0 1024x768x24 +extension GLX +render > /dev/null 2>&1 &
                sleep 3
            fi
            export DISPLAY=:1
            # 启动NapcatQQ
            LD_PRELOAD=./libnapcat_launcher.so qq --no-sandbox
        "
        sleep 5
        if screen -list | grep -q "\$SESSION_NAPCAT"; then
            echo "NapcatQQ已在Screen会话 '\$SESSION_NAPCAT' 中启动"
            echo "使用 'maibot switch napcat' 连接到会话"
        else
            echo "错误: NapcatQQ启动失败"
            return 1
        fi
    else
        echo "错误: NapCat安装目录不存在: \$NAPCAT_DIR"
        return 1
    fi
}

stop_component() {
    local component=\$1
    local session_name=""
    
    case "\$component" in
        maibot)
            session_name="\$SESSION_MAIBOT"
            ;;
        adapter)
            session_name="\$SESSION_ADAPTER"
            ;;
        napcat)
            session_name="\$SESSION_NAPCAT"
            ;;
        *)
            echo "错误: 未知组件 '\$component'"
            return 1
            ;;
    esac
    
    if screen -list | grep -q "\$session_name"; then
        screen -S "\$session_name" -X quit
        echo "\$component 会话已停止"
        
        # 如果是napcat，还需要清理虚拟显示服务器
        if [[ "\$component" == "napcat" ]]; then
            pkill -f "Xvfb :1" 2>/dev/null || true
            echo "虚拟显示服务器已清理"
        fi
    else
        echo "\$component 会话未运行"
    fi
}

status_component() {
    local component=\$1
    local session_name=""
    
    case "\$component" in
        maibot)
            session_name="\$SESSION_MAIBOT"
            ;;
        adapter)
            session_name="\$SESSION_ADAPTER"
            ;;
        napcat)
            session_name="\$SESSION_NAPCAT"
            ;;
        *)
            echo "错误: 未知组件 '\$component'"
            return 1
            ;;
    esac
    
    if screen -list | grep -q "\$session_name"; then
        echo "\$component: 运行中 (Screen会话: \$session_name)"
    else
        echo "\$component: 已停止"
    fi
}

switch_to_session() {
    local component=\$1
    local session_name=""
    
    case "\$component" in
        maibot)
            session_name="\$SESSION_MAIBOT"
            ;;
        adapter)
            session_name="\$SESSION_ADAPTER"
            ;;
        napcat)
            session_name="\$SESSION_NAPCAT"
            ;;
        *)
            echo "错误: 未知组件 '\$component'"
            echo "可用组件: maibot, adapter, napcat"
            return 1
            ;;
    esac
    
    if screen -list | grep -q "\$session_name"; then
        echo "连接到 \$component 会话..."
        echo "提示: 使用 Ctrl+A 然后按 D 脱离会话"
        screen -r "\$session_name"
    else
        echo "错误: \$component 会话不存在或未运行"
        echo "使用 'maibot start \$component' 启动组件"
        return 1
    fi
}

list_sessions() {
    echo "MaiBot相关的Screen会话:"
    echo "========================"
    local found=false
    
    if screen -list | grep -q "\$SESSION_MAIBOT"; then
        echo "✓ \$SESSION_MAIBOT (MaiBot本体)"
        found=true
    fi
    
    if screen -list | grep -q "\$SESSION_ADAPTER"; then
        echo "✓ \$SESSION_ADAPTER (MaiBot-NapCat-Adapter)"
        found=true
    fi
    
    if screen -list | grep -q "\$SESSION_NAPCAT"; then
        echo "✓ \$SESSION_NAPCAT (NapcatQQ)"
        found=true
    fi
    
    if [[ "\$found" == "false" ]]; then
        echo "没有运行中的MaiBot会话"
        echo "使用 'maibot start all' 启动所有组件"
    fi
    
    echo ""
    echo "使用 'maibot switch <component>' 连接到指定会话"
}

# 检查screen是否安装
check_screen

case "\$1" in
    start)
        case "\$2" in
            maibot)
                start_maibot
                ;;
            adapter)
                start_adapter
                ;;
            napcat)
                start_napcat
                ;;
            all|"")
                echo "启动所有MaiBot组件..."
                start_napcat
                sleep 3
                start_adapter
                sleep 2
                start_maibot
                echo ""
                echo "所有组件启动完成！"
                echo "使用 'maibot list' 查看所有会话"
                echo "使用 'maibot switch <component>' 连接到指定会话"
                ;;
            *)
                echo "错误: 未知组件 '\$2'"
                echo "使用 'maibot help' 查看可用命令"
                exit 1
                ;;
        esac
        ;;
    stop)
        case "\$2" in
            maibot)
                stop_component "maibot"
                ;;
            adapter)
                stop_component "adapter"
                ;;
            napcat)
                stop_component "napcat"
                ;;
            all|"")
                echo "停止所有MaiBot组件..."
                stop_component "maibot"
                stop_component "adapter"
                stop_component "napcat"
                echo "所有组件已停止"
                ;;
            *)
                echo "错误: 未知组件 '\$2'"
                echo "使用 'maibot help' 查看可用命令"
                exit 1
                ;;
        esac
        ;;
    switch)
        if [[ -z "\$2" ]]; then
            echo "错误: 请指定要切换的组件"
            echo "用法: maibot switch <component>"
            echo "可用组件: maibot, adapter, napcat"
            exit 1
        fi
        switch_to_session "\$2"
        ;;
    status)
        case "\$2" in
            maibot)
                status_component "maibot"
                ;;
            adapter)
                status_component "adapter"
                ;;
            napcat)
                status_component "napcat"
                ;;
            all|"")
                echo "MaiBot组件状态:"
                echo "==============="
                status_component "maibot"
                status_component "adapter"
                status_component "napcat"
                ;;
            *)
                echo "错误: 未知组件 '\$2'"
                echo "使用 'maibot help' 查看可用命令"
                exit 1
                ;;
        esac
        ;;
    list)
        list_sessions
        ;;
    restart)
        case "\$2" in
            maibot)
                stop_component "maibot"
                sleep 2
                start_maibot
                ;;
            adapter)
                stop_component "adapter"
                sleep 2
                start_adapter
                ;;
            napcat)
                stop_component "napcat"
                sleep 2
                start_napcat
                ;;
            all|"")
                echo "重启所有MaiBot组件..."
                stop_component "maibot"
                stop_component "adapter"
                stop_component "napcat"
                sleep 3
                start_napcat
                sleep 3
                start_adapter
                sleep 2
                start_maibot
                echo "所有组件重启完成"
                ;;
            *)
                echo "错误: 未知组件 '\$2'"
                echo "使用 'maibot help' 查看可用命令"
                exit 1
                ;;
        esac
        ;;
    logs)
        case "\$2" in
            maibot)
                if [[ -f "\$MAIBOT_DIR/logs/maibot.log" ]]; then
                    tail -f "\$MAIBOT_DIR/logs/maibot.log"
                else
                    echo "日志文件不存在: \$MAIBOT_DIR/logs/maibot.log"
                fi
                ;;
            adapter)
                if [[ -f "\$ADAPTER_DIR/logs/adapter.log" ]]; then
                    tail -f "\$ADAPTER_DIR/logs/adapter.log"
                else
                    echo "日志文件不存在: \$ADAPTER_DIR/logs/adapter.log"
                fi
                ;;
            napcat)
                if [[ -f "\$NAPCAT_DIR/logs/napcat.log" ]]; then
                    tail -f "\$NAPCAT_DIR/logs/napcat.log"
                else
                    echo "日志文件不存在: \$NAPCAT_DIR/logs/napcat.log"
                fi
                ;;
            *)
                echo "错误: 请指定要查看日志的组件 (maibot|adapter|napcat)"
                echo "使用 'maibot help' 查看可用命令"
                exit 1
                ;;
        esac
        ;;
    update)
        echo "更新功能暂未实现"
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "错误: 未知命令 '\$1'"
        echo "使用 'maibot help' 查看可用命令"
        exit 1
        ;;
esac
EOF
    
    # 设置执行权限
    sudo chmod +x "$maibot_script"
    
    # 验证命令是否创建成功
    if [[ -f "$maibot_script" ]]; then
        print_success "全局maibot命令创建成功 (Screen版本)"
        print_info "现在您可以使用以下命令:"
        print_info "  maibot start all      # 在Screen会话中启动所有组件"
        print_info "  maibot switch maibot  # 切换到MaiBot本体会话"
        print_info "  maibot switch adapter # 切换到适配器会话"
        print_info "  maibot switch napcat  # 切换到NapcatQQ会话"
        print_info "  maibot list           # 列出所有活动会话"
        print_info "  maibot status         # 查看所有组件状态"
        print_info "  maibot help           # 查看完整帮助"
        print_warning "注意: 需要先安装screen包才能使用新功能"
    else
        print_error "全局maibot命令创建失败"
        return 1
    fi
}

# 安装MaiBot本体
install_maibot() {
    print_info "开始安装MaiBot本体..."
    
    # 检查安装目录
    if [[ ! -d "$MAIBOT_DIR" ]]; then
        print_error "MaiBot安装目录不存在: $MAIBOT_DIR"
        return 1
    fi
    
    # 切换到安装目录的父目录
    cd "$(dirname "$MAIBOT_DIR")" || {
        print_error "无法进入安装目录"
        return 1
    }
    
    # 检查目录是否为空
    if [[ -d "$MAIBOT_DIR" ]] && [[ -n "$(ls -A "$MAIBOT_DIR" 2>/dev/null)" ]]; then
        print_warning "MaiBot目录不为空，清理现有内容..."
        rm -rf "$MAIBOT_DIR"
        mkdir -p "$MAIBOT_DIR"
    fi
    
    # 测试GitHub镜像
    local maibot_repo="https://github.com/MaiM-with-u/MaiBot.git"
    local test_url="https://github.com/MaiM-with-u/MaiBot"
    local mirror_prefix=""
    
    print_info "测试GitHub连接性..."
    mirror_prefix=$(test_github_mirrors "$test_url")
    
    # 构建完整的克隆URL
    local clone_url="$maibot_repo"
    if [[ -n "$mirror_prefix" ]]; then
        clone_url="$mirror_prefix/$maibot_repo"
        print_info "使用镜像站点克隆: $mirror_prefix"
        print_debug "构建的克隆URL: $clone_url"
    else
        print_info "使用GitHub直连克隆"
        print_debug "使用直连URL: $clone_url"
    fi
    
    # 克隆MaiBot仓库
    print_info "克隆MaiBot本体..."
    print_debug "执行命令: git clone --depth=1 '$clone_url' '$MAIBOT_DIR'"
    if ! git clone --depth=1 "$clone_url" "$MAIBOT_DIR" 2>>"$LOG_FILE"; then
        print_error "无法克隆MaiBot仓库"
        print_debug "克隆失败的URL: $clone_url"
        log_message "ERROR: git clone failed for URL: $clone_url"
        
        # 如果使用镜像失败，尝试直连
        if [[ -n "$mirror_prefix" ]]; then
            print_warning "镜像站点失败，尝试直连..."
            print_debug "执行命令: git clone --depth=1 '$maibot_repo' '$MAIBOT_DIR'"
            if ! git clone --depth=1 "$maibot_repo" "$MAIBOT_DIR" 2>>"$LOG_FILE"; then
                print_error "直连也失败，无法下载MaiBot本体"
                print_debug "直连失败的URL: $maibot_repo"
                log_message "ERROR: git clone failed for fallback URL: $maibot_repo"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    print_success "MaiBot本体克隆成功"
    
    # 切换到MaiBot目录
    cd "$MAIBOT_DIR" || {
        print_error "无法进入MaiBot目录"
        return 1
    }
    
    # 创建Python虚拟环境
    print_info "创建Python虚拟环境..."
    python3 -m venv venv || {
        print_error "无法创建Python虚拟环境"
        return 1
    }
    
    print_success "Python虚拟环境创建成功"
    
    # 激活虚拟环境并安装依赖
    print_info "激活虚拟环境并安装依赖..."
    
    # 激活虚拟环境并安装依赖
    # 使用source命令激活虚拟环境，然后安装依赖
    print_info "使用阿里云镜像源安装Python依赖..."
    if ! bash -c "source venv/bin/activate && pip install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/ && pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/"; then
        print_error "无法安装Python依赖"
        return 1
    fi
    
    print_success "Python依赖安装完成"
    
    # 初始化配置
    print_info "初始化MaiBot配置..."
    
    # 创建配置目录
    mkdir -p config logs data
    
    # 复制示例配置文件
    print_info "复制示例配置文件..."
    
    # 复制bot_config_template.toml到config目录
    if [[ -f "template/bot_config_template.toml" ]]; then
        cp "template/bot_config_template.toml" "config/bot_config.toml"
        print_success "已复制bot_config.toml配置文件"
    else
        print_warning "未找到template/bot_config_template.toml文件"
    fi
    
    # 复制lpmm_config_template.toml到config目录
    if [[ -f "template/lpmm_config_template.toml" ]]; then
        cp "template/lpmm_config_template.toml" "config/lpmm_config.toml"
        print_success "已复制lpmm_config.toml配置文件"
    else
        print_warning "未找到template/lpmm_config_template.toml文件"
    fi
    
    # 复制template.env到MaiBot根目录并重命名为.env
    if [[ -f "template/template.env" ]]; then
        cp "template/template.env" ".env"
        print_success "已复制.env环境配置文件"
    else
        print_warning "未找到template/template.env文件"
    fi
    
    # 设置执行权限
    find . -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    
    # 设置执行权限
    find . -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    # 创建全局maibot命令
    print_info "创建全局maibot命令..."
    create_global_command
    
    print_success "MaiBot本体安装完成"
    print_info "虚拟环境位置: $MAIBOT_DIR/venv"
    print_info "配置文件位置: $MAIBOT_DIR/config/"
    print_info "启动脚本: $MAIBOT_DIR/start.sh"
    
    log_message "MaiBot本体安装完成: $MAIBOT_DIR"
    return 0
}

# 安装MaiBot-NapCat-Adapter
install_adapter() {
    print_info "开始安装MaiBot-NapCat-Adapter..."
    
    # 检查安装目录
    if [[ ! -d "$ADAPTER_DIR" ]]; then
        print_error "Adapter安装目录不存在: $ADAPTER_DIR"
        return 1
    fi
    
    # 切换到安装目录的父目录
    cd "$(dirname "$ADAPTER_DIR")" || {
        print_error "无法进入安装目录"
        return 1
    }
    
    # 检查目录是否为空
    if [[ -d "$ADAPTER_DIR" ]] && [[ -n "$(ls -A "$ADAPTER_DIR" 2>/dev/null)" ]]; then
        print_warning "Adapter目录不为空，清理现有内容..."
        rm -rf "$ADAPTER_DIR"
        mkdir -p "$ADAPTER_DIR"
    fi
    
    # 测试GitHub镜像
    local adapter_repo="https://github.com/MaiM-with-u/MaiBot-NapCat-Adapter.git"
    local test_url="https://github.com/MaiM-with-u/MaiBot-NapCat-Adapter"
    local mirror_prefix=""
    
    print_info "测试GitHub连接性..."
    mirror_prefix=$(test_github_mirrors "$test_url")
    
    # 构建完整的克隆URL
    local clone_url="$adapter_repo"
    if [[ -n "$mirror_prefix" ]]; then
        clone_url="$mirror_prefix/$adapter_repo"
        print_info "使用镜像站点克隆: $mirror_prefix"
        print_debug "构建的克隆URL: $clone_url"
    else
        print_info "使用GitHub直连克隆"
        print_debug "使用直连URL: $clone_url"
    fi
    
    # 克隆Adapter仓库
    print_info "克隆MaiBot-NapCat-Adapter..."
    print_debug "执行命令: git clone --depth=1 '$clone_url' '$ADAPTER_DIR'"
    if ! git clone --depth=1 "$clone_url" "$ADAPTER_DIR" 2>>"$LOG_FILE"; then
        print_error "无法克隆MaiBot-NapCat-Adapter仓库"
        print_debug "克隆失败的URL: $clone_url"
        log_message "ERROR: git clone failed for URL: $clone_url"
        
        # 如果使用镜像失败，尝试直连
        if [[ -n "$mirror_prefix" ]]; then
            print_warning "镜像站点失败，尝试直连..."
            print_debug "执行命令: git clone --depth=1 '$adapter_repo' '$ADAPTER_DIR'"
            if ! git clone --depth=1 "$adapter_repo" "$ADAPTER_DIR" 2>>"$LOG_FILE"; then
                print_error "直连也失败，无法下载MaiBot-NapCat-Adapter"
                print_debug "直连失败的URL: $adapter_repo"
                log_message "ERROR: git clone failed for fallback URL: $adapter_repo"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    print_success "MaiBot-NapCat-Adapter克隆成功"
    
    # 切换到Adapter目录
    cd "$ADAPTER_DIR" || {
        print_error "无法进入Adapter目录"
        return 1
    }
    
    # 创建Python虚拟环境
    print_info "创建Python虚拟环境..."
    python3 -m venv venv || {
        print_error "无法创建Python虚拟环境"
        return 1
    }
    
    print_success "Python虚拟环境创建成功"
    
    # 激活虚拟环境并安装依赖
    print_info "激活虚拟环境并安装依赖..."
    
    # 检查requirements.txt是否存在
    if [[ ! -f "requirements.txt" ]]; then
        print_warning "未找到requirements.txt文件"
        # 创建基本的requirements.txt
        cat > requirements.txt << 'EOF'
# 基本依赖
requests>=2.25.0
aiohttp>=3.8.0
websockets>=10.0
pydantic>=1.8.0
loguru>=0.6.0
asyncio-mqtt>=0.11.0
EOF
        print_info "已创建基本的requirements.txt文件"
    fi
    
    # 激活虚拟环境并安装依赖
    print_info "使用阿里云镜像源安装Python依赖..."
    if ! bash -c "source venv/bin/activate && pip install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/ && pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/"; then
        print_error "无法安装Python依赖"
        return 1
    fi
    
    print_success "Python依赖安装完成"
    
    # 初始化配置
    print_info "初始化Adapter配置..."
    
    # 创建配置目录
    mkdir -p config logs data
    
    # 复制配置文件模板
    if [[ -f "template/template_config.toml" ]]; then
        cp "template/template_config.toml" "config.toml"
        print_success "已复制template_config.toml配置文件"
    else
        print_warning "未找到template/template_config.toml文件"
    fi
    
    # 设置执行权限
    find . -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    print_success "MaiBot-NapCat-Adapter安装完成"
    print_info "虚拟环境位置: $ADAPTER_DIR/venv"
    print_info "配置文件位置: $ADAPTER_DIR/config/"
    print_info "启动脚本: $ADAPTER_DIR/start.sh"
    
    log_message "MaiBot-NapCat-Adapter安装完成: $ADAPTER_DIR"
    return 0
}

# 安装NapcatQQ
install_napcat() {
    print_info "开始安装NapcatQQ..."
    
    # 检查安装目录
    if [[ ! -d "$NAPCAT_DIR" ]]; then
        print_error "NapcatQQ安装目录不存在: $NAPCAT_DIR"
        return 1
    fi
    
    # 切换到安装目录
    cd "$NAPCAT_DIR" || {
        print_error "无法进入NapcatQQ安装目录"
        return 1
    }
    
    # 检测系统架构
    print_info "检测系统架构..."
    local arch=$(uname -m)
    local system_arch=""
    
    case "$arch" in
        x86_64)
            system_arch="amd64"
            ;;
        aarch64)
            system_arch="arm64"
            ;;
        *)
            print_error "不支持的系统架构: $arch"
            return 1
            ;;
    esac
    
    print_success "系统架构: $system_arch"
    
    # 网络测试和代理选择
    print_info "测试Github网络连接..."
    local proxy_arr=("https://ghfast.top" "https://gh.wuliya.xin" "https://gh-proxy.com" "https://github.moeyy.xyz")
    local check_url="https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"
    local target_proxy=""
    local timeout=10
    
    for proxy in "${proxy_arr[@]}"; do
        print_debug "测试代理: $proxy"
        local status=$(curl -k -L --connect-timeout $timeout --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "$proxy/$check_url" 2>/dev/null)
        if [[ "$status" == "200" ]]; then
            target_proxy="$proxy"
            print_success "使用Github代理: $proxy"
            break
        fi
    done
    
    if [[ -z "$target_proxy" ]]; then
        print_warning "无法找到可用的Github代理，尝试直连..."
        local status=$(curl -k --connect-timeout $timeout --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "$check_url" 2>/dev/null)
        if [[ "$status" != "200" ]]; then
            print_warning "无法连接到Github，将继续尝试安装，但可能会失败"
        else
            print_success "直连Github成功"
        fi
    fi
    
    # 下载NapCat Shell
    print_info "下载NapCat Shell..."
    local napcat_file="NapCat.Shell.zip"
    
    if [[ -f "$napcat_file" ]]; then
        print_info "检测到已下载的NapCat安装包，跳过下载..."
    else
        local napcat_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
        if [[ -n "$target_proxy" ]]; then
            napcat_url="$target_proxy/$napcat_url"
        fi
        
        curl -k -L -# "$napcat_url" -o "$napcat_file" 2>>"$LOG_FILE" || {
            print_error "NapCat Shell下载失败"
            log_message "ERROR: curl failed for URL: $napcat_url"
            return 1
        }
        print_success "NapCat Shell下载成功"
    fi
    
    # 验证和解压
    print_info "验证压缩包..."
    unzip -t "$napcat_file" > /dev/null 2>&1 || {
        print_error "压缩包验证失败"
        rm -f "$napcat_file"
        return 1
    }
    
    print_info "解压NapCat Shell..."
    unzip -q -o "$napcat_file" || {
        print_error "解压失败"
        return 1
    }
    
    # 安装LinuxQQ
    print_info "安装LinuxQQ..."
    install_linux_qq "$system_arch" || {
        print_error "LinuxQQ安装失败"
        return 1
    }
    
    # 下载和编译launcher
    print_info "下载并编译NapCat启动器..."
    install_napcat_launcher "$target_proxy" || {
        print_error "NapCat启动器安装失败"
        return 1
    }
    
    # 清理临时文件
    rm -f "$napcat_file" QQ.rpm QQ.deb launcher.cpp 2>/dev/null || true
    
    print_success "NapcatQQ安装完成"
    log_message "NapcatQQ安装完成: $NAPCAT_DIR"
    return 0
}

# 安装LinuxQQ的辅助函数
install_linux_qq() {
    local system_arch="$1"
    local qq_url=""
    
    # 根据架构和包管理器确定下载链接
    if [[ "$system_arch" == "amd64" ]]; then
        case "$PACKAGE_MANAGER" in
            yum|dnf)
                qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/5aa2d8d6/linuxqq_3.2.17-34740_x86_64.rpm"
                ;;
            apt)
                qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/5aa2d8d6/linuxqq_3.2.17-34740_amd64.deb"
                ;;
        esac
    elif [[ "$system_arch" == "arm64" ]]; then
        case "$PACKAGE_MANAGER" in
            yum|dnf)
                qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/5aa2d8d6/linuxqq_3.2.17-34740_aarch64.rpm"
                ;;
            apt)
                qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/5aa2d8d6/linuxqq_3.2.17-34740_arm64.deb"
                ;;
        esac
    fi
    
    if [[ -z "$qq_url" ]]; then
        print_error "不支持的架构或包管理器组合: $system_arch + $PACKAGE_MANAGER"
        return 1
    fi
    
    # 下载和安装QQ
    case "$PACKAGE_MANAGER" in
        yum|dnf)
            if [[ ! -f "QQ.rpm" ]]; then
                curl -k -L -# "$qq_url" -o QQ.rpm 2>>"$LOG_FILE" || {
                    print_error "QQ下载失败"
                    log_message "ERROR: curl failed for QQ URL: $qq_url"
                    return 1
                }
            fi
            $INSTALL_CMD ./QQ.rpm 2>>"$LOG_FILE" || {
                print_error "QQ安装失败"
                log_message "ERROR: QQ package install failed"
                return 1
            }
            # 安装额外依赖
            print_info "安装QQ运行依赖..."
            $INSTALL_CMD nss libXScrnSaver || print_warning "某些依赖安装失败，但可能不影响运行"
            # 对于RHEL/CentOS/Fedora，音频库通常是 alsa-lib
            $INSTALL_CMD alsa-lib || print_warning "音频库安装失败，但可能不影响运行"
            ;;
        apt)
            if [[ ! -f "QQ.deb" ]]; then
                curl -k -L -# "$qq_url" -o QQ.deb 2>>"$LOG_FILE" || {
                    print_error "QQ下载失败"
                    log_message "ERROR: curl failed for QQ URL: $qq_url"
                    return 1
                }
            fi
            # 安装QQ及其依赖
            apt install -f -y --allow-downgrades ./QQ.deb 2>>"$LOG_FILE" || {
                print_error "QQ安装失败"
                log_message "ERROR: QQ package install failed"
                return 1
            }
            # 安装额外依赖
            $INSTALL_CMD libnss3 libgbm1 || true
            
            # 智能安装 libasound2 依赖
            print_info "安装音频依赖..."
            if apt list --installed libasound2t64 2>/dev/null | grep -q libasound2t64; then
                print_info "检测到 libasound2t64 已安装"
            elif apt-cache show libasound2t64 >/dev/null 2>&1; then
                print_info "使用 libasound2t64 (新版本)"
                $INSTALL_CMD libasound2t64 || print_warning "libasound2t64 安装失败，但可能不影响运行"
            elif apt-cache show libasound2 >/dev/null 2>&1; then
                print_info "使用 libasound2 (传统版本)"
                $INSTALL_CMD libasound2 || print_warning "libasound2 安装失败，但可能不影响运行"
            else
                print_warning "无法找到合适的音频库，尝试安装liboss4-salsa-asound2"
                $INSTALL_CMD liboss4-salsa-asound2 || print_warning "音频库安装失败，但可能不影响运行"
            fi
            ;;
    esac
    
    print_success "LinuxQQ安装完成"
    return 0
}

# 安装NapCat启动器的辅助函数
install_napcat_launcher() {
    local target_proxy="$1"
    local cpp_url="https://raw.githubusercontent.com/NapNeko/napcat-linux-launcher/refs/heads/main/launcher.cpp"
    local cpp_file="launcher.cpp"
    local so_file="libnapcat_launcher.so"
    
    # 构建下载URL
    local download_url="$cpp_url"
    if [[ -n "$target_proxy" ]]; then
        local cpp_url_path="${cpp_url#https://}"
        download_url="$target_proxy/$cpp_url_path"
    fi
    
    # 下载源码
    curl -k -L -# "$download_url" -o "$cpp_file" 2>>"$LOG_FILE" || {
        print_error "启动器源码下载失败"
        log_message "ERROR: curl failed for launcher source: $download_url"
        return 1
    }
    
    # 编译
    g++ -shared -fPIC "$cpp_file" -o "$so_file" -ldl 2>>"$LOG_FILE" || {
        print_error "启动器编译失败，请检查g++是否安装"
        log_message "ERROR: g++ compilation failed for launcher"
        return 1
    }
    
    print_success "NapCat启动器编译完成"
    return 0
}

# 配置模块间连接
configure_modules() {
    print_info "配置模块间连接..."
    
    # 配置NapcatQQ
    print_info "配置NapcatQQ..."
    if [[ -d "$NAPCAT_DIR" ]]; then
        cd "$NAPCAT_DIR" || {
            print_warning "无法进入NapcatQQ目录，跳过配置"
        }
        
        # 创建NapCat配置文件
        mkdir -p config
        cat > config/onebot11.json << 'EOF'
{
    "http": {
        "enable": true,
        "host": "0.0.0.0",
        "port": 6099,
        "secret": "",
        "enableHeart": true,
        "enablePost": false,
        "postUrls": []
    },
    "ws": {
        "enable": true,
        "host": "0.0.0.0",
        "port": 6099
    },
    "reverseWs": {
        "enable": false,
        "urls": []
    },
    "GroupLocalTime": {
        "Record": false,
        "RecordList": []
    },
    "debug": false,
    "heartInterval": 30000,
    "messagePostFormat": "array",
    "enableLocalFile2Url": true,
    "musicSignUrl": "",
    "reportSelfMessage": false,
    "token": ""
}
EOF
        print_success "NapcatQQ配置文件已创建"
    fi
    
    # 配置MaiBot-NapCat-Adapter
    print_info "配置MaiBot-NapCat-Adapter..."
    if [[ -d "$ADAPTER_DIR" ]] && [[ -f "$ADAPTER_DIR/config/config.json" ]]; then
        cd "$ADAPTER_DIR" || {
            print_warning "无法进入Adapter目录，跳过配置"
        }
        
        # 更新Adapter配置文件
        cat > config/config.json << 'EOF'
{
    "napcat": {
        "ws_url": "ws://localhost:6099",
        "http_url": "http://localhost:6099",
        "access_token": ""
    },
    "maibot": {
        "ws_url": "ws://localhost:8080",
        "http_url": "http://localhost:8080",
        "access_token": ""
    },
    "adapter": {
        "host": "0.0.0.0",
        "port": 7099,
        "debug": false,
        "reconnect_interval": 5,
        "forward_events": true,
        "forward_api": true
    },
    "logging": {
        "level": "INFO",
        "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        "file": "logs/adapter.log",
        "max_bytes": 10485760,
        "backup_count": 5
    }
}
EOF
        print_success "MaiBot-NapCat-Adapter配置文件已更新"
    fi
    
    # 配置MaiBot
    print_info "配置MaiBot..."
    if [[ -d "$MAIBOT_DIR" ]]; then
        cd "$MAIBOT_DIR" || {
            print_warning "无法进入MaiBot目录，跳过配置"
        }
        
        # 创建或更新MaiBot配置文件
        if [[ ! -f "config/config.json" ]] && [[ ! -f "config/config.yaml" ]]; then
            # 创建基本配置文件
            cat > config/config.json << 'EOF'
{
    "bot": {
        "name": "MaiBot",
        "admin_users": [],
        "command_prefix": "/",
        "auto_accept_friend": false,
        "auto_accept_group": false
    },
    "adapter": {
        "type": "onebot_v11",
        "host": "localhost",
        "port": 7099,
        "access_token": "",
        "heartbeat_interval": 30000
    },
    "plugins": {
        "enabled": [],
        "disabled": [],
        "plugin_dirs": ["plugins"]
    },
    "database": {
        "type": "sqlite",
        "url": "sqlite:///data/maibot.db"
    },
    "logging": {
        "level": "INFO",
        "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        "file": "logs/maibot.log",
        "console": true
    }
}
EOF
            print_success "MaiBot配置文件已创建"
        else
            print_info "MaiBot配置文件已存在，跳过创建"
        fi
    fi
    
    # 生成启动脚本
    print_info "生成启动脚本..."
    create_startup_scripts
    
    # 创建环境变量配置
    print_info "创建环境变量配置..."
    cat > "$INSTALL_BASE_DIR/maibot.env" << EOF
# MaiBot环境变量配置
export MAIBOT_HOME="$MAIBOT_DIR"
export ADAPTER_HOME="$ADAPTER_DIR"
export NAPCAT_HOME="$NAPCAT_DIR"
export MAIBOT_CONFIG="$MAIBOT_DIR/config"
export ADAPTER_CONFIG="$ADAPTER_DIR/config"
export NAPCAT_CONFIG="$NAPCAT_DIR/config"
export DISPLAY=:1
EOF
    
    # 创建服务管理脚本
    print_info "创建服务管理脚本..."
    cat > "$INSTALL_BASE_DIR/maibot-service.sh" << 'EOF'
#!/bin/bash
# MaiBot服务管理脚本

MAIBOT_BASE="/opt/maibot"
MAIBOT_ENV="$MAIBOT_BASE/maibot.env"

# 加载环境变量
if [[ -f "$MAIBOT_ENV" ]]; then
    source "$MAIBOT_ENV"
fi

# 获取进程ID
get_pid() {
    local service="$1"
    case "$service" in
        maibot)
            pgrep -f "python3.*bot.py" | grep -v grep | head -1
            ;;
        adapter)
            pgrep -f "maibot-napcat-adapter.*main.py" | grep -v grep | head -1
            ;;
        napcat)
            pgrep -f "LD_PRELOAD.*libnapcat_launcher.so" | grep -v grep | head -1
            ;;
        xvfb)
            pgrep -f "Xvfb :1" | grep -v grep | head -1
            ;;
    esac
}

# 检查服务状态
status() {
    local service="$1"
    local pid=$(get_pid "$service")
    if [[ -n "$pid" ]]; then
        echo "$service is running (PID: $pid)"
        return 0
    else
        echo "$service is not running"
        return 1
    fi
}

# 启动服务
start() {
    local service="$1"
    
    case "$service" in
        xvfb)
            if ! status xvfb > /dev/null; then
                echo "Starting Xvfb..."
                Xvfb :1 -screen 0 1024x768x24 +extension GLX +render > /dev/null 2>&1 &
                sleep 2
            fi
            ;;
        napcat)
            start xvfb
            if ! status napcat > /dev/null; then
                echo "Starting NapCat..."
                cd "$NAPCAT_HOME"
                nohup bash -c "export DISPLAY=:1; LD_PRELOAD=./libnapcat_launcher.so qq --no-sandbox" > /dev/null 2>&1 &
                sleep 5
            fi
            ;;
        adapter)
            if ! status adapter > /dev/null; then
                echo "Starting Adapter..."
                cd "$ADAPTER_HOME"
                source venv/bin/activate
                nohup python3 main.py > /dev/null 2>&1 &
                sleep 3
            fi
            ;;
        maibot)
            if ! status maibot > /dev/null; then
                echo "Starting MaiBot..."
                cd "$MAIBOT_HOME"
                source venv/bin/activate
                nohup python3 bot.py > /dev/null 2>&1 &
                sleep 2
            fi
            ;;
        all)
            start xvfb
            start napcat
            start adapter
            start maibot
            ;;
    esac
}

# 停止服务
stop() {
    local service="$1"
    local pid=$(get_pid "$service")
    
    if [[ -n "$pid" ]]; then
        echo "Stopping $service (PID: $pid)..."
        kill "$pid"
        sleep 2
        
        # 强制停止
        if kill -0 "$pid" 2>/dev/null; then
            echo "Force stopping $service..."
            kill -9 "$pid"
        fi
    else
        echo "$service is not running"
    fi
}

# 重启服务
restart() {
    local service="$1"
    stop "$service"
    sleep 2
    start "$service"
}

# 显示所有服务状态
status_all() {
    echo "=== MaiBot 服务状态 ==="
    status xvfb
    status napcat
    status adapter
    status maibot
}

# 主函数
case "$1" in
    start)
        start "${2:-all}"
        ;;
    stop)
        if [[ "$2" == "all" ]] || [[ -z "$2" ]]; then
            stop maibot
            stop adapter
            stop napcat
            stop xvfb
        else
            stop "$2"
        fi
        ;;
    restart)
        restart "${2:-all}"
        ;;
    status)
        if [[ -z "$2" ]]; then
            status_all
        else
            status "$2"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status} [service]"
        echo "Services: maibot, adapter, napcat, xvfb, all"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$INSTALL_BASE_DIR/maibot-service.sh"
    
    print_success "模块连接配置完成"
    print_info "配置文件位置:"
    print_info "  NapcatQQ: $NAPCAT_DIR/config/onebot11.json"
    print_info "  Adapter: $ADAPTER_DIR/config/config.json"
    print_info "  MaiBot: $MAIBOT_DIR/config/config.json"
    print_info "服务管理: $INSTALL_BASE_DIR/maibot-service.sh {start|stop|restart|status}"
    
    log_message "模块连接配置完成"
}

# 创建启动脚本
create_startup_scripts() {
    print_info "所有功能已整合到maibot命令中，无需创建单独的启动脚本"
    print_success "maibot命令已包含所有启动和管理功能"
    log_message "跳过创建单独启动脚本，功能已整合到maibot命令"
}

# 启动服务
start_services() {
    print_info "启动MaiBot生态系统服务..."
    
    # 检查是否所有组件都已安装
    local missing_components=()
    
    if [[ ! -d "$MAIBOT_DIR" ]] || [[ ! -f "$MAIBOT_DIR/main.py" ]]; then
        missing_components+=("MaiBot本体")
    fi
    
    if [[ ! -d "$ADAPTER_DIR" ]] || [[ ! -f "$ADAPTER_DIR/main.py" ]]; then
        missing_components+=("MaiBot-NapCat-Adapter")
    fi
    
    if [[ ! -d "$NAPCAT_DIR" ]] || [[ ! -f "$NAPCAT_DIR/libnapcat_launcher.so" ]]; then
        missing_components+=("NapcatQQ")
    fi
    
    if [[ ${#missing_components[@]} -gt 0 ]]; then
        print_error "以下组件未安装或不完整："
        for component in "${missing_components[@]}"; do
            print_error "  - $component"
        done
        print_error "请先完成完整安装后再启动服务"
        return 1
    fi
    
    # 检查服务管理脚本是否存在
    if [[ ! -f "$INSTALL_BASE_DIR/maibot-service.sh" ]]; then
        print_error "服务管理脚本不存在，请先运行配置模块连接"
        return 1
    fi
    
    # 使用服务管理脚本启动服务
    print_info "启动虚拟显示服务器..."
    "$INSTALL_BASE_DIR/maibot-service.sh" start xvfb
    
    if [[ $? -eq 0 ]]; then
        print_success "虚拟显示服务器启动成功"
    else
        print_warning "虚拟显示服务器启动可能有问题"
    fi
    
    print_info "启动NapcatQQ..."
    "$INSTALL_BASE_DIR/maibot-service.sh" start napcat
    
    if [[ $? -eq 0 ]]; then
        print_success "NapcatQQ启动成功"
        sleep 8  # 等待NapcatQQ完全启动
    else
        print_error "NapcatQQ启动失败"
        return 1
    fi
    
    print_info "启动MaiBot-NapCat-Adapter..."
    "$INSTALL_BASE_DIR/maibot-service.sh" start adapter
    
    if [[ $? -eq 0 ]]; then
        print_success "MaiBot-NapCat-Adapter启动成功"
        sleep 5  # 等待Adapter完全启动
    else
        print_error "MaiBot-NapCat-Adapter启动失败"
        return 1
    fi
    
    print_info "启动MaiBot本体..."
    "$INSTALL_BASE_DIR/maibot-service.sh" start maibot
    
    if [[ $? -eq 0 ]]; then
        print_success "MaiBot本体启动成功"
        sleep 3
    else
        print_error "MaiBot本体启动失败"
        return 1
    fi
    
    # 检查所有服务状态
    print_info "检查服务状态..."
    sleep 2
    "$INSTALL_BASE_DIR/maibot-service.sh" status
    
    print_success "MaiBot生态系统启动完成"
    print_info "使用以下命令管理服务:"
    print_info "  检查状态: $INSTALL_BASE_DIR/maibot-service.sh status"
    print_info "  启动服务: $INSTALL_BASE_DIR/maibot-service.sh start [service]"
    print_info "  停止服务: $INSTALL_BASE_DIR/maibot-service.sh stop [service]"
    print_info "  重启服务: $INSTALL_BASE_DIR/maibot-service.sh restart [service]"
    
    log_message "MaiBot生态系统服务启动完成"
    return 0
}

# =============================================================================
# 主要功能函数
# =============================================================================
full_install() {
    print_header "开始完整安装"
    
    print_info "即将安装以下组件:"
    print_info "• MaiBot本体"
    print_info "• MaiBot-NapCat-Adapter"
    print_info "• NapcatQQ"
    echo ""
    
    if ! confirm_action "确认进行完整安装?"; then
        print_info "安装已取消"
        return
    fi
    
    # 执行安装步骤
    local steps=("更新软件包列表" "安装系统依赖" "创建安装目录" "安装Python" "安装MaiBot本体" "安装MaiBot-NapCat-Adapter" "安装NapcatQQ" "配置模块连接" "启动服务")
    local total=${#steps[@]}
    
    for i in "${!steps[@]}"; do
        show_progress $((i+1)) $total "${steps[$i]}"
        sleep 1
        
        case $i in
            0)
                # 更新软件包列表
                $UPDATE_CMD || {
                    print_error "软件包列表更新失败"
                    return 1
                }
                ;;
            1)
                # 安装系统依赖
                install_dependencies || {
                    print_error "系统依赖安装失败"
                    return 1
                }
                ;;
            2)
                # 创建安装目录
                create_install_directories || {
                    print_error "创建安装目录失败"
                    return 1
                }
                ;;
            3)
                # 安装Python
                install_python || {
                    print_error "Python安装失败"
                    return 1
                }
                ;;
            4)
                # 安装MaiBot本体
                install_maibot || {
                    print_error "MaiBot本体安装失败"
                    return 1
                }
                ;;
            5)
                # 安装MaiBot-NapCat-Adapter
                install_adapter || {
                    print_error "MaiBot-NapCat-Adapter安装失败"
                    return 1
                }
                ;;
            6)
                # 安装NapcatQQ
                install_napcat || {
                    print_error "NapcatQQ安装失败"
                    return 1
                }
                ;;
            7)
                # 配置模块连接
                configure_modules || {
                    print_error "模块连接配置失败"
                    return 1
                }
                ;;
            8)
                # 启动服务
                start_services || {
                    print_error "服务启动失败"
                    return 1
                }
                ;;
        esac
    done
    
    print_success "完整安装完成!"
    print_info "所有组件已正确安装和配置。"
    
    log_message "完整安装完成"
}

custom_install() {
    print_header "自定义安装"
    print_info "请选择要安装的组件:"
    echo "1) MaiBot本体"
    echo "2) MaiBot-NapCat-Adapter"
    echo "3) NapcatQQ"
    echo "4) 全部组件"
    echo "0) 返回主菜单"
    
    local selection
    while true; do
        read -p "请输入选择 (用空格分隔多个选项, 如: 1 2 3): " selection
        
        case "$selection" in
            *0*)
                print_info "返回主菜单"
                return
                ;;
            *4*)
                perform_custom_install "maibot" "adapter" "napcat"
                break
                ;;
            *)
                local selected_components=()
                for choice in $selection; do
                    case "$choice" in
                        1) selected_components+=("maibot") ;;
                        2) selected_components+=("adapter") ;;
                        3) selected_components+=("napcat") ;;
                    esac
                done
                
                if [[ ${#selected_components[@]} -gt 0 ]]; then
                    perform_custom_install "${selected_components[@]}"
                    break
                else
                    print_error "无效的选择，请重新输入"
                fi
                ;;
        esac
    done
}

# 执行自定义安装的核心函数
perform_custom_install() {
    local components=("$@")
    local install_maibot=false
    local install_adapter=false
    local install_napcat=false
    
    # 解析组件列表
    for component in "${components[@]}"; do
        case "$component" in
            maibot) install_maibot=true ;;
            adapter) install_adapter=true ;;
            napcat) install_napcat=true ;;
        esac
    done
    
    print_header "开始自定义安装"
    print_info "安装组件: ${components[*]}"
    
    # 系统检查和准备
    print_info "执行系统检查..."
    if ! check_system; then
        print_error "系统检查失败"
        return 1
    fi
    
    # 更新软件包列表
    print_info "更新软件包列表..."
    if ! update_package_list; then
        print_error "软件包列表更新失败"
        return 1
    fi
    
    # 安装基础依赖
    print_info "安装基础依赖..."
    if ! install_dependencies; then
        print_error "基础依赖安装失败"
        return 1
    fi
    
    # 创建安装目录
    print_info "创建安装目录..."
    if ! create_install_directories; then
        print_error "创建安装目录失败"
        return 1
    fi
    
    # 安装Python
    print_info "检查Python环境..."
    if ! install_python; then
        print_error "Python安装失败"
        return 1
    fi
    
    local success_count=0
    local total_count=${#components[@]}
    
    # 按顺序安装选定的组件
    if [[ "$install_napcat" == "true" ]]; then
        print_info "安装NapcatQQ..."
        if install_napcat; then
            print_success "NapcatQQ安装成功"
            ((success_count++))
        else
            print_error "NapcatQQ安装失败"
        fi
    fi
    
    if [[ "$install_adapter" == "true" ]]; then
        print_info "安装MaiBot-NapCat-Adapter..."
        if install_adapter; then
            print_success "MaiBot-NapCat-Adapter安装成功"
            ((success_count++))
        else
            print_error "MaiBot-NapCat-Adapter安装失败"
        fi
    fi
    
    if [[ "$install_maibot" == "true" ]]; then
        print_info "安装MaiBot本体..."
        if install_maibot; then
            print_success "MaiBot本体安装成功"
            ((success_count++))
        else
            print_error "MaiBot本体安装失败"
        fi
    fi
    
    # 配置已安装的组件
    if [[ $success_count -gt 0 ]]; then
        print_info "配置已安装的组件..."
        if configure_modules; then
            print_success "组件配置完成"
        else
            print_warning "组件配置可能有问题"
        fi
    fi
    
    # 安装结果总结
    print_header "自定义安装完成"
    print_info "安装结果: $success_count/$total_count 个组件成功安装"
    
    if [[ $success_count -eq $total_count ]]; then
        print_success "所有选定组件安装成功!"
        print_info "安装目录: $INSTALL_BASE_DIR"
        print_info "配置文件目录:"
        
        if [[ "$install_maibot" == "true" ]]; then
            print_info "  MaiBot: $MAIBOT_DIR/config/"
        fi
        
        if [[ "$install_adapter" == "true" ]]; then
            print_info "  Adapter: $ADAPTER_DIR/config/"
        fi
        
        if [[ "$install_napcat" == "true" ]]; then
            print_info "  NapCat: $NAPCAT_DIR/config/"
        fi
        
        print_info "服务管理: $INSTALL_BASE_DIR/maibot-service.sh"
        
        # 询问是否启动服务
        if confirm_action "是否启动已安装的服务?"; then
            start_services
        fi
    else
        print_warning "部分组件安装失败，请检查错误信息"
        print_info "可以稍后重新运行安装脚本"
    fi
    
    log_message "自定义安装完成: $success_count/$total_count 个组件成功"
}

uninstall() {
    print_header "卸载程序"
    
    print_warning "即将删除以下内容:"
    print_info "• 安装目录: $INSTALL_BASE_DIR"
    print_info "• 所有配置文件"
    print_info "• Python虚拟环境"
    print_info "• 启动脚本"
    print_info "• 日志文件"
    echo ""
    
    if ! confirm_action "确认卸载程序? 这将删除所有相关文件"; then
        print_info "卸载已取消"
        return
    fi
    
    perform_uninstall
}

# 执行卸载操作的核心函数
perform_uninstall() {
    print_header "开始卸载MaiBot生态系统"
    
    # 停止所有运行中的服务
    print_info "停止所有服务..."
    
    # 停止MaiBot
    print_debug "停止MaiBot本体..."
    pkill -f "python3.*bot.py" 2>/dev/null && sleep 2
    
    # 停止Adapter
    print_debug "停止MaiBot-NapCat-Adapter..."
    pkill -f "maibot-napcat-adapter.*main.py" 2>/dev/null && sleep 2
    
    # 停止NapCat
    print_debug "停止NapcatQQ..."
    pkill -f "LD_PRELOAD.*libnapcat_launcher.so" 2>/dev/null && sleep 2
    pkill -f "qq --no-sandbox" 2>/dev/null && sleep 2
    
    # 停止虚拟显示服务器
    print_debug "停止虚拟显示服务器..."
    pkill -f "Xvfb :1" 2>/dev/null && sleep 2
    
    print_success "所有服务已停止"
    
    # 备份配置文件（可选）
    if [[ -d "$INSTALL_BASE_DIR" ]]; then
        local backup_dir="/tmp/maibot_backup_$(date +%Y%m%d_%H%M%S)"
        
        if confirm_action "是否备份配置文件到 $backup_dir ?"; then
            create_backup "$backup_dir"
        fi
    fi
    
    # 删除安装目录
    if [[ -d "$INSTALL_BASE_DIR" ]]; then
        print_info "删除安装目录: $INSTALL_BASE_DIR"
        
        # 确保目录存在且是我们的安装目录
        if [[ "$INSTALL_BASE_DIR" == *"/maibot"* ]] || [[ "$INSTALL_BASE_DIR" == *"/MaiBot"* ]]; then
            if rm -rf "$INSTALL_BASE_DIR"; then
                print_success "安装目录删除成功"
            else
                print_error "删除安装目录失败，请手动删除: $INSTALL_BASE_DIR"
            fi
        else
            print_warning "安全起见，请手动删除安装目录: $INSTALL_BASE_DIR"
        fi
    else
        print_info "安装目录不存在，跳过删除"
    fi
    
    # 删除系统服务文件（如果存在）
    local service_files=(
        "/etc/systemd/system/maibot.service"
        "/etc/systemd/system/maibot-adapter.service"
        "/etc/systemd/system/napcat.service"
    )
    
    print_info "检查并删除系统服务文件..."
    local deleted_services=false
    
    for service_file in "${service_files[@]}"; do
        if [[ -f "$service_file" ]]; then
            print_debug "删除服务文件: $service_file"
            if rm -f "$service_file"; then
                deleted_services=true
            else
                print_warning "删除服务文件失败: $service_file"
            fi
        fi
    done
    
    if [[ "$deleted_services" == "true" ]]; then
        print_info "重新加载systemd配置..."
        systemctl daemon-reload 2>/dev/null || true
    fi
    
    # 删除创建的用户（如果存在）
    local maibot_user="maibot"
    if id "$maibot_user" &>/dev/null; then
        print_info "删除用户: $maibot_user"
        if confirm_action "是否删除系统用户 $maibot_user ?"; then
            userdel -r "$maibot_user" 2>/dev/null || {
                print_warning "删除用户失败，可能需要手动清理"
            }
        fi
    fi
    
    # 清理环境变量
    local shell_configs=(
        "/etc/profile.d/maibot.sh"
        "$HOME/.bashrc_maibot"
        "$HOME/.zshrc_maibot"
    )
    
    print_info "清理环境变量配置..."
    for config_file in "${shell_configs[@]}"; do
        if [[ -f "$config_file" ]]; then
            print_debug "删除配置文件: $config_file"
            rm -f "$config_file" || print_warning "删除配置文件失败: $config_file"
        fi
    done
    
    # 清理临时文件
    print_info "清理临时文件..."
    local temp_dirs=(
        "/tmp/maibot_*"
        "/tmp/napcat_*"
        "/tmp/adapter_*"
    )
    
    for temp_pattern in "${temp_dirs[@]}"; do
        rm -rf $temp_pattern 2>/dev/null || true
    done
    
    # 清理日志记录
    if [[ -f "$LOG_FILE" ]]; then
        print_info "清理安装日志: $LOG_FILE"
        rm -f "$LOG_FILE" || print_warning "删除日志文件失败"
    fi
    
    print_success "卸载完成"
    print_info "MaiBot生态系统已完全移除"
    
    print_header "卸载完成"
    print_info "感谢您使用MaiBot生态系统!"
    
    log_message "MaiBot生态系统卸载完成"
}

# 创建配置备份
create_backup() {
    local backup_dir="$1"
    
    print_info "创建配置备份..."
    mkdir -p "$backup_dir" || {
        print_error "无法创建备份目录"
        return 1
    }
    
    # 备份配置文件
    local config_dirs=(
        "$MAIBOT_DIR/config"
        "$ADAPTER_DIR/config"
        "$NAPCAT_DIR/config"
    )
    
    for config_dir in "${config_dirs[@]}"; do
        if [[ -d "$config_dir" ]]; then
            local component_name=$(basename "$(dirname "$config_dir")")
            print_debug "备份 $component_name 配置..."
            cp -r "$config_dir" "$backup_dir/${component_name}_config" 2>/dev/null || true
        fi
    done
    
    # 备份启动脚本
    if [[ -d "$INSTALL_BASE_DIR" ]]; then
        print_debug "备份启动脚本..."
        cp "$INSTALL_BASE_DIR"/*.sh "$backup_dir/" 2>/dev/null || true
        cp "$INSTALL_BASE_DIR"/*.env "$backup_dir/" 2>/dev/null || true
    fi
    
    # 创建备份信息文件
    cat > "$backup_dir/backup_info.txt" << EOF
MaiBot生态系统配置备份
备份时间: $(date)
安装目录: $INSTALL_BASE_DIR
系统信息: $OS $OS_VERSION
备份内容:
- MaiBot配置文件
- Adapter配置文件
- NapCat配置文件
- 启动脚本
- 环境变量配置
EOF
    
    print_success "配置备份完成: $backup_dir"
}

show_system_info() {
    print_header "系统信息"
    echo -e "${BOLD}操作系统:${NC} $OS $OS_VERSION"
    echo -e "${BOLD}包管理器:${NC} $PACKAGE_MANAGER"
    echo -e "${BOLD}内核版本:${NC} $(uname -r)"
    echo -e "${BOLD}架构:${NC} $(uname -m)"
    echo -e "${BOLD}内存:${NC} $(free -h | awk '/^Mem:/{print $2}')"
    echo -e "${BOLD}磁盘使用:${NC} $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
    echo -e "${BOLD}运行时间:${NC} $(uptime -p 2>/dev/null || uptime)"
    echo ""
}

show_logs() {
    print_header "安装日志"
    if [[ -f "$LOG_FILE" ]]; then
        tail -20 "$LOG_FILE"
    else
        print_info "暂无日志文件"
    fi
    echo ""
    read -p "按任意键继续..." -n 1 -r
}

# =============================================================================
# 错误处理函数
# =============================================================================
cleanup() {
    print_info "清理临时文件..."
    # TODO: 实现清理逻辑
}

error_handler() {
    local line_num=$1
    print_error "脚本在第 $line_num 行发生错误"
    cleanup
    exit 1
}

# 设置错误处理
trap 'error_handler $LINENO' ERR
trap cleanup EXIT

# =============================================================================
# 主程序
# =============================================================================
main() {
    # 解析命令行参数
    parse_arguments "$@"
    
    # 初始化日志系统
    init_logging
    
    # 记录脚本启动
    log_message "脚本启动: $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # 系统检测
    detect_os
    check_root
    detect_package_manager
    check_system_requirements
    
    # 安装依赖
    install_dependencies
    
    # 显示欢迎界面
    show_welcome
    
    # 主循环
    while true; do
        # 显示菜单
        show_menu
        
        # 获取用户选择
        choice=$(read_choice)
        choice_result=$?
        
        # 检查读取是否成功
        if [[ $choice_result -ne 0 ]]; then
            print_error "读取用户输入失败"
            continue
        fi
        
        # 验证选择是否为空
        if [[ -z "$choice" ]]; then
            print_error "获取用户选择失败"
            continue
        fi
        
        case "$choice" in
            1)
                print_info "开始完整安装..."
                full_install
                ;;
            2)
                print_info "开始自定义安装..."
                custom_install
                ;;
            3)
                print_info "开始卸载..."
                uninstall
                ;;
            4)
                show_system_info
                ;;
            5)
                show_logs
                ;;
            6)
                if [[ "$DEBUG_MENU_MODE" == "true" ]]; then
                    print_info "执行调试选项：仅添加maibot命令脚本..."
                    only_add_maibot_command
                else
                    print_error "内部错误：选项6仅在调试模式下可用"
                fi
                ;;
            0)
                print_info "感谢使用 $SCRIPT_NAME!"
                log_message "脚本正常结束"
                exit 0
                ;;
            *)
                print_error "内部错误：未处理的选择 '$choice'"
                print_debug "这不应该发生，请报告此错误"
                ;;
        esac
        
        # 暂停以便用户查看结果
        echo ""
        read -p "按任意键继续..." -n 1 -r >/dev/null 2>&1
        echo ""
    done
}

# =============================================================================
# 脚本入口点
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi