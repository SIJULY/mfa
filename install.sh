#!/bin/bash
set -e # 确保脚本在出错时立即停止

# --- 默认配置 ---
REPO_URL="https://github.com/SIJULY/sijuly-mfa.git"
IMAGE_NAME="sijuly-mfa"
CONTAINER_NAME="mfa-web-container"
CADDYFILE_PATH="/etc/caddy/Caddyfile"
CONTAINER_PORT=8080 # 这是您 Dockerfile 中 Nginx 监听的端口
# ------------------

# --- Caddy 重载函数 ---
reload_caddy() {
    echo "==> 正在重新加载 Caddy 服务..."
    # 尝试使用 systemctl 重载 (最常见的方式)
    if command -v systemctl >/dev/null && systemctl is-active --quiet caddy; then
        echo "通过 systemctl 重新加载 Caddy..."
        sudo systemctl reload caddy
    # 检查 caddy 命令是否存在
    elif command -v caddy >/dev/null; then
        echo "通过 'caddy reload' 命令重新加载..."
        sudo caddy reload --config "$CADDYFILE_PATH"
    # 如果两种方式都失败了
    else
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! 警告: 无法自动重新加载 Caddy。"
        echo "!! 脚本无法找到正在运行的 Caddy 服务或 'caddy' 命令。"
        echo "!! 请手动重新加载 Caddy 以使您的域名生效。"
        echo "!! 您可以尝试以下命令之一："
        echo "   sudo systemctl reload caddy"
        echo "   sudo service caddy reload"
        echo "   caddy reload --config $CADDYFILE_PATH"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    fi
}


# --- 卸载函数 ---
uninstall_mfa() {
    echo ""
    echo "--- 开始卸载 MFA 网页 ---"
    
    # 停止并删除 Docker 容器
    echo "==> 1. 正在停止并删除 Docker 容器: $CONTAINER_NAME..."
    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
        docker stop $CONTAINER_NAME
    fi
    if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
        docker rm $CONTAINER_NAME
    fi
    echo "容器已清理。"
    
    # 删除 Docker 镜像
    echo "==> 2. 正在删除 Docker 镜像: $IMAGE_NAME..."
    if docker image inspect $IMAGE_NAME > /dev/null 2>&1; then
        docker rmi $IMAGE_NAME
        echo "镜像已删除。"
    else
        echo "镜像不存在，跳过。"
    fi
    
    # 删除克隆的项目文件夹
    echo "==> 3. 正在删除项目文件夹 (位于脚本运行的当前目录)..."
    if [ -d "$IMAGE_NAME" ]; then
        rm -rf "$IMAGE_NAME"
        echo "项目文件夹已删除。"
    else
        echo "项目文件夹不存在，跳过。"
    fi
    
    # 从 Caddyfile 中移除配置（如果用户提供了域名）
    read -p "如果您安装时使用了域名，请输入该域名以便从Caddy中移除 (否则请直接回车): " DOMAIN_NAME
    if [ -n "$DOMAIN_NAME" ]; then
        echo "==> 4. 正在从 Caddyfile 中移除配置..."
        if [ -f "$CADDYFILE_PATH" ]; then
            sudo cp "$CADDYFILE_PATH" "$CADDYFILE_PATH.bak.$(date +%s)"
            START_LINE=$(grep -n -m 1 "$DOMAIN_NAME" "$CADDYFILE_PATH" | cut -d: -f1)
            if [ -n "$START_LINE" ]; then
                END_LINE=$(awk "NR >= $START_LINE && /^\s*}\s*$/ {print NR; exit}" "$CADDYFILE_PATH")
                if [ -n "$END_LINE" ]; then
                    echo "将从 Caddyfile 中删除第 $START_LINE 到 $END_LINE 行的配置..."
                    sudo sed -i "${START_LINE},${END_LINE}d" "$CADDYFILE_PATH"
                    echo "配置已移除。"
                    reload_caddy
                else
                    echo "!! 警告: 找到了域名 $DOMAIN_NAME，但无法自动移除配置块。请手动编辑 $CADDYFILE_PATH 文件。"
                fi
            else
                echo "在 Caddyfile 中未找到域名 $DOMAIN_NAME 的配置，跳过。"
            fi
        else
            echo "未找到 Caddyfile，跳过 Caddy 配置移除。"
        fi
    else
        echo "==> 4. 跳过 Caddy 配置移除。"
    fi

    echo ""
    echo "✅ 卸载完成！"
}

