#!/bin/bash
# 完全卸载 Docker 的脚本（Debian 12/bookworm专用）
# 新增：自动解除Docker相关包的固定状态，避免重装冲突

set -e  # 出错立即退出

echo "🛑 正在停止 Docker 相关服务..."
sudo systemctl stop docker || true
sudo systemctl stop docker.socket || true
sudo systemctl stop containerd || true

echo "🔓 正在解除所有Docker相关包的固定状态..."
# 解除docker-ce-cli/docker-ce等包的hold状态，无则跳过
sudo apt-mark unhold docker-ce-cli 2>/dev/null || echo "✅ docker-ce-cli 未被固定，无需解除"
sudo apt-mark unhold docker-ce 2>/dev/null || echo "✅ docker-ce 未被固定，无需解除"
sudo apt-mark unhold containerd.io 2>/dev/null || echo "✅ containerd.io 未被固定，无需解除"

echo "❌ 正在卸载 Docker 相关软件包..."
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
sudo apt autoremove -y --purge

echo "🧹 正在删除 Docker 核心数据目录..."
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd

echo "🗑️ 正在删除 Docker 配置文件/密钥/仓库源..."
sudo rm -rf /etc/docker
sudo rm -rf /etc/systemd/system/docker.service.d
sudo rm -f  /etc/apt/sources.list.d/docker.list
sudo rm -f  /etc/apt/keyrings/docker.gpg
sudo rm -f  /etc/apt/keyrings/docker.asc
sudo rm -f  /etc/apt/trusted.gpg.d/docker.gpg

echo "🔄 更新 apt 缓存并清理..."
sudo apt update
sudo apt clean

echo "✅ Docker 已彻底卸载（含解除包固定），可重新安装。"