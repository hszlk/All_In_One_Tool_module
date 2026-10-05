#!/system/bin/sh
MODDIR=${0%/*}
MODID=${MODDIR##*/}
PERM_LOG=$MODDIR/Number_of_starts.log
TEMP_LOG=$MODDIR/temp_reboot.log
LOG=$MODDIR/Number_of_brick_rescue.log
RESCUE_STEP=$MODDIR/rescue_step.txt
USER_CONFIG="$MODDIR/user_config.prop"

log_cmd() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $MODDIR/rescue_action.log
}

get_prop() {
    local key="$1"
    local def="$2"
    if [ -f "$USER_CONFIG" ]; then
        local v=$(grep "^${key}=" "$USER_CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)
        [ -n "$v" ] && echo "$v" && return
    fi
    echo "$def"
}

is_step_enabled() {
    local n="$1"
    local v=$(get_prop "rescue.step${n}.enabled" "true")
    [ "$v" = "true" ]
}

get_order() {
    local v=$(get_prop "rescue.order" "1,2,3,4,5,6")
    echo "$v"
}

is_whitelisted() {
    local name="$1"
    [ -z "$name" ] && return 1
    [ -f "$MODDIR/${name}.conf" ]
}

list_whitelisted() {
    for f in "$MODDIR"/*.conf; do
        [ -f "$f" ] || continue
        basename "$f" | sed 's/\.conf$//'
    done
}

find_chattr() {
    if [ -x "/data/adb/magisk/busybox" ]; then
        echo "/data/adb/magisk/busybox chattr"
    elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -q chattr; then
        echo "busybox chattr"
    elif command -v chattr >/dev/null 2>&1; then
        echo "chattr"
    else
        echo ""
    fi
}

create_disable() {
    local module_path="$1"
    local disable_file="$module_path/disable"
    local chattr_cmd=$(find_chattr)

    log_cmd "尝试解除 $module_path 的不可变属性"
    if [ -n "$chattr_cmd" ]; then
        $chattr_cmd -i "$module_path" 2>/dev/null
        log_cmd "$chattr_cmd -i 返回码: $?"
    else
        log_cmd "未找到 chattr 命令，跳过"
    fi

    log_cmd "临时关闭 SELinux"
    setenforce 0 2>/dev/null
    log_cmd "setenforce 0 返回码: $?"

    log_cmd "尝试创建 $disable_file"
    touch "$disable_file" 2>/dev/null
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "" > "$disable_file" 2>/dev/null
        ret=$?
    fi
    log_cmd "touch/echo 返回码: $ret"

    setenforce 1 2>/dev/null
    log_cmd "恢复 SELinux，返回码: $?"

    if [ -f "$disable_file" ]; then
        echo "Disabled by Automatic_brick_rescue at $(date '+%Y-%m-%d %H:%M:%S')" > "$module_path/disabled_by_rescue.txt"
        echo "Reason: Non-whitelist module during rescue process" >> "$module_path/disabled_by_rescue.txt"
        return 0
    else
        log_cmd "常规禁用失败，尝试 mount --bind 强制禁用 $module_path"
        local bind_src="$MODDIR/disabled_bind/$(basename "$module_path")"
        mkdir -p "$bind_src"
        touch "$bind_src/disable"
        mount --bind "$bind_src" "$module_path" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Disabled by Automatic_brick_rescue at $(date '+%Y-%m-%d %H:%M:%S')" > "$module_path/disabled_by_rescue.txt"
            echo "Reason: Non-whitelist module during rescue process (mount --bind)" >> "$module_path/disabled_by_rescue.txt"
            log_cmd "mount --bind 成功，模块 $module_path 已被强制禁用"
            return 0
        else
            log_cmd "mount --bind 失败"
            return 1
        fi
    fi
}

Delete_XP_Modules_Not_In_Whitelist() {
    XP_WHITELIST="$MODDIR/xp_whitelist.txt"
    if [ ! -f "$XP_WHITELIST" ]; then
        log_cmd "白名单文件不存在，跳过 Xposed 删除"
        return
    fi
    find /data -name "modules.list" 2>/dev/null | while read list; do
        [ -f "$list" ] || continue
        while read line; do
            pkg=$(echo "$line" | grep -oE 'com\.[a-zA-Z0-9._]+' | head -1)
            [ -z "$pkg" ] && continue
            if grep -qx "$pkg" "$XP_WHITELIST" 2>/dev/null; then
                log_cmd "保留白名单模块: $pkg"
            else
                log_cmd "删除非白名单模块: $pkg"
                rm -rf "/data/app/$pkg"* 2>/dev/null
                rm -rf "/data/data/$pkg" 2>/dev/null
            fi
        done < "$list"
    done
}

Reserve() {
    for i in $(list_whitelisted); do
        rm -f "/data/adb/modules/$i/disable" 2>/dev/null
        rm -f "/data/adb/modules/$i/disabled_by_rescue.txt" 2>/dev/null
    done
}

Disable_Xposed_Modules_By_SDK() {
    SDK=$(cat "$MODDIR/sdk_version.txt" 2>/dev/null || getprop ro.build.version.sdk)
    XP_WHITELIST="$MODDIR/xp_whitelist.txt"

    if [ "$SDK" -lt 30 ]; then
        find /data -name "modules.list" 2>/dev/null | while read list; do
            [ -f "$list" ] || continue
            grep -E 'com\.huanli233\.systemplus|com\.zcg\.systemplus' "$list" > "$list.tmp" 2>/dev/null
            if [ -s "$list.tmp" ]; then
                mv "$list.tmp" "$list"
                log_cmd "已清理 Xposed 列表，保留白名单: $list"
            else
                > "$list"
                log_cmd "已清空 Xposed 列表: $list"
            fi
            rm -f "$list.tmp"
        done
    else
        LSPD_DIR="/data/adb/modules/riru_lsposed"
        if [ ! -d "$LSPD_DIR" ]; then
            log_cmd "未找到 LSPosed 目录: $LSPD_DIR，跳过 XP 模块禁用"
            return
        fi
        MODULES_LIST_FILE=""
        if [ -f "$LSPD_DIR/modules.list" ]; then
            MODULES_LIST_FILE="$LSPD_DIR/modules.list"
        elif [ -f "$LSPD_DIR/config/modules_config.json" ]; then
            MODULES_LIST_FILE="$LSPD_DIR/config/modules_config.json"
        else
            found=$(find "$LSPD_DIR" -name "modules.list" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                MODULES_LIST_FILE="$found"
            else
                found=$(find "$LSPD_DIR" -name "modules_config.json" 2>/dev/null | head -1)
                [ -n "$found" ] && MODULES_LIST_FILE="$found"
            fi
        fi
        if [ -z "$MODULES_LIST_FILE" ]; then
            log_cmd "未在 $LSPD_DIR 下找到模块列表文件"
            return
        fi
        log_cmd "找到 LSPosed 模块列表文件: $MODULES_LIST_FILE"
        PACKAGES=""
        case "$MODULES_LIST_FILE" in
            *.json)
                PACKAGES=$(grep -oE '"packageName"[[:space:]]*:[[:space:]]*"[^"]+"' "$MODULES_LIST_FILE" | sed 's/.*"packageName"[[:space:]]*:[[:space:]]*"//;s/".*//')
                ;;
            *)
                PACKAGES=$(grep -oE 'com\.[a-zA-Z0-9._]+' "$MODULES_LIST_FILE")
                ;;
        esac
        echo "$PACKAGES" | while read pkg; do
            [ -z "$pkg" ] && continue
            if grep -qx "$pkg" "$XP_WHITELIST" 2>/dev/null; then
                log_cmd "保留白名单 XP 模块: $pkg"
                continue
            fi
            DISABLE_CREATED=0
            if [ -d "$LSPD_DIR/$pkg" ]; then
                touch "$LSPD_DIR/$pkg/disable" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_cmd "已在 $LSPD_DIR/$pkg 创建 disable 文件，禁用模块: $pkg"
                    DISABLE_CREATED=1
                fi
            fi
            if [ $DISABLE_CREATED -eq 0 ] && [ -d "$LSPD_DIR/config" ]; then
                touch "$LSPD_DIR/config/disable_$pkg" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_cmd "已在 $LSPD_DIR/config 创建 disable_$pkg 文件，禁用模块: $pkg"
                    DISABLE_CREATED=1
                fi
            fi
            if [ $DISABLE_CREATED -eq 0 ]; then
                list_dir=$(dirname "$MODULES_LIST_FILE")
                touch "$list_dir/disable_$pkg" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_cmd "已在 $list_dir 创建 disable_$pkg 文件，禁用模块: $pkg"
                    DISABLE_CREATED=1
                fi
            fi
            if [ $DISABLE_CREATED -eq 0 ]; then
                log_cmd "警告：无法为 $pkg 创建禁用文件，跳过"
            fi
        done
    fi
}

