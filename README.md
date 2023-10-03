# friendly-pwm-fan

## 目录

-   [设备](#设备)
-   [使用方式](#使用方式)
-   [开机自启](#开机自启)

> 借鉴了[jjm2473](https://github.com/jjm2473/openwrt-apps/commit/b66c6ae196bf95595caef8dc9d84338aeab3bbb0 "jjm2473")的脚本，并进行改进

### 设备

适用于友善friendly系列的pwm-fan控温脚本，R2S\R4S\R5S\R5C等

由于友善除了openwrt以外的固件并没有提供自定义控温脚本，于是自己写了一个

### 使用方式

```bash
#赋予执行权限
chmod 777 fan-control.sh

#获取当前设备温度
fan-control.sh temp

#设置温度配置文件
fan-control.sh set [风扇启动温度] [风扇停止温度(可选，没有的话默认为风扇启动温度减5摄氏度)]
eg: ./fan-control.sh set 55
    ./fan-control.sh set 55 50

#显示温度配置文件
fan-control.sh get

```

## 开机自启

```bash
#设置完温度配置后，1-2s后配置生效，风扇在达到指定温度就会转动
#但是重启设备后配置文件会刷新，请将你设置温度配置的命令添加为开机运行即可
fan-control.sh set 55 50
```
