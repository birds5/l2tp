#!/bin/bash
#############################################################
#                                                           #
# This is a PPTP and L2TP VPN installation for CentOS 7     #
# Version: 1.1.1 20220114                                   #
# Author:                                                   #
# Website:                                                  #
#                                                           #
#############################################################

#检测是否是root用户
if [[ $(id -u) != "0" ]]; then
    printf "\e[42m\e[31mError: You must be root to run this install script.\e[0m\n"
    exit 1
fi

#检测是否是CentOS 7或者RHEL 7
if [[ $(grep "release 7." /etc/redhat-release 2>/dev/null | wc -l) -eq 0 ]]; then
    printf "\e[42m\e[31mError: Your OS is NOT CentOS 7 or RHEL 7.\e[0m\n"
    printf "\e[42m\e[31mThis install script is ONLY for CentOS 7 and RHEL 7.\e[0m\n"
    exit 1
fi
clear

printf "
#############################################################
#                                                           #
# This is a PPTP and L2TP VPN installation for CentOS 7     #
# Version: 1.1.1 20220114                                   #
# Author:    xx                                             #
# Website:                                                  #
#                                                           #
#############################################################
"

#获取服务器IP
serverip=$(ifconfig -a |grep -w "inet"| grep -v "127.0.0.1" |awk '{print $2;}')
printf "\e[33m$serverip\e[0m is the server IP?"
printf "If \e[33m$serverip\e[0m is \e[33mcorrect\e[0m, press enter directly."
printf "If \e[33m$serverip\e[0m is \e[33mincorrect\e[0m, please input your server IP."
printf "(Default server IP: \e[33m$serverip\e[0m):"
read serveriptmp
if [[ -n "$serveriptmp" ]]; then
    serverip=$serveriptmp
fi

#获取网卡接口名称
ethlist=$(ifconfig | grep ": flags" | cut -d ":" -f1)
eth=$(printf "$ethlist\n" | head -n 1)
if [[ $(printf "$ethlist\n" | wc -l) -gt 2 ]]; then
    echo ======================================
    echo "Network Interface list:"
    printf "\e[33m$ethlist\e[0m\n"
    echo ======================================
    echo "Which network interface you want to listen for ocserv?"
    printf "Default network interface is \e[33m$eth\e[0m, let it blank to use default network interface: "
    read ethtmp
    if [ -n "$ethtmp" ]; then
        eth=$ethtmp
    fi
fi

#设置VPN拨号后分配的IP段
iprange="192.168.18"
echo "Please input IP-Range:"
printf "(Default IP-Range: \e[33m$iprange\e[0m): "
read iprangetmp
if [[ -n "$iprangetmp" ]]; then
    iprange=$iprangetmp
fi

#设置预共享密钥
mypsk="test"
echo "Please input PSK:"
printf "(Default PSK: \e[33mtest\e[0m): "
read mypsktmp
if [[ -n "$mypsktmp" ]]; then
    mypsk=$mypsktmp
fi

#设置VPN用户名
username="test"
echo "Please input VPN username:"
printf "(Default VPN username: \e[33mtest\e[0m): "
read usernametmp
if [[ -n "$usernametmp" ]]; then
    username=$usernametmp
fi

#随机密码
randstr() {
    index=0
    str=""
    for i in {a..z}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {A..Z}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {0..9}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
    echo $str
}

#设置VPN用户密码
password=$(randstr)
printf "Please input \e[33m$username\e[0m's password:\n"
printf "Default password is \e[33m$password\e[0m, let it blank to use default password: "
read passwordtmp
if [[ -n "$passwordtmp" ]]; then
    password=$passwordtmp
fi

clear

#打印配置参数
clear
echo "Server IP:"
echo "$serverip"
echo
echo "Server Local IP:"
echo "$iprange.1"
echo
echo "Client Remote IP Range:"
echo "$iprange.10-$iprange.254"
echo
echo "PSK:"
echo "$mypsk"
echo
echo "Press any key to start..."

get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}
char=$(get_char)
clear
mknod /dev/random c 1 9

#更新组件
yum update -y

#安装epel源
yum install epel-release -y

#安装依赖的组件
yum install -y libreswan ppp pptpd xl2tpd wget firewalld

#创建ipsec.conf配置文件
rm -f /etc/ipsec.conf
cat >>/etc/ipsec.conf<<EOF
version 2.0

config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    interfaces=%defaultroute
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat

conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

#设置预共享密钥配置文件
rm -f /etc/ipsec.secrets
cat >>/etc/ipsec.secrets<<EOF
#include /etc/ipsec.d/*.secrets
$serverip %any: PSK "$mypsk"
EOF

