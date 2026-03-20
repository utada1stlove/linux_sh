# linux_sh

这是一个关于一键帮我初始化vps的脚本，包括以下内容：

- 更新软件库，安装基础软件
  
```sh
apt update -y && apt upgrade -y
apt install sudo curl wget vim lsof vnstati -y
```

- 矫正时区
  - 设置为新加坡时区，并开启ntp
- 安装vnstati
  - 设置vnstati——每次登录ssh都会弹出前24h使用流量的情况
- 设置shell提示符
  - 这是我现在的提示符
    ```.bashrc
    export PS1="\[\e[1;38;5;220m\]\u\[\e[1;38;5;228m\]@\[\e[1;38;5;49m\]LacusClyne\[\e[0m\] \[\e[1;38;5;228m\]\w\[\e[1;38;5;213m\] [\$(date +%H:%M:%S)]\$\[\e[0m\] "
    alias ls='ls --color=auto'
    ```
 - 设置bbr
   - 检测是否为lxc（lxc不能跑更换bbr的命令，所以如果是lxc，则跳过设置bbr这个选项）
 - 优化连接youtube的方案
   - 虽然测试speedtest数据很好看，但是连接youtube意外的很差
   - 想办法进行优化，尤其是去掉quic
