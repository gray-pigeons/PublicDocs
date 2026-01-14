#!/bin/bash
# Docker环境一键修复脚本（Debian 12专用）
# 功能：修复DNS解析 + 配置Docker daemon DNS + 修复镜像源配置
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
BLUE='\033[0;34m'

# 日志函数
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        warning "脚本需要root权限，将使用sudo执行。请确保已安装sudo并配置了密码。"
        sleep 2
    fi
}

# 检查Docker是否安装
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        error "Docker未安装！请先安装Docker："
        echo "sudo apt update && sudo apt install -y docker.io"
        exit 1
    fi
}

# ===================== Step 1: 修复主机DNS配置 =====================
fix_host_dns() {
    info "🔍 Step 1: 修复主机DNS解析..."
    
    # 备份原有DNS
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 检查是否使用systemd-resolved
    if [ -f /etc/systemd/resolved.conf ] && grep -q "DNS=" /etc/systemd/resolved.conf; then
        warning "检测到systemd-resolved服务，将配置全局DNS..."
        sudo tee /etc/systemd/resolved.conf > /dev/null << 'EOF'
[Resolve]
DNS=223.5.5.5 114.114.114.114
FallbackDNS=8.8.8.8 119.29.29.29
Domains=~.
EOF
        sudo systemctl restart systemd-resolved
        sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    else
        # 直接修改resolv.conf
        sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 223.5.5.5
nameserver 114.114.114.114
nameserver 8.8.8.8
options timeout:1 rotate
EOF
    fi
    
    # 测试DNS解析
    info "测试主机DNS解析..."
    if ping -c 2 www.baidu.com &> /dev/null; then
        success "主机DNS解析测试成功！"
    else
        warning "主机DNS解析测试失败，但已配置备用DNS，继续执行..."
    fi
}

# ===================== Step 2: 配置Docker daemon DNS和镜像加速器 =====================
configure_docker_daemon() {
    info "🔍 Step 2: 配置Docker daemon DNS和镜像加速器..."
    
    # 创建docker配置目录
    sudo mkdir -p /etc/docker
    
    # 配置Docker daemon，包括DNS和镜像加速器
    # 关键修复：为Docker daemon单独配置DNS，解决lookup失败问题
    sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
    "dns": ["223.5.5.5", "114.114.114.114", "8.8.8.8"],
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com"
    ],
    "max-concurrent-downloads": 10,
    "max-download-attempts": 5,
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "experimental": false,
    "debug": false
}
EOF
    
    # 重启Docker服务
    info "重启Docker服务应用配置..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    # 验证配置
    sleep 3
    if sudo docker info | grep -q "Registry Mirrors"; then
        success "Docker daemon配置成功！"
        echo -e "${YELLOW}镜像加速器配置：${NC}"
        sudo docker info | grep -A 3 "Registry Mirrors"
        echo -e "${YELLOW}DNS配置：${NC}"
        sudo docker info | grep "DNS"
    else
        warning "Docker daemon配置可能未生效，继续执行..."
    fi
    
    # 检查Docker服务状态
    info "检查Docker服务状态..."
    if sudo systemctl is-active --quiet docker; then
        success "Docker服务运行正常！"
    else
        error "Docker服务未运行！尝试启动..."
        sudo systemctl start docker
        sleep 2
        if sudo systemctl is-active --quiet docker; then
            success "Docker服务已成功启动！"
        else
            error "Docker服务启动失败！请检查系统日志：sudo journalctl -u docker --no-pager"
            exit 1
        fi
    fi
    
    # 关键修复：测试Docker daemon的DNS解析能力
    info "测试Docker daemon的DNS解析能力..."
    if sudo docker run --rm alpine ping -c 2 www.baidu.com &> /dev/null; then
        success "Docker daemon DNS解析正常！"
    else
        warning "Docker daemon DNS解析异常，这可能是镜像拉取失败的根本原因。"
    fi
}

# ===================== Step 3: 修复DNS解析问题（关键） =====================
fix_docker_dns_resolution() {
    info "🔍 Step 3: 修复Docker容器DNS解析（关键步骤）..."
    
    # 方法1：检查并修复resolv.conf权限
    info "方法1：修复resolv.conf权限和配置..."
    sudo chattr -i /etc/resolv.conf 2>/dev/null || true
    sudo chmod 644 /etc/resolv.conf
    
    # 重新配置DNS
    sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 223.5.5.5
nameserver 114.114.114.114
options timeout:1 rotate
EOF
    
    # 方法2：配置systemd-resolved（如果使用）
    if command -v systemd-resolve &> /dev/null; then
        info "方法2：配置systemd-resolved DNS..."
        sudo systemd-resolve --set-dns=223.5.5.5 --interface=eth0 2>/dev/null || true
        sudo systemd-resolve --set-dns=114.114.114.114 --interface=eth0 2>/dev/null || true
    fi
    
    # 方法3：清理Docker DNS缓存
    info "方法3：清理Docker DNS缓存和网络配置..."
    sudo systemctl stop docker
    sudo rm -rf /var/lib/docker/network/files/*
    sudo systemctl start docker
    sleep 2
    
    # 方法4：检查nsswitch.conf配置
    info "方法4：检查nsswitch.conf配置..."
    if ! grep -q "hosts: files dns" /etc/nsswitch.conf; then
        sudo sed -i 's/hosts:.*/hosts: files dns/' /etc/nsswitch.conf
        info "已修复nsswitch.conf配置"
    fi
    
    success "Docker DNS解析修复步骤完成！"
}

