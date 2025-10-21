#!/bin/bash
set -e # 确保脚本在出错时立即停止

# --- 默认配置 ---
# 您的 GitHub 仓库地址
REPO_URL="https://github.com/SIJULY/sijuly-mfa.git"
# Docker 镜像和容器的名称 (可以自定义)
IMAGE_NAME="sijuly-mfa"
CONTAINER_NAME="mfa-web-container"
# Caddyfile 的默认路径
CADDYFILE_PATH="/etc/caddy/Caddyfile"
# 内部端口 (Nginx 默认监听 8080)
CONTAINER_PORT=8080
# ------------------

# 检查依赖
command -v git >/dev/null 2>&1 || { echo "!! 错误: git 未安装。请先安装 git。"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "!! 错误: docker 未安装。请先安装 docker。"; exit 1; }
command -v caddy >/dev/null 2>&1 || { echo "!! 警告: 未找到 caddy 命令。脚本将假定 caddy 已作为 systemd 服务运行。"; }
echo "依赖检查通过。"
echo ""

# --- 1. 用户输入 ---
read -p "请输入您的域名 (例如 mfa.sijuly.nyc.mn): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    echo "!! 错误: 域名不能为空。"
    exit 1
fi

# 推荐一个高端口以避免冲突
DEFAULT_HOST_PORT="8081"
read -p "请输入要映射到主机的端口 (默认: $DEFAULT_HOST_PORT): " HOST_PORT
HOST_PORT=${HOST_PORT:-$DEFAULT_HOST_PORT}

echo ""
echo "--- 配置确认 ---"
echo "域名: $DOMAIN_NAME"
echo "本地端口: $HOST_PORT (Caddy 将代理到此端口)"
echo "容器名称: $CONTAINER_NAME"
echo "Caddyfile: $CADDYFILE_PATH"
echo "------------------"
read -p "确认无误？(y/n): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
echo ""

# --- 2. Git 操作 ---
echo "==> 1. 正在从 GitHub 克隆项目..."
# 如果目录已存在，先删除
if [ -d "$IMAGE_NAME" ]; then
    echo "发现旧目录，正在删除..."
    rm -rf "$IMAGE_NAME"
fi
git clone $REPO_URL $IMAGE_NAME
cd $IMAGE_NAME

# --- 3. Docker 操作 ---
echo "==> 2. 正在停止并删除旧容器 (如果存在)..."
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

echo "==> 3. 正在构建 Docker 镜像..."
docker build -t $IMAGE_NAME .

echo "==> 4. 正在启动 Docker 容器..."
# 我们将端口绑定到 127.0.0.1 (本地主机)，这样它就不会对外暴露，只有 Caddy 可以访问
docker run -d \
    -p 127.0.0.1:${HOST_PORT}:${CONTAINER_PORT} \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    $IMAGE_NAME

echo "容器已启动，正在监听 127.0.0.1:${HOST_PORT}"

# --- 4. Caddy 配置 (核心) ---
echo "==> 5. 正在配置 Caddy..."

# 准备要追加的 Caddy 配置块
CADDY_SNIPPET="
$DOMAIN_NAME {
    reverse_proxy 127.0.0.1:$HOST_PORT
}
"

# 检查 Caddyfile 是否存在
if [ ! -f "$CADDYFILE_PATH" ]; then
    echo "警告: 未找到 Caddyfile 于 $CADDYFILE_PATH。将尝试创建新文件。"
    # 尝试创建 (如果权限不足，tee 命令会处理)
    touch "$CADDYFILE_PATH"
fi

# 检查域名是否已存在于 Caddyfile 中
if grep -q " $DOMAIN_NAME " "$CADDYFILE_PATH"; then
    echo "Caddyfile 中已存在 $DOMAIN_NAME 的配置，跳过追加。"
else
    echo "正在将 $DOMAIN_NAME 的配置追加到 $CADDYFILE_PATH ..."
    # 使用 tee -a 和 sudo 来追加内容，以处理权限问题
    # 这要求运行此脚本的用户具有 sudo 权限
    echo "$CADDY_SNIPPET" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
    echo "配置已追加。"
fi

# --- 5. 重载 Caddy ---
echo "==> 6. 正在重新加载 Caddy 服务..."
# 尝试使用 systemctl 重载 (最常见的方式)
if [ -f "/etc/systemd/system/caddy.service" ]; then
    sudo systemctl reload caddy
else
    # 否则尝试 Caddy API (如果 Caddy 是手动运行的)
    echo "未找到 Caddy systemd 服务，尝试使用 'caddy reload'..."
    sudo caddy reload --config $CADDYFILE_PATH
fi

echo ""
echo "============================================="
echo " 部署完成！"
echo ""
echo " 您现在应该可以通过 https://$DOMAIN_NAME 访问您的 MFA 网页了。"
echo " (Caddy 会自动为您处理 HTTPS)"
echo "============================================="
