#!/bin/bash

#======================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: Manage v2-ui
#   Author: Style
#   Github - v2-ui: https://github.com/StyleTJy/v2-ui
#======================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v2.0.1"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " choice
        if [[ x"${choice}" == x"" ]]; then
            choice=$2
        fi
    else
        read -p "$1 [y/n]: " choice
    fi
    if [[ x"${choice}" == x"y" || x"${choice}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启面板" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/StyleTJy/v2-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "本功能会强制重装当前最新版，数据不会丢失，是否继续?" "n"
    if [[ $? != 0 ]]; then
        echo -e "${red}已取消${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    echo -e "${green}开始备份...${plain}"
    systemctl stop v2-ui
    cd /usr/local/
    mv v2-ui v2-ui.bak
    echo -e "${green}备份结束，开始更新...${plain}"
    bash <(curl -Ls https://raw.githubusercontent.com/StyleTJy/v2-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启面板${plain}"
        return 0
#        if [[ $# == 0 ]]; then
#            restart
#        else
#            restart 0
#        fi
    else # fail in updating, now rollback
        echo -e "${red}更新失败，开始回滚...${plain}"
        systemctl stop v2-ui
        cd /usr/local/
        rm -rf /usr/local/v2-ui
        mv v2-ui.bak v2-ui
        cp -f v2-ui/v2-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable v2-ui
        systemctl start v2-ui
        if [[ $? == 0 ]];then
            echo -e "${green}回滚成功${plain}"
        else
            echo -e "${red}回滚失败，请手动检查${plain}"
        fi
    fi
}

uninstall() {
    confirm "确定要卸载面板吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop v2-ui
    systemctl disable v2-ui
    rm /etc/systemd/system/v2-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/v2-ui/ -rf
    rm /usr/local/v2-ui/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/man-v2-ui -f${plain} 进行删除"
    echo ""
    echo -e "Github issues: ${green}https://github.com/StyleTJy/v2-ui/issues${plain}"

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "确定要将用户名和密码重置为 admin 吗" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/v2-ui/v2-ui resetuser
    echo -e "用户名和密码已重置为 ${green}admin${plain}，现在请重启面板"
    confirm_restart
}

reset_config() {
    confirm "确定要重置所有面板设置吗，账号数据不会丢失，用户名和密码不会改变" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/v2-ui/v2-ui resetconfig
    echo -e "所有面板已重置为默认值，现在请重启面板，并使用默认的 ${green}65432${plain} 端口访问面板"
    confirm_restart
}

set_port() {
    echo && echo -n -e "输入端口号[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        echo -e "${yellow}已取消${plain}"
        before_show_menu
    else
        /usr/local/v2-ui/v2-ui setport ${port}
        echo -e "设置端口完毕，现在请重启面板，并使用新设置的端口 ${green}${port}${plain} 访问面板"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}面板已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start v2-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}v2-ui 启动成功${plain}"
        else
            echo -e "${red}面板启动失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        echo -e "${green}面板已停止，无需再次停止${plain}"
    else
        systemctl stop v2-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            echo -e "${green}v2-ui 停止成功${plain}"
        else
            echo -e "${red}面板停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart v2-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}v2-ui 重启成功${plain}"
    else
        echo -e "${red}面板重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status v2-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable v2-ui
    if [[ $? == 0 ]]; then
        echo -e "${green}v2-ui 设置开机自启成功${plain}"
    else
        echo -e "${red}v2-ui 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable v2-ui
    if [[ $? == 0 ]]; then
        echo -e "${green}v2-ui 取消开机自启成功${plain}"
    else
        echo -e "${red}v2-ui 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

addnode(){
    if [[ $# == 3 ]] && [[ $3 == 1 ]];then
        /usr/local/v2-ui/v2-ui addnodenoc $1 $2
    elif [[ $# == 2 ]];then
        /usr/local/v2-ui/v2-ui addnode $1 $2
    else
        echo -e "${red}添加节点失败，参数错误${plain}"
        return 1
    fi
}

handle_addnode(){
    if [[ $1 == 1 ]];then
        echo "no-confirm 添加节点"
    fi
    read -p "请输入要添加的节点地址（域名或者IP）和备注（以空格隔开）: " -a node
    confirm "要添加的节点[${node[0]}(${node[1]})]" "y"
    if [[ $? == 0 ]];then
        if [[ $1 == 1 ]];then
            addnode ${node[0]} ${node[1]} 1
        else
            addnode ${node[0]} ${node[1]}
        fi
    fi
    if [[ $? == 0 ]];then
        before_show_menu
    fi
}

update_node(){
    if [[ $# != 3 ]];then
        echo -e "${red}更新节点失败，参数错误${plain}"
        return 1
    else
        /usr/local/v2-ui/v2-ui updnode $1 $2 $3
    fi
}

handle_updnode(){
    listnodes
    read -p "请输入要更新的节点id，列名（地址(address)或备注(remark)）和值（以空格隔开）: " -a args
    confirm "要更新节点id为[${args[0]}]的[${args[1]}]列的值为[${args[2]}]" "y"
    if [[ $? == 0 ]];then
        updnode ${args[0]} ${args[1]} ${args[2]}
    fi
    if [[ $? == 0 ]];then
        before_show_menu
    fi
}

listnodes(){
    /usr/local/v2-ui/v2-ui listnodes
  return $?
}

handle_listnodes(){
    listnodes
    if [[ $? == 0 ]];then
       before_show_menu
    fi
}

delnode(){
    if [[ $# != 1 ]];then
        echo -e "${red}删除节点失败，参数错误${plain}"
    else
        /usr/local/v2-ui/v2-ui delnode $1
    fi
}

handle_delnode(){
    listnodes
    read -p "请输入要删除的节点序号：" id
    confirm "要删除序号为[$id]的节点" "n"
    if [[ $? == 0 ]];then
        delnode $id
        if [[ $? == 0 ]];then
            before_show_menu
        fi
    fi
}

syncconfig(){
    /usr/local/v2-ui/v2-ui syncconfig
    return $?
}

handle_sync(){
    syncconfig
    if [[ $? == 0 ]];then
        before_show_menu
    fi
}

show_log() {
    echo && echo -n -e "面板使用过程中可能会输出许多 WARNING 日志，如果面板使用没有什么问题的话，那就没有问题，按回车继续: " && read temp
    tail -f /etc/v2-ui/v2-ui.log
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://gist.githubusercontent.com/StyleTJy/320abcbbc628dcc1bfd367ac4f02cf83/raw/69afafa2b69bad823c2d26fdc5b52536940c1354/install_bbr.sh)
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}安装 bbr 成功${plain}"
    else
        echo ""
        echo -e "${red}下载 bbr 安装脚本失败，请检查本机能否连接 Github${plain}"
    fi

    before_show_menu
}

update_shell() {
    wget -O /usr/bin/v2-ui -N --no-check-certificate https://raw.githubusercontent.com/StyleTJy/v2-ui/master/man-v2-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2-ui
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/v2-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status v2-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled v2-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}面板已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装面板${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "面板状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "面板状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "面板状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

show_usage() {
    echo "man-v2-ui 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "man-v2-ui                      - 显示管理菜单 (功能更多)"
    echo "man-v2-ui start                - 启动 v2-ui 面板"
    echo "man-v2-ui stop                 - 停止 v2-ui 面板"
    echo "man-v2-ui restart              - 重启 v2-ui 面板"
    echo "man-v2-ui status               - 查看 v2-ui 状态"
    echo "man-v2-ui addnode addr remark  - 添加子节点服务器"
    echo "man-v2-ui addnodenoc addr remark- 无验证添加节点"
    echo "man-v2-ui updnode id column val- 更新子节点服务器"
    echo "man-v2-ui delnode id           - 删除子节点服务器"
    echo "man-v2-ui listnodes            - 列出所有子节点服务器"
    echo "man-v2-ui syncconfig           - 与节点同步配置文件"
    echo "man-v2-ui enable               - 设置 v2-ui 开机自启"
    echo "man-v2-ui disable              - 取消 v2-ui 开机自启"
    echo "man-v2-ui log                  - 查看 v2-ui 日志"
    echo "man-v2-ui update               - 更新 v2-ui 面板"
    echo "man-v2-ui install              - 安装 v2-ui 面板"
    echo "man-v2-ui uninstall            - 卸载 v2-ui 面板"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}v2-ui 面板管理脚本${plain} ${red}${version}${plain}

---------------------------------

  ${green}0.${plain} 退出脚本
————————————————
  ${green}1.${plain} 安装 v2-ui
  ${green}2.${plain} 更新 v2-ui
  ${green}3.${plain} 卸载 v2-ui
————————————————
  ${green}4.${plain} 重置用户名密码
  ${green}5.${plain} 重置面板设置
  ${green}6.${plain} 设置面板端口
————————————————
  ${green}7.${plain} 启动 v2-ui
  ${green}8.${plain} 停止 v2-ui
  ${green}9.${plain} 重启 v2-ui
  ${green}10.${plain} 添加节点
  ${green}11.${plain} no-confirmed 添加节点
  ${green}12.${plain} 更新节点
  ${green}13.${plain} 删除节点
  ${green}14.${plain} 显示已有节点
  ${green}15.${plain} 与节点同步配置文件
  ${green}16.${plain} 查看 v2-ui 状态
  ${green}17.${plain} 查看 v2-ui 日志
————————————————
  ${green}18.${plain} 设置 v2-ui 开机自启
  ${green}19.${plain} 取消 v2-ui 开机自启
————————————————
  ${green}20.${plain} 一键安装 bbr (最新内核)
 "
    show_status
    echo && read -p "请输入选择 [0-19]: " num

    case "${num}" in
        0) exit 0
        ;;
        1) check_uninstall && install
        ;;
        2) check_install && update
        ;;
        3) check_install && uninstall
        ;;
        4) check_install && reset_user
        ;;
        5) check_install && reset_config
        ;;
        6) check_install && set_port
        ;;
        7) check_install && start
        ;;
        8) check_install && stop
        ;;
        9) check_install && restart
        ;;
        10) check_install 0 && handle_addnode
        ;;
        11) check_install 0 && handle_addnode 1
        ;;
        12) check_install 0 && handle_updnode
        ;;
        13) check_install 0 && handle_delnode
        ;;
        14) check_install 0 && handle_listnodes
        ;;
        15) check_install 0 && handle_sync
        ;;
        16) check_install && status
        ;;
        17) check_install && show_log
        ;;
        18) check_install && enable
        ;;
        19) check_install && disable
        ;;
        20) install_bbr
        ;;
        *) echo -e "${red}请输入正确的数字 [0-19]${plain}"
        ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0
        ;;
        "stop") check_install 0 && stop 0
        ;;
        "restart") check_install 0 && restart 0
        ;;
        "status") check_install 0 && status 0
        ;;
        "enable") check_install 0 && enable 0
        ;;
        "disable") check_install 0 && disable 0
        ;;
        "addnode") check_install 0 && addnode $2 $3
        ;;
        "addnodenoc") check_install 0 && addnode $2 $3 1
        ;;
        "updnode") check_install 0 && updnode $2 $3 $4
        ;;
        "delnode") check_install 0 && delnode $2
        ;;
        "listnodes") check_install 0 && listnodes
        ;;
        "syncconfig") check_install 0 && syncconfig
        ;;
        "log") check_install 0 && show_log 0
        ;;
        "update") check_install 0 && update 0
        ;;
        "install") check_uninstall 0 && install 0
        ;;
        "uninstall") check_install 0 && uninstall 0
        ;;
        *) show_usage
    esac
else
    show_menu
fi
