#!/usr/bin/env sh

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

pyinstaller --version > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${red}pyinstaller is not installed.${plain}"
    echo -e "${yellow}run pip install pyinstaller to install it.${plain}"
    return 1
fi

echo -e "${yellow}compiling v2-node...${plain}"

pyinstaller v2-node.spec

if [[ $? -ne 0 ]];then
    echo -e "${red}compile v2-node failed.${plain}"
else
    echo -e "${green}compile v2-node successfully.${plain}"
    cd dist
    tar czvf v2-node.tar.gz v2-node
    echo -e "${green}package v2-node completed.${plain}"
    cd ..
fi


pyinstaller v2-ui.spec

if [[ $? -ne 0 ]]; then
    echo -e "${red}compile v2-ui failed.${plain}"
else
    echo -e "${green}compile v2-ui successfully.${plain}"
    cd dist
    tar czvf v2-ui-linux.tar.gz v2-ui
    echo -e "${green}package v2-ui completed.${plain}"
fi


