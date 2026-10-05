#!/system/bin/sh
MODDIR=${0%/*}
export PATH="/system/bin:/system/xbin:/vendor/bin:/product/bin"

rm -f /data/adb/modules/XTCPatch/disable
rm -f /data/adb/modules/XTCPatch/disabled_by_rescue.txt
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开机检查：已删除 XTCPatch 禁用文件" >> $MODDIR/run.log

mkdir -p "$MODDIR/system/bin"

if [ ! -x "$MODDIR/system/bin/real_rm" ]; then
    cp -p /system/bin/rm "$MODDIR/system/bin/real_rm" 2>/dev/null
    chmod 755 "$MODDIR/system/bin/real_rm" 2>/dev/null
fi

SUCCESS_COUNT_FILE="$MODDIR/boot_success_count.log"
RESCUE_STEP="$MODDIR/rescue_step.txt"
if [ -f "$RESCUE_STEP" ]; then
    count=0
    if [ -f "$SUCCESS_COUNT_FILE" ]; then
        tmp_count=$(cat "$SUCCESS_COUNT_FILE" 2>/dev/null)
        case "$tmp_count" in
            ''|*[!0-9]*) count=0 ;;
            *) count=$tmp_count ;;
        esac
    fi
    if [ "$count" -ge 2 ]; then
        rm -f "$RESCUE_STEP"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 开机检查：步骤文件已删除" >> $MODDIR/run.log
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 开机检查：步骤文件未删除（条件未满足）" >> $MODDIR/run.log
    fi
fi

TEMP_LOG="$MODDIR/temp_reboot.log"
if [ -f "$TEMP_LOG" ]; then
    temp=$(cat "$TEMP_LOG" 2>/dev/null)
    case "$temp" in
        ''|*[!0-9]*) temp=0 ;;
        *) ;;
    esac
else
    temp=0
fi
temp=$((temp + 1))
echo "$temp" > "$TEMP_LOG"

PERM_LOG="$MODDIR/Number_of_starts.log"
if [ -f "$PERM_LOG" ]; then
    perm=$(cat "$PERM_LOG" 2>/dev/null)
    case "$perm" in
        ''|*[!0-9]*) perm=0 ;;
        *) ;;
    esac
else
    perm=0
fi
perm=$((perm + 1))
echo "$perm" > "$PERM_LOG"

if [ "$temp" -ge 4 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 连续重启 $temp 次，直接触发救砖" >> $MODDIR/rescue_action.log
    /system/bin/sh $MODDIR/Automatic_brick_rescue.sh force
    exit 0
fi
(
    sleep 300
    BOOT_SUCCESS_FLAG="/data/local/tmp/boot_success.txt"
    if [ -f "$BOOT_SUCCESS_FLAG" ]; then
        rm -f "$TEMP_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 正常启动，删除 temp_reboot.log" >> $MODDIR/rescue_action.log
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 300秒超时，系统未正常启动，触发救砖" >> $MODDIR/rescue_action.log
        /system/bin/sh $MODDIR/Automatic_brick_rescue.sh force
    fi
) &
exit 0