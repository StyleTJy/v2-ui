#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

curl -LOs https://raw.githubusercontent.com/StyleTJy/v2-ui/master/install.sh
if [[ $? -ne 0 ]];then
    echo -e "${red}下载install脚本失败，请确保你的服务器能够下载Github的文件，如果多次安装失败，请手动安装${plain}"
    return 1
fi

bash install.sh node

if [[ $? -ne 0 ]];then
    echo -e "${red}节点安装失败${plain}"
else
    echo -e "${green}节点安装成功${plain}"
fi

echo "cleaning..."
rm install.sh
