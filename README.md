# sijuly-mfa - 纯前端 MFA/TOTP 动态验证码生成器

这是一个轻量级、纯前端实现的 MFA (多因素认证) 动态验证码生成器。它允许您在自己的服务器上快速部署一个网页，用于生成基于时间的一次性密码 (TOTP)，而无需依赖任何第三方应用。

项目完全开源，您可以将其部署在任何有 Docker 环境的服务器上。

*(建议您将项目截图命名为 `screenshot.png` 并上传到仓库根目录，以使此图片生效)*

## ✨ 功能特性

- **纯前端实现**：所有 TOTP 计算都在用户的浏览器中完成，服务器零负担，保障秘钥安全。
- **Docker 化部署**：通过 Docker 镜像封装，实现跨平台、一键式快速部署。
- **URL 秘钥注入**：支持通过 URL 参数 (`?key=...`) 或哈希 (`#...`) 动态传入秘钥，方便将特定秘钥的链接保存为书签。
- **一键安装脚本**：提供 `install.sh` 脚本，可在支持 Docker 和 Caddy 的服务器上一键完成部署、配置反向代理及 HTTPS。
- **多种访问方式**：安装脚本支持**域名 (自动HTTPS)** 和 **公网IP (HTTP)** 两种部署模式。
- **轻松卸载**：一键脚本同样提供完整的卸载功能，自动清理容器、镜像及相关配置。

## 🚀 快速开始：一键部署教程

本教程适用于一台全新的、已安装好 `git` 和 `docker` 的 VPS (推荐 Debian/Ubuntu 系统)。

### 必选：前置依赖安装

在运行一键脚本之前，请确保您的服务器已安装 `git` 和 `docker`。

### 更新软件包列表
```bash
sudo apt update
```
### 安装 git
```bash
sudo apt install -y git
```
### 安装 docker
### (如果已安装请跳过)
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### 🌐 可选：安装 Caddy (如果需要使用域名)
如果您希望通过域名并自动启用 HTTPS 访问您的 MFA 网页（这是推荐的方式），您需要安装 Caddy Web 服务器。
如果您选择稍后使用 IP 地址访问，则可以跳过此步骤。
### 1. 安装 Caddy 所需的依赖
```bash
sudo apt update && sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
```
### 2. 导入 Caddy 的 GPG 密钥以验证软件包
```bash
curl -1sLf '[https://dl.cloudsmith.io/public/caddy/stable/gpg.key](https://dl.cloudsmith.io/public/caddy/stable/gpg.key)' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
```
### 3. 添加 Caddy 的官方软件源
```bash
curl -1sLf '[https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt](https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt)' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
```
### 4. 更新软件包列表并安装 Caddy
```bash
sudo apt update && sudo apt install caddy
```


## ▶️ 运行一键脚本
现在，您可以运行一键脚本来完成 MFA 网页的部署了。

```bash
wget -O install.sh [https://raw.githubusercontent.com/SIJULY/sijuly-mfa/main/install.sh](https://raw.githubusercontent.com/SIJULY/sijuly-mfa/main/install.sh) && chmod +x install.sh && sudo bash install.sh
```
- **脚本将引导您完成以下步骤：**

- **选择 安装 或 卸载。**

- **选择使用 域名 还是 IP 地址 进行访问。**

- **输入您的域名或确认 IP。**

- **输入一个映射到主机的端口（例如 8081）。**

- **脚本将自动完成所有后续操作！**

🔑 如何访问
- **如果使用域名：脚本执行完毕后，直接访问 https://你的域名 即可。**

- **如果使用 IP：脚本执行完毕后，直接访问 http://你的服务器IP:你设置的端口 即可。**


📄 许可证
本项目采用 MIT License 开源。