Disable_All_Modules() {
    Disable_Xposed_Modules_By_SDK

    ls "/data/adb/modules" 2>/dev/null | while read i; do
        [ -z "$i" ] && continue
        [ "$i" = "$MODID" ] && continue
        if is_whitelisted "$i"; then
            continue
        fi
        if create_disable "/data/adb/modules/$i"; then
            log_cmd "已禁用模块: $i"
        else
            log_cmd "无法禁用模块: $i"
        fi
    done
    Reserve
}

Statistics() {
    if [ ! -f "$LOG" ]; then
        echo "1" > "$LOG"
    else
        n=$(cat "$LOG")
        echo "$((n + 1))" > "$LOG"
    fi
}

force_reboot() {
    sync
    sleep 1
    reboot 2>/dev/null &
    sleep 2
    if [ -f /proc/sys/kernel/sysrq ]; then
        echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
    fi
    if [ -f /proc/sysrq-trigger ]; then
        echo b > /proc/sysrq-trigger 2>/dev/null
    fi
    sleep 2
    killall init 2>/dev/null
    exit 0
}

increment_step() {
    log_cmd "步骤执行完毕，准备重启"
}

Execute_Step1() {
    log_cmd "执行救砖第一步：恢复默认桌面"

    BACKUP_DIR="$MODDIR/backup"

    if [ -d "$BACKUP_DIR/data_user/com.xtc.i3launcher" ]; then
        rm -rf /data/user/0/com.xtc.i3launcher 2>/dev/null
        cp -a "$BACKUP_DIR/data_user/com.xtc.i3launcher" /data/user/0/ 2>/dev/null
        chown -R 1000:1000 /data/user/0/com.xtc.i3launcher 2>/dev/null
        chmod -R 771 /data/user/0/com.xtc.i3launcher 2>/dev/null
        log_cmd "已恢复 /data/user/0/com.xtc.i3launcher"
    else
        log_cmd "未找到备份 /data/user/0/com.xtc.i3launcher，跳过"
    fi

    if [ -f "$BACKUP_DIR/data_app_name.txt" ]; then
        DATA_APP_NAME=$(cat "$BACKUP_DIR/data_app_name.txt" 2>/dev/null | tr -d '\r\n')
        if [ -n "$DATA_APP_NAME" ] && [ -d "$BACKUP_DIR/data_app/$DATA_APP_NAME" ]; then
            rm -rf "/data/app/$DATA_APP_NAME" 2>/dev/null
            cp -a "$BACKUP_DIR/data_app/$DATA_APP_NAME" /data/app/ 2>/dev/null
            chown -R 1000:1000 "/data/app/$DATA_APP_NAME" 2>/dev/null
            chmod -R 755 "/data/app/$DATA_APP_NAME" 2>/dev/null
            log_cmd "已恢复 /data/app/$DATA_APP_NAME"
        else
            log_cmd "未找到备份 /data/app/$DATA_APP_NAME，跳过"
        fi
    else
        log_cmd "未找到 data_app_name.txt，跳过"
    fi

    if [ -d "$BACKUP_DIR/system_app/XTCLauncher" ]; then
        mkdir -p "$MODDIR/system/app"
        rm -rf "$MODDIR/system/app/XTCLauncher"
        cp -a "$BACKUP_DIR/system_app/XTCLauncher" "$MODDIR/system/app/" 2>/dev/null
        log_cmd "已恢复 /system/app/XTCLauncher 到模块挂载点"
    else
        log_cmd "未找到备份 /system/app/XTCLauncher，跳过"
    fi

    LAUNCHER_FILE="$MODDIR/default_launcher.txt"
    if [ -f "$LAUNCHER_FILE" ]; then
        LAUNCHER=$(cat "$LAUNCHER_FILE" 2>/dev/null | tr -d '\r\n' | head -1)
        if [ -n "$LAUNCHER" ]; then
            log_cmd "读取默认桌面: $LAUNCHER"

            if command -v cmd >/dev/null 2>&1; then
                cmd package set-home-activity "$LAUNCHER" >> $MODDIR/rescue_action.log 2>&1
            fi
            if [ $? -ne 0 ]; then
                pm set-home-activity "$LAUNCHER" >> $MODDIR/rescue_action.log 2>&1
            fi

            if [ $? -eq 0 ]; then
                log_cmd "已设置默认桌面为 $LAUNCHER"
            else
                log_cmd "设置默认桌面失败，尝试 fallback"
                settings put secure home_activity "$LAUNCHER" 2>/dev/null
            fi
        else
            log_cmd "default_launcher.txt 为空，跳过"
        fi
    else
        log_cmd "未找到 default_launcher.txt，跳过默认桌面设置"
    fi

    settings delete secure display_density_forced 2>/dev/null
    settings delete global display_density_forced 2>/dev/null
    settings delete system display_density_forced 2>/dev/null
    wm density reset 2>/dev/null
    log_cmd "已删除 DPI 强制设置并执行 wm density reset"

    increment_step
    log_cmd "救砖第一步完成，即将重启"
    force_reboot
}

