# 基础镜像
FROM alpine:3.18.12 AS base

# 设置环境变量

# 安装依赖 + 安装 Nginx
RUN apk add --no-cache bash curl wget tzdata ca-certificates nginx && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    # 创建 Nginx 运行所需的 PID 目录
    mkdir -p /run/nginx && \
    # 创建一个默认的主页
    mkdir -p /var/www/html && \
    # --- 修改重点：添加 style 样式实现居中 ---
    # text-align: center (水平居中)
    # margin-top: 20% (距离顶部 20%，视觉上垂直居中)
    # font-family: sans-serif (使用无衬线字体，更像浏览器默认错误页)
    echo "<h1 style='text-align: center; margin-top: 20vh; font-family: sans-serif;'>500 Internal Server Error</h1>" > /var/www/html/index.html

# 下载并安装 sing-box
RUN wget -O /usr/local/bin/sing "https://aria.i7.cloudns.org/sing" && \
    chmod +x /usr/local/bin/sing


# 下载并安装 cloudflared
RUN wget -q https://aria.i7.cloudns.org/cloudflared\
    -O /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared

# 创建应用目录
WORKDIR /app

# 复制脚本
COPY seven.sh .

# 设置执行权限
RUN chmod +x seven.sh

# 启动命令
ENTRYPOINT ["/bin/bash", "./seven.sh"]
