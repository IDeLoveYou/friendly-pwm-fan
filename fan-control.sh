#!/bin/bash

# 定义保存默认数据的文件路径
SAVE="/tmp/fan-default/fan-default"

# 获取脚本执行时传入的第一个参数，用于确定要执行的操作（"get"、"set" 或 "temp"）
ACTION="${1}"

# 将命令行参数向左移动一位，以便后续处理
shift

# Function to get the thermal zone with minimum and maximum trip points
# 获取具有最低和最高温度trip点的热区域函数
getFanTP() {
    local zone cdev trip temp mintemp mintrip minzone maxtemp

    # 检查是否存在thermal目录，否则返回错误
    [[ -d /sys/class/thermal ]] || return 1

    # 进入thermal目录
    cd /sys/class/thermal || exit

    # 遍历thermal_zone*目录
    for zone in thermal_zone*; do
        # 进入当前zone目录
        cd "$zone" || exit

        # 遍历以cdev开头的目录
        for cdev in cdev[0-9]*; do
            # 忽略非目录
            [[ -d "$cdev" ]] || continue

            # 检查cdev目录下是否包含'fan'
            grep -Fiq fan "$cdev/type" || continue

            # 获取trip点号
            trip=$(cat "${cdev}_trip_point")

            # 检查trip点是否处于活动状态
            grep -Fwq active "trip_point_${trip}_type" || continue

            # 检查文件权限是否为0644
            [[ "$(stat -c '%#a' "trip_point_${trip}_temp" 2>/dev/null || echo 0444)" = "0644" ]] || continue

            # 获取温度值
            temp=$(cat "trip_point_${trip}_temp")

            # 更新最小温度和对应的trip点
            if [[ -z "$mintemp" ]] || [[ "$temp" -lt "$mintemp" ]]; then
                mintemp=$temp
                mintrip=$trip
                minzone=$zone
            fi

            # 更新最大温度
            if [[ -z "$maxtemp" ]] || [[ "$temp" -gt "$maxtemp" ]]; then
                maxtemp=$temp
            fi
        done

        # 返回thermal目录
        cd /sys/class/thermal || exit
    done

    # 如果找到了最小温度，则输出信息并返回成功
    if [[ -n "$mintemp" ]]; then
        echo "$minzone" "$mintrip" "$mintemp" "$maxtemp"
        return 0
    else
        # 否则返回错误
        return 1
    fi
}

# Function to get the current fan trip points
# 获取当前风扇trip点函数
getFanTP_C() {
    # 如果文件 "$SAVE" 存在且非空，从文件中读取数据并返回0
    if [[ -f "$SAVE" && -s "$SAVE" ]]; then
        cat "$SAVE"
        return 0
    fi

    # 否则，调用 getFanTP 函数获取设置，并将结果写入文件 "$SAVE"，然后返回1或0（根据文件是否为空）
    getFanTP | tee "$SAVE"
    [[ -s "$SAVE" ]]
}

# Function to update fan trip points
# 更新风扇trip点函数
getFanTP_U() {
    local zone trip

    # 从 getFanTP_C 函数获取当前风扇trip点设置，并提取信息
    read -r zone trip _ < <(getFanTP_C) || return 1

    # 如果 zone 和 trip 存在，返回这些信息，否则返回1表示失败
    [[ -n "$zone" && -n "$trip" ]] || return 1

    # 构建 trip点温度文件的路径
    ON_TEMP="$(cat "/sys/class/thermal/${zone}/trip_point_${trip}_temp")"
    OFF_TEMP="$((ON_TEMP - $(cat "/sys/class/thermal/${zone}/trip_point_${trip}_hyst")))"

    # 返回热区域、trip点、trip点温度和最高温度信息
    echo "$zone" "$trip" "$((ON_TEMP / 1000))" "$((OFF_TEMP / 1000))"
    return 0
}

# Function to set fan trip points
# 设置风扇trip点函数
setFanTP() {
    local zone trip maxTemp ON_TEMP OFF_TEMP

    # 接受两个参数：ON_TEMP 和可选的 OFF_TEMP
    ON_TEMP=$(($1 * 1000))
    if [ -n "$2" ]; then
        OFF_TEMP=$(($2 * 1000))
    else
        OFF_TEMP=$((ON_TEMP - 5000))
    fi

    # 检查参数的有效性，确保 ON_TEMP 大于 5000 并且大于 OFF_TEMP
    [[ -n "$ON_TEMP" && "$ON_TEMP" -gt 5000 && "$ON_TEMP" -gt "$OFF_TEMP" ]] || {
        echo "Invalid input" >&2
        return 1
    }

    # 从 getFanTP_C 函数获取当前风扇trip点设置，并提取信息
    read -r zone trip _ maxTemp < <(getFanTP_C) || return 1

    # 检查 zone、trip 存在并且对应的热区域目录存在，否则返回1表示失败
    [[ -n "$zone" && -n "$trip" && -d "/sys/class/thermal/${zone}" ]] || return 1

    # 如果 maxTemp 存在且 ON_TEMP 大于等于 maxTemp，修正 ON_TEMP 为 maxTemp 减去 5000，并在标准错误输出上发出警告
    if [[ -n "$maxTemp" && "$ON_TEMP" -ge "$maxTemp" ]]; then
        ON_TEMP=$((maxTemp - 5000))
        echo "WARN: ON_TEMP is greater than next TP $maxTemp, fixed to $ON_TEMP" >&2
    fi

    # 将新的 ON_TEMP 写入 trip点温度文件，将温度差值写入 trip点温度差值文件
    echo "$ON_TEMP" >"/sys/class/thermal/${zone}/trip_point_${trip}_temp"
    echo "$((ON_TEMP - OFF_TEMP))" >"/sys/class/thermal/${zone}/trip_point_${trip}_hyst"
}

# Function to get current thermal temperature and fan on temp
# 获取当前热温度和风扇trip点温度函数
getTemp() {
    local zone trip temp tpt

    # 从 getFanTP_C 函数获取当前风扇trip点设置，并提取信息
    read -r zone trip _ < <(getFanTP_C) || return 1

    # 检查 zone、trip 存在，并且温度文件存在，否则返回1表示失败
    [[ -n "$zone" && -n "$trip" && -f "/sys/class/thermal/$zone/temp" ]] || return 1

    # 获取当前热温度和风扇trip点温度，并返回这些信息
    temp=$(cat "/sys/class/thermal/$zone/temp")
    tpt=$(cat "/sys/class/thermal/$zone/trip_point_${trip}_temp")
    echo "$temp $tpt"
}

# Function to display usage information
# 显示脚本的使用信息函数
usage() {
    echo "usage: $0 sub-command"
    echo "where sub-command is one of:"
    echo "      get                     Get Fan setting"
    echo "      set ON_TEMP [OFF_TEMP]  Set Fan setting"
    echo "      temp                    Get current thermal temp and Fan on temp"
}

# 保存默认温度墙
[[ -f "$SAVE" ]] || (mkdir -p "$(dirname "$SAVE")" && (getFanTP >"$SAVE"))

# 主脚本部分，根据传入的 ACTION 变量的值执行不同的子命令
case "${ACTION}" in
"get")
    getFanTP_U
    ;;
"set")
    setFanTP "$@"
    ;;
"temp")
    getTemp
    ;;
*)
    # 如果传入的命令不在列表中，显示使用信息并退出脚本
    usage
    exit 1
    ;;
esac