Execute_Step2() {
    log_cmd "执行救砖第二步：Magisk 模块救砖"
    Disable_All_Modules
    increment_step
    log_cmd "救砖第二步完成，即将重启"
    force_reboot
}

Execute_Step3() {
    log_cmd "执行救砖第三步：禁用 XP 模块"
    Disable_Xposed_Modules_By_SDK
    increment_step
    log_cmd "救砖第三步完成，即将重启"
    force_reboot
}

Execute_Step4() {
    log_cmd "执行救砖第四步：物理删除功能已移除，跳过"
    increment_step
    log_cmd "救砖第四步完成，即将重启"
    force_reboot
}

Execute_Step5() {
    log_cmd "执行救砖第五步：删除 magisk.db 重置授权"
    if [ -f "/data/adb/magisk.db" ]; then
        chattr_cmd=$(find_chattr)
        [ -n "$chattr_cmd" ] && $chattr_cmd -i /data/adb/magisk.db 2>/dev/null
        rm -f /data/adb/magisk.db 2>/dev/null
        if [ $? -eq 0 ]; then
            log_cmd "已删除 /data/adb/magisk.db"
        else
            log_cmd "删除 /data/adb/magisk.db 失败"
        fi
    else
        log_cmd "/data/adb/magisk.db 不存在，跳过"
    fi
    increment_step
    log_cmd "救砖第五步完成，即将重启"
    force_reboot
}

