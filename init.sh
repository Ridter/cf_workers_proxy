#!/bin/bash

if [ $# -ne 2 ] && [ $# -ne 4 ]; then
    echo "[+] Usage: $0 <url> <port> [username] [password]"
    exit 1
fi

url=$1
port=$2


if [ $# -gt 2 ]; then
    username=$3
    password=$4
    authtype="password"
else
    username="user"
    password="pass"
    authtype="noauth"
fi

# 检查是否安装了curl
if ! command -v curl >/dev/null; then
    echo "[x] curl is required. Exiting."
    exit 1
fi

# 请求URL获取配置信息, 如果返回不包含 "protocol": "vless", 则认为配置不存在
echo "[*] Requesting configuration from $url"
response=$(curl --connect-timeout 3 -s "$url")
if [[ ! $response =~ "protocol\": \"vless\"" ]]; then
    echo "[x] Configuration not found. Exiting."
    exit 1
fi

# 检查配置文件是否存在
if [ ! -d "config" ]; then
    echo "[x] Config file missing. Exiting."
    exit 1
fi

# 检查是否安装了Docker
if ! command -v docker >/dev/null; then
    echo "[*] Docker is not installed. Do you want to install it? (yes/no)"
    read -r answer
    if [ "$answer" = "yes" ]; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
    else
        echo "[x] Docker is required. Exiting."
        exit 1
    fi
fi

# 检查是否安装了Docker Compose
if ! command -v docker-compose >/dev/null; then
    echo "[*] Docker Compose is not installed. Do you want to install it? (yes/no)"
    read -r answer
    if [ "$answer" = "yes" ]; then
        # 获取最新版本
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
        sudo curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "[x] Docker Compose is required. Exiting."
        exit 1
    fi
fi

# 重新生成xray配置文件进行替换
cat > config/config.json <<EOL
{
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ],
    "tag": "api"
  },
  "dns": null,
  "fakeDns": null,
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "sniffing": null,
      "streamSettings": null,
      "tag": "api"
    },
    {
      "listen": null,
      "port": $port,
      "protocol": "socks",
      "settings": {
        "accounts": [
          {
            "pass": "$password",
            "user": "$username"
          }
        ],
        "auth": "$authtype",
        "ip": "127.0.0.1",
        "udp": false
      },
      "sniffing": null,
      "streamSettings": null,
      "tag": "inbound-31445"
    }
  ],
  "log": {
    "error": "./error.log",
    "loglevel": "warning"
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    $response,
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    }
  },
  "reverse": null,
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "domain": [
          "regexp:.*"
        ],
        "outboundTag": "cloudflare",
        "type": "field"
      },
      {
        "ip": [
          "0.0.0.0/0",
          "::/0"
        ],
        "outboundTag": "cloudflare",
        "type": "field"
      },
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      }
    ]
  },
  "stats": {},
  "transport": null
}
EOL


# 生成Docker Compose文件
cat > docker-compose.yml <<EOL
version: '3'

services:
  cf_proxy:
    image: teddysun/xray:latest
    container_name: cf_proxy
    hostname: cf_proxy
    volumes:
      - ./config/config.json:/etc/xray/config.json
    tty: true
    restart: unless-stopped
    ports:
      - $port:$port
EOL


docker-compose down
docker-compose up -d