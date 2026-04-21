#!/bin/bash
# 1. 设置默认端口
NGINX_PORT=${NGINX_PORT:-80}
echo "Setting Nginx port to: $NGINX_PORT"

# 2. 【关键】直接覆盖 Nginx 配置文件
# 使用 cat <<EOF 将新的配置写入文件，这样绝对不会错
cat > /etc/nginx/http.d/default.conf <<EOF
server {

	listen $NGINX_PORT default_server;
	listen [::]:$NGINX_PORT default_server;
  listen 8080;

	root /var/www/html;
	index index.html index.htm;

	server_name _;

	location / {
		try_files \$uri \$uri/ =404;
	}
}
EOF


echo "--------------------------"

# 4. 启动 Nginx
nginx &

# 确保必要的命令存在
command -v /usr/local/bin/sing >/dev/null 2>&1 || { echo "错误：未找到 sing。"; exit 1; }
command -v /usr/local/bin/cloudflared >/dev/null 2>&1 || { echo "错误：未找到 cloudflared。"; exit 1; }
command -v base64 >/dev/null 2>&1 || { echo "错误：未找到 base64 (是否缺少 coreutils？)。"; exit 1; }

# --- UUID 处理 ---
EFFECTIVE_UUID=""
if [ -n "$UUID" ]; then
    EFFECTIVE_UUID="$UUID"
    #echo "--------------------------------------------------"
    #echo "检测到用户提供的 UUID: $EFFECTIVE_UUID"
else
    EFFECTIVE_UUID=$(/usr/local/bin/sing generate uuid)
    echo "--------------------------------------------------"
    echo "未提供 UUID，已自动生成: $EFFECTIVE_UUID"
fi
#echo "--------------------------------------------------"

# --- sing-box 配置 ---
cat > seven.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [


  
	{
	  "type": "vmess",
	  "sniff": true,
	  "sniff_override_destination": true,
	  "tag": "proxy-in",
	  "listen": "::",
	  "listen_port": 2777,
	  "users": [
		{
		  "uuid": "${EFFECTIVE_UUID}",
		  "alterId": 0
		}
	  ],
	  "transport": {
		"type": "ws",
		"path": "/${EFFECTIVE_UUID}"
	  },
	"tls": {
		"enabled": false
	},
	"multiplex": {
		"enabled": true
	}
	
	}


  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy-out",
      "server": "pages.5i7.dpdns.org",
      "server_port": 443,
      "uuid": "792c9cd6-9ece-4ebc-ff02-86eaf8bf7e73",
      "tls": {
        "enabled": true
      },
      "transport": {
        "type": "ws"
      }
    },
	{
      "type": "direct",
      "tag": "direct"
    },
	{
	  "type": "vmess",
	  "tag": "relay-vps2",
	  "server": "31.57.241.63",
	  "server_port": 24851,
	  "uuid": "c7ace3f0-7094-4896-af76-f2e74e5341a6",
	  "tls": {
		"enabled": false
	  },
	  "network": "tcp"
	},

    {
      "type": "vless",
      "tag": "proxy-out1",
      "server": "s.i7.cloudns.org",
      "server_port": 80,
      "uuid": "05ec359e-d6d4-48c7-9738-5e83042de347",
      "tls": {
        "enabled": false
      },
      "network": "tcp",
      "transport": {
        "type": "ws"
      }
    }
  ],
  "route": {
    "rules": [

    {
      "rule_set": "geosite-cn",
      "outbound": "proxy-out"
    },
    {
      "rule_set": "geoip-cn",
      "outbound": "proxy-out"
    }
    ],
	"rule_set": [
  {
    "tag": "geoip-cn",
    "type": "remote",
    "format": "binary",
    "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
    "download_detour": "direct"
  },
  {
    "tag": "geosite-cn",
    "type": "remote",
    "format": "binary",
    "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
    "download_detour": "direct"
  },
  {
    "tag": "geosite-category-ads-all",
    "type": "remote",
    "format": "binary",
    "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
    "download_detour": "direct"
  }
],
"final": "direct"
  }
}
EOF
#echo "seven.json 已创建 (端口: 2777)。"

nohup /usr/local/bin/sing run -c seven.json > /dev/null 2>&1 &
sleep 2
#ps | grep "sing-box" | grep -v 'grep'
#echo "sing-box 已启动。"
#echo "--------------------------------------------------"
echo "ERROR:The response must not contain a body and must include the headers"
echo "--------------------------------------------------"
# --- Cloudflare Tunnel 处理 ---
TUNNEL_MODE=""
FINAL_DOMAIN=""
TUNNEL_CONNECTED=false

# 检查是否使用固定隧道
if [ -n "$TOKEN" ] && [ -n "$DOMAIN" ]; then
    TUNNEL_MODE="固定隧道 (Fixed Tunnel)"
    FINAL_DOMAIN="$DOMAIN"
    #echo "检测到 token 和 domain 环境变量，将使用【固定隧道模式】。"
    #echo "隧道域名将是: $FINAL_DOMAIN"
    #echo "Cloudflare Tunnel Token: [已隐藏]"
    #echo "正在启动固定的 Cloudflare 隧道..."
    nohup /usr/local/bin/cloudflared tunnel --no-autoupdate run --token "${TOKEN}" > ./seven.log 2>&1 &

    #echo "正在等待 Cloudflare 固定隧道连接... (最多 30 秒)"
    for attempt in $(seq 1 15); do
        sleep 2
        if grep -q -E "Registered tunnel connection|Connected to .*, an Argo Tunnel an edge" ./seven.log; then
            TUNNEL_CONNECTED=true
            break
        fi
        echo -n "." 
    done
    echo ""

else
    TUNNEL_MODE="临时隧道 (Temporary Tunnel)"
    echo "未提供 token 和/或 domain 环境变量，将使用【临时隧道模式】。"
    echo "正在启动临时的 Cloudflare 隧道..."
    nohup /usr/local/bin/cloudflared tunnel --url http://localhost:2777 --edge-ip-version auto --no-autoupdate --protocol http2 > ./seven.log 2>&1 &

    echo "正在等待 Cloudflare 临时隧道 URL... (最多 30 秒)"
    for attempt in $(seq 1 15); do
        sleep 2
        TEMP_TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare.com' ./seven.log | head -n 1)
        if [ -n "$TEMP_TUNNEL_URL" ]; then
            FINAL_DOMAIN=$(echo $TEMP_TUNNEL_URL | awk -F'//' '{print $2}')
            TUNNEL_CONNECTED=true
            break
        fi
        echo -n "."
    done
    echo ""
fi

# --- 输出结果 ---
if [ "$TUNNEL_CONNECTED" = "true" ]; then
 
    tail -f /etc/nginx/http.d/default.conf
else
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    cat ./seven.log
    exit 1
fi