Execute_Step6() {
    log_cmd "执行救砖第六步：备份 framework-res.apk"
    PRE_BACKUP="$MODDIR/framework-res.apk.bak"
    if [ -f "$PRE_BACKUP" ]; then
        mkdir -p "$MODDIR/system/framework"
        cp -f "$PRE_BACKUP" "$MODDIR/system/framework/framework-res.apk" 2>/dev/null
        log_cmd "使用预备份 framework-res.apk"
    else
        if [ -f "/system/framework/framework-res.apk" ]; then
            mkdir -p "$MODDIR/system/framework"
            cp -f "/system/framework/framework-res.apk" "$MODDIR/system/framework/framework-res.apk" 2>/dev/null
            log_cmd "动态备份 framework-res.apk"
        else
            log_cmd "警告：framework-res.apk 不存在"
        fi
    fi
    increment_step
    log_cmd "救砖第六步完成，即将重启"
    force_reboot
}

run_rescue() {
    local order=$(get_order)
    local old_ifs="$IFS"
    IFS=','
    set -- $order
    IFS="$old_ifs"

    local total=$#
    local current_idx=0
    [ -f "$RESCUE_STEP" ] && current_idx=$(cat "$RESCUE_STEP" 2>/dev/null)
    case "$current_idx" in
        ''|*[!0-9]*) current_idx=0 ;;
    esac

    local next_idx=$current_idx
    local next_step=""

    while [ "$next_idx" -lt "$total" ]; do
        local s=""
        local i=0
        for arg in "$@"; do
            if [ "$i" -eq "$next_idx" ]; then
                s="$arg"
                break
            fi
            i=$((i + 1))
        done
        [ -z "$s" ] && break

        if is_step_enabled "$s"; then
            next_step="$s"
            break
        fi
        log_cmd "步骤 $s 已禁用，跳过"
        next_idx=$((next_idx + 1))
    done

    if [ -z "$next_step" ]; then
        log_cmd "所有步骤已完成或全部禁用"
        rm -f "$RESCUE_STEP"
        return
    fi

    echo "$((next_idx + 1))" > "$RESCUE_STEP"
    log_cmd "执行顺序索引: $((next_idx + 1)) / $total，执行步骤: $next_step"

    case "$next_step" in
        1) Execute_Step1 ;;
        2) Execute_Step2 ;;
        3) Execute_Step3 ;;
        4) Execute_Step4 ;;
        5) Execute_Step5 ;;
        6) Execute_Step6 ;;
        *) log_cmd "未知步骤: $next_step" ;;
    esac
}

if [ "$1" = "force" ]; then
    Statistics
    rm -f "$MODDIR/boot_success_count.log"
    rm -f "$TEMP_LOG"
    run_rescue
    exit 0
else
    if [ -f "$TEMP_LOG" ]; then
        temp=$(cat "$TEMP_LOG")
    else
        temp=0
    fi
    if [ $temp -ge 4 ]; then
        Statistics
        rm -f "$MODDIR/boot_success_count.log"
        rm -f "$TEMP_LOG"
        run_rescue
    fi
    exit 0
fi