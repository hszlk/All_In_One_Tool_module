#!/system/bin/sh
MODDIR=${0%/*}
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 2

wm density reset 2>/dev/null

rm -f "$MODDIR/temp_reboot.log"

if [ -f "$MODDIR/rescue_step.txt" ]; then
    SUCCESS_COUNT_FILE="$MODDIR/boot_success_count.log"
    count=0
    [ -f "$SUCCESS_COUNT_FILE" ] && count=$(cat "$SUCCESS_COUNT_FILE")
    count=$((count + 1))
    echo "$count" > "$SUCCESS_COUNT_FILE"

    if [ "$count" -ge 2 ]; then
        rm -f "$MODDIR/rescue_step.txt"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 系统正常启动，已清除救砖标记" >> $MODDIR/run.log
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 系统正常启动，正常启动次数不足" >> $MODDIR/run.log
    fi
fi

touch /data/local/tmp/boot_success.txt

pm uninstall -k --user 0 com.xtc.systemupdate_i11 2>/dev/null
pm disable --user 0 com.xtc.appupdate 2>/dev/null

PERM_COUNT=$(cat "$MODDIR/Number_of_starts.log" 2>/dev/null || echo "0")
RESCUE_COUNT=$(cat "$MODDIR/Number_of_brick_rescue.log" 2>/dev/null || echo "0")
if [ -f "$MODDIR/rescue_step.txt" ]; then
    pos=$(cat "$MODDIR/rescue_step.txt" 2>/dev/null | tr -d '\r\n')
    order=$(grep "^rescue.order=" "$MODDIR/user_config.prop" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -z "$order" ] && order="1,2,3,4,5,6"
    step=$(echo "$order" | cut -d, -f"$pos")
    case $step in
        1) DESC="🧱 桌面爆炸砖" ;;
        2) DESC="🧱 Magisk轻度模块砖" ;;
        3) DESC="🧱 XP模块砖" ;;
        4) DESC="🧱 Magisk重度模块砖" ;;
        5) DESC="🧱 Zygisk砖" ;;
        6) DESC="🧱 framework-res砖" ;;
        *) DESC="✅ 当前环境正常暂无风险" ;;
    esac
else
    DESC="✅ 当前环境正常暂无风险"
fi
sed "/^description=/c description=🛡️ 总开机 $PERM_COUNT 次 | 救砖 $RESCUE_COUNT 次 | $DESC" "$MODDIR/module.prop" > "$MODDIR/module.prop.tmp" 2>/dev/null && mv "$MODDIR/module.prop.tmp" "$MODDIR/module.prop"

XP_WHITELIST="$MODDIR/xp_whitelist.txt"
find /data -name "modules.list" 2>/dev/null | while read list; do
    if [ -f "$list" ]; then
        grep -oE 'com\.[a-zA-Z0-9._]+' "$list" 2>/dev/null > "$XP_WHITELIST"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 已备份 Xposed 模块白名单，共 $(cat "$XP_WHITELIST" 2>/dev/null | wc -l) 个模块" >> $MODDIR/run.log
        break
    fi
done

am broadcast -n com.firewall_aio.hszlk/.BootReceiver -a com.firewall_aio.hszlk.action.COLLECT

if [ -f "$MODDIR/power_save.sh" ]; then
    chmod 755 "$MODDIR/power_save.sh"
    mkdir -p "$MODDIR/cron"
    echo "* * * * * $MODDIR/power_save.sh" > "$MODDIR/cron/root"
    /data/adb/magisk/busybox crond -c "$MODDIR/cron"
fi

exit 0