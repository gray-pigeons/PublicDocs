#!/bin/bash
# Docker 安装脚本 for Debian 12 (bookworm)，适合中国宝宝体质
# 最终版：解决GPG密钥+仓库404+包固定冲突

set -e  # 出错立即退出

# Step 1: 安装必要依赖
echo -e "\n📦 Step 1: 安装必要依赖..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# Step 2: 添加清华源GPG密钥（解决连接重置）
echo -e "\n🔐 Step 2: 添加 Docker GPG 公钥（清华源）..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Step 3: 添加Debian专用清华Docker源
echo -e "\n🧩 Step 3: 添加清华 Docker 镜像源（Debian专用）..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian \
$(lsb_release -cs) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 4: 解除docker-ce-cli包固定（核心修复）
echo -e "\n🔓 Step 4: 解除 docker-ce-cli 包固定..."
sudo apt-mark unhold docker-ce-cli 2>/dev/null || echo "✅ docker-ce-cli 未被固定，无需解除"

# Step 5: 更新缓存+安装Docker（带允许修改固定包参数）
echo -e "\n🔄 Step 5: 更新 APT 缓存并安装 Docker..."
sudo apt update
sudo apt install -y --allow-change-held-packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Step 6: 配置国内镜像源
echo -e "\n📑 Step 6: 添加国内镜像源并加载配置..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://docker.1panel.live"
  ]
}
EOF

# Step 7: 重启Docker+验证
echo -e "\n🔧 Step 7: 重启Docker服务并验证..."
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo docker info | grep "Registry Mirrors"

# Step 8: 测试Docker
echo -e "\n✅ 安装完成，运行 hello-world 测试..."
sudo docker run --rm hello-world

echo -e "\n🎉 Docker 安装成功！"
echo "👉 如需无sudo使用docker：sudo usermod -aG docker $USER && newgrp docker"