#创建pptpd.conf配置文件
rm -f /etc/pptpd.conf
cat >>/etc/pptpd.conf<<EOF
#ppp /usr/sbin/pppd
option /etc/ppp/options.pptpd
#debug
# stimeout 10
#noipparam
logwtmp
#vrf test
#bcrelay eth1
#delegate
#connections 100
localip $iprange.2
remoteip $iprange.200-254

EOF

#创建xl2tpd.conf配置文件
mkdir -p /etc/xl2tpd
rm -f /etc/xl2tpd/xl2tpd.conf
cat >>/etc/xl2tpd/xl2tpd.conf<<EOF
[global]
port = 1701

[lns default]
ip range = ${iprange}.2-${iprange}.254
local ip = ${iprange}.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

#创建options.pptpd配置文件
mkdir -p /etc/ppp
rm -f /etc/ppp/options.pptpd
cat >>/etc/ppp/options.pptpd<<EOF
# Authentication
name pptpd
#chapms-strip-domain

# Encryption
# BSD licensed ppp-2.4.2 upstream with MPPE only, kernel module ppp_mppe.o
# {{{
refuse-pap
refuse-chap
refuse-mschap
# Require the peer to authenticate itself using MS-CHAPv2 [Microsoft
# Challenge Handshake Authentication Protocol, Version 2] authentication.
require-mschap-v2
# Require MPPE 128-bit encryption
# (note that MPPE requires the use of MSCHAP-V2 during authentication)
require-mppe-128
# }}}

# OpenSSL licensed ppp-2.4.1 fork with MPPE only, kernel module mppe.o
# {{{
#-chap
#-chapms
# Require the peer to authenticate itself using MS-CHAPv2 [Microsoft
# Challenge Handshake Authentication Protocol, Version 2] authentication.
#+chapms-v2
# Require MPPE encryption
# (note that MPPE requires the use of MSCHAP-V2 during authentication)
#mppe-40    # enable either 40-bit or 128-bit, not both
#mppe-128
#mppe-stateless
# }}}

ms-dns 114.114.114.114
ms-dns 223.5.5.5

#ms-wins 10.0.0.3
#ms-wins 10.0.0.4

proxyarp
#10.8.0.100

# Logging
#debug
#dump
lock
nobsdcomp 
novj
novjccomp
nologfd

EOF

#创建options.xl2tpd配置文件
rm -f /etc/ppp/options.xl2tpd
cat >>/etc/ppp/options.xl2tpd<<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 114.114.114.114
ms-dns 223.5.5.5
noccp
auth
hide-password
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

#创建chap-secrets配置文件，即用户列表及密码
rm -f /etc/ppp/chap-secrets
cat >>/etc/ppp/chap-secrets<<EOF
# Secrets for authentication using CHAP
# client     server     secret               IP addresses
$username          pptpd     $password               *
$username          l2tpd     $password               *
EOF

#修改系统配置，允许IP转发
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.$eth.rp_filter=0
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.default.send_redirects=0
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.default.accept_redirects=0

cat >>/etc/sysctl.conf<<EOF

net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.$eth.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
EOF

#允许防火墙端口
cat >>/usr/lib/firewalld/services/pptpd.xml<<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>pptpd</short>
  <description>PPTP and Fuck the GFW</description>
  <port protocol="tcp" port="1723"/>
</service>
EOF

cat >>/usr/lib/firewalld/services/xl2tpd.xml<<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>l2tpd</short>
  <description>L2TP IPSec</description>
  <port protocol="udp" port="500"/>
  <port protocol="udp" port="4500"/>
  <port protocol="udp" port="1701"/>
</service>
EOF
systemctl start firewalld
firewall-cmd --reload
firewall-cmd --permanent --add-service=pptpd
firewall-cmd --permanent --add-service=xl2tpd
firewall-cmd --permanent --add-service=ipsec
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

#iptables --table nat --append POSTROUTING --jump MASQUERADE
#iptables -t nat -A POSTROUTING -s $iprange.0/24 -o $eth -j MASQUERADE
#iptables -t nat -A POSTROUTING -s $iprange.0/24 -j SNAT --to-source $serverip
#iptables -I FORWARD -p tcp –syn -i ppp+ -j TCPMSS –set-mss 1356
#service iptables save

#允许开机启动
systemctl enable pptpd ipsec xl2tpd firewalld
systemctl restart pptpd ipsec xl2tpd firewalld
clear

#测试ipsec
ipsec verify

printf "
#############################################################
#                                                           #
# This is a PPTP and L2TP VPN installation for CentOS 7     #
# Version: 1.1.1 20220114                                   #
# Author:                                                   #
# Website:                                                  #
#                                                           #
#############################################################
if there are no [FAILED] above, then you can
connect to your L2TP VPN Server with the default
user/password below:

ServerIP: $serverip
username: $username
password: $password
PSK: $mypsk

"
