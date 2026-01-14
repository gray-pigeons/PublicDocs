#!/bin/bash
# Docker 安装脚本 for Ubuntu 22.04, 适合中国宝宝体质

set -e  # 出错立即退出

echo "📦 Step 1: 安装必要依赖..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

echo "🔐 Step 2: 添加 Docker GPG 公钥..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "🧩 Step 3: 添加清华 Docker 镜像源..."
# $(lsb_release -cs) 会自动获取发行代号，例如 jammy、focal 等
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu \
$(lsb_release -cs) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🔄 Step 4: 更新 APT 缓存并安装 Docker..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

echo "📑 Step 5: 添加国内镜像源并加载配置"
if [[ ! -d /etc/docker ]]; then
  mkdir /etc/docker;
fi
echo '
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://noohub.ru",
    "https://huecker.io",
    "https://dockerhub.timeweb.cloud",
    "https://docker.1panel.live",
    "http://mirrors.ustc.edu.cn/",
    "http://mirror.azure.cn/",
    "https://hub.rat.dev/",
    "https://docker.ckyl.me/",
    "https://docker.chenby.cn",
    "https://docker.hpcloud.cloud",
    "https://docker.m.daocloud.io"
  ]
}' > /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo docker info

echo "✅ 安装完成，运行 hello-world 测试 Docker..."
sudo docker run hello-world

echo "🎉 Docker 安装成功！你现在可以使用 docker 命令啦~"

# 可选：将当前用户加入 docker 组（重启后生效）
echo "👉 如需无 sudo 使用 docker，可执行：sudo usermod -aG docker $USER && newgrp docker"