# --- 安装函数 ---
install_mfa() {
    echo ""
    echo "--- 请选择您的访问方式 ---"
    echo "1. 使用域名 (推荐, Caddy将自动配置HTTPS)"
    echo "2. 使用公网IP (HTTP, 无加密)"
    read -p "请输入选项 [1-2]: " access_choice

    local USE_DOMAIN=false
    if [ "$access_choice" == "1" ]; then
        USE_DOMAIN=true
    elif [ "$access_choice" != "2" ]; then
        echo "!! 错误: 无效选项。"
        exit 1
    fi

    # --- 1. 用户输入 ---
    if [ "$USE_DOMAIN" = true ]; then
        read -p "请输入您的域名 (例如 mfa.sijuly.nyc.mn): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            echo "!! 错误: 域名不能为空。"
            exit 1
        fi
    fi

    DEFAULT_HOST_PORT="8081"
    read -p "请输入要映射到主机的端口 (默认: $DEFAULT_HOST_PORT): " HOST_PORT
    HOST_PORT=${HOST_PORT:-$DEFAULT_HOST_PORT}

    echo ""
    echo "--- 配置确认 ---"
    if [ "$USE_DOMAIN" = true ]; then
        echo "访问方式: 域名 (HTTPS)"
        echo "域名: $DOMAIN_NAME"
        echo "Caddyfile: $CADDYFILE_PATH"
    else
        echo "访问方式: 公网IP (HTTP)"
    fi
    echo "本地端口: $HOST_PORT"
    echo "容器名称: $CONTAINER_NAME"
    echo "------------------"
    read -p "确认无误？(y/n): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
    echo ""

    # --- 2. Git & Docker 操作 ---
    echo "==> 1. 正在从 GitHub 克隆项目..."
    if [ -d "$IMAGE_NAME" ]; then rm -rf "$IMAGE_NAME"; fi
    git clone $REPO_URL $IMAGE_NAME
    cd $IMAGE_NAME

    echo "==> 2. 正在准备 Docker..."
    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then docker stop $CONTAINER_NAME; fi
    if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then docker rm $CONTAINER_NAME; fi
    echo "==> 3. 正在构建 Docker 镜像..."
    docker build -t $IMAGE_NAME .

    echo "==> 4. 正在启动 Docker 容器..."
    if [ "$USE_DOMAIN" = true ]; then
        # 绑定到本地，仅供 Caddy 访问
        docker run -d -p 127.0.0.1:${HOST_PORT}:${CONTAINER_PORT} --name $CONTAINER_NAME --restart unless-stopped $IMAGE_NAME
        echo "容器已启动，正在监听 127.0.0.1:${HOST_PORT}"
    else
        # 绑定到公网
        docker run -d -p ${HOST_PORT}:${CONTAINER_PORT} --name $CONTAINER_NAME --restart unless-stopped $IMAGE_NAME
        echo "容器已启动，正在监听所有网络接口的 ${HOST_PORT} 端口"
    fi

    # --- 4. Caddy 配置 或 显示IP访问信息 ---
    if [ "$USE_DOMAIN" = true ]; then
        echo "==> 5. 正在配置 Caddy..."
        CADDY_SNIPPET="\n$DOMAIN_NAME {\n    reverse_proxy 127.0.0.1:$HOST_PORT\n}\n"
        sudo mkdir -p "$(dirname "$CADDYFILE_PATH")"
        if [ ! -f "$CADDYFILE_PATH" ]; then
            echo "警告: 未找到 Caddyfile，将创建新文件。"
            sudo touch "$CADDYFILE_PATH"
        fi
        if grep -q " $DOMAIN_NAME " "$CADDYFILE_PATH"; then
            echo "Caddyfile 中已存在 $DOMAIN_NAME 的配置，跳过追加。"
        else
            echo "正在将 $DOMAIN_NAME 的配置追加到 $CADDYFILE_PATH ..."
            echo -e "$CADDY_SNIPPET" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
            echo "配置已追加。"
        fi
        
        reload_caddy

        echo ""
        echo "============================================="
        echo " ✅ 部署完成！"
        echo ""
        echo " 您现在应该可以通过 https://$DOMAIN_NAME 访问您的 MFA 网页了。"
        echo "============================================="
    else
        PUBLIC_IP=$(curl -s ifconfig.me || curl -s ip.sb || echo "YOUR_PUBLIC_IP")
        echo ""
        echo "============================================="
        echo " ✅ 部署完成！"
        echo ""
        echo " 您现在可以通过以下地址访问您的 MFA 网页："
        echo " http://$PUBLIC_IP:$HOST_PORT"
        echo ""
        echo " (请确保您服务器的防火墙已放行 ${HOST_PORT} 端口)"
        echo "============================================="
    fi
}

# --- 主菜单 ---
main_menu() {
    echo "欢迎使用 sijuly-mfa 一键脚本"
    echo "--------------------------------"
    echo "请选择操作:"
    echo "1. 安装或更新 MFA 网页"
    echo "2. 卸载 MFA 网页"
    echo "3. 退出"
    echo "--------------------------------"
    read -p "请输入选项 [1-3]: " choice

    case $choice in
        1) install_mfa ;;
        2) uninstall_mfa ;;
        3) echo "退出脚本。"; exit 0 ;;
        *) echo "!! 错误: 无效选项。"; exit 1 ;;
    esac
}

# --- 脚本开始 ---
# 检查依赖
command -v git >/dev/null 2>&1 || { echo "!! 错误: git 未安装。请先安装 git。"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "!! 错误: docker 未安装。请先安装 docker。"; exit 1; }
# 不再检查 caddy 命令，因为我们会在重载函数中处理
echo "依赖检查通过。"

main_menu