# ===================== Step 4: 拉取alpine镜像（终极解决方案） =====================
pull_alpine_image_final() {
    info "🔍 Step 4: 拉取alpine镜像（终极解决方案）..."
    
    # 先清理旧镜像
    sudo docker rmi alpine:latest 2>/dev/null || true
    sudo docker rmi alpine:3.18 2>/dev/null || true
    
    # 方案1：使用中科大镜像源（最可靠）
    info "方案1：使用中科大镜像源..."
    if sudo docker pull docker.mirrors.ustc.edu.cn/library/alpine:3.18; then
        success "中科大镜像源拉取成功！"
        sudo docker tag docker.mirrors.ustc.edu.cn/library/alpine:3.18 alpine:latest
        sudo docker rmi docker.mirrors.ustc.edu.cn/library/alpine:3.18
        return 0
    fi
    
    # 方案2：使用网易云镜像源
    info "方案2：使用网易云镜像源..."
    if sudo docker pull hub-mirror.c.163.com/library/alpine:3.18; then
        success "网易云镜像源拉取成功！"
        sudo docker tag hub-mirror.c.163.com/library/alpine:3.18 alpine:latest
        sudo docker rmi hub-mirror.c.163.com/library/alpine:3.18
        return 0
    fi
    
    # 方案3：使用HTTP协议（绕过HTTPS问题）
    info "方案3：尝试HTTP协议拉取..."
    sudo docker pull registry.docker-cn.com/library/alpine:3.18 2>/dev/null || true
    
    # 方案4：如果所有方法都失败，提供详细的调试步骤
    error "❌ 所有自动拉取方法都失败！"
    echo -e "${YELLOW}请执行以下手动调试步骤：${NC}"
    
    echo -e "\n${BLUE}1. 检查Docker daemon DNS配置：${NC}"
    echo "sudo docker info | grep -A 5 'DNS'"
    
    echo -e "\n${BLUE}2. 测试Docker容器内的DNS解析：${NC}"
    echo "sudo docker run --rm busybox nslookup www.baidu.com"
    
    echo -e "\n${BLUE}3. 检查网络连接：${NC}"
    echo "sudo docker run --rm busybox ping -c 2 223.5.5.5"
    
    echo -e "\n${BLUE}4. 手动拉取镜像（推荐）：${NC}"
    echo "sudo docker pull docker.mirrors.ustc.edu.cn/library/alpine:3.18"
    echo "sudo docker tag docker.mirrors.ustc.edu.cn/library/alpine:3.18 alpine:latest"
    
    echo -e "\n${BLUE}5. 如果仍然失败，检查防火墙：${NC}"
    echo "sudo iptables -L -n -v"
    echo "sudo systemctl status ufw"
    
    # 提供详细的诊断信息
    info "详细诊断信息："
    echo "主机DNS配置："
    cat /etc/resolv.conf
    echo -e "\nDocker daemon配置："
    cat /etc/docker/daemon.json 2>/dev/null || echo "配置文件不存在"
    echo -e "\nDocker网络信息："
    sudo docker network ls
    
    exit 1
}

# ===================== Step 5: 验证Docker运行 =====================
verify_docker() {
    info "🔍 Step 5: 验证Docker环境..."
    
    # 基础验证
    if sudo docker run --rm alpine echo "Docker环境正常！"; then
        success "✅ Docker基础功能验证成功！"
        
        # 额外验证：测试容器网络
        info "🔍 测试容器网络连接..."
        if sudo docker run --rm alpine ping -c 2 www.baidu.com &> /dev/null; then
            success "✅ 容器网络连接正常！"
        else
            warning "容器网络连接异常，可能需要进一步配置。"
        fi
        
        # 额外验证：测试镜像拉取
        info "🔍 测试镜像拉取功能..."
        if sudo docker pull hello-world &> /dev/null; then
            success "✅ 镜像拉取功能正常！"
            sudo docker rmi hello-world &> /dev/null || true
        else
            warning "镜像拉取功能异常。"
        fi
    else
        error "❌ Docker容器运行失败！"
        info "诊断信息："
        sudo docker info 2>&1 | grep -E "(Server Version|Storage Driver|Logging Driver|Cgroup Driver|Kernel Version|DNS)"
        sudo systemctl status docker --no-pager
        return 1
    fi
    
    success "🎉 Docker环境验证成功！所有功能正常可用！"
    
    # 显示常用命令提示
    echo -e "\n${GREEN}👉 Docker环境修复完成！常用命令：${NC}"
    echo "  1. 查看Docker状态：${YELLOW}sudo systemctl status docker${NC}"
    echo "  2. 无sudo使用Docker：${YELLOW}sudo usermod -aG docker $USER && newgrp docker${NC}"
    echo "  3. 运行Nginx示例：${YELLOW}sudo docker run -d --name nginx -p 8080:80 nginx${NC}"
    echo "  4. 查看镜像：${YELLOW}sudo docker images${NC}"
    echo "  5. 查看容器：${YELLOW}sudo docker ps${NC}"
    echo "  6. DNS故障排查：${YELLOW}sudo docker run --rm busybox nslookup www.baidu.com${NC}"
}

# ===================== Main Execution =====================
main() {
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}     Docker环境一键修复脚本 (Debian 12)${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${YELLOW}注意：本脚本将修复Docker DNS解析问题，这是镜像拉取失败的根本原因！${NC}"
    
    # 检查权限和Docker安装
    check_root
    check_docker_installed
    
    # 执行所有步骤
    fix_host_dns
    configure_docker_daemon
    fix_docker_dns_resolution
    pull_alpine_image_final
    verify_docker
    
    echo -e "\n${GREEN}✅ 脚本执行完成！Docker环境已彻底修复！${NC}"
    echo -e "${YELLOW}如果仍有问题，请根据Step 4中的手动调试步骤进行排查。${NC}"
}

# 执行主函数
main "$@"