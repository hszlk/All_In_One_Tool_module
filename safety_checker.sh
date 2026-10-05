#!/system/bin/sh
MODDIR=${0%/*}
MALWARE_DETECTOR="$MODDIR/malware_detector.sh"
RECOVERY_DIR="/sdcard/危险模块恢复"
LOG_FILE="$MODDIR/run.log"
WHITELIST_FILE="$MODDIR/白名单.conf"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

run_detection() {
    MODULE_NAME="$1"
    MODULE_PATH="/data/adb/modules/$MODULE_NAME"

    SH_FILES=$(find "$MODULE_PATH" -type f -name "*.sh" 2>/dev/null | sort)
    SH_COUNT=$(echo "$SH_FILES" | wc -l)

    if [ "$SH_COUNT" -eq 0 ]; then
        log "模块 $MODULE_NAME 无 .sh 文件，判定安全"
        rm -f "$MODULE_PATH/disable" "$MODULE_PATH/loading.log"
        sed -i 's/（等待重启实行检测）//g' "$MODULE_PATH/module.prop"
        return
    fi

    DETECTED=0

    for sh_file in $SH_FILES; do
        [ -f "$MODULE_PATH/disable" ] || touch "$MODULE_PATH/disable"

        /system/bin/sh "$MALWARE_DETECTOR" "$MODULE_NAME" "$sh_file"
        ret=$?
        if [ $ret -eq 1 ]; then
            DETECTED=1
            break
        fi
    done

    if [ $DETECTED -eq 1 ]; then
        log "模块 $MODULE_NAME 存在危险代码，保留禁用"
        sed -i 's/（等待重启实行检测）/（风险模块）/g' "$MODULE_PATH/module.prop"
        rm -f "$MODULE_PATH/loading.log"

        mkdir -p "$RECOVERY_DIR"
        RECOVERY_SCRIPT="$RECOVERY_DIR/enable_${MODULE_NAME}.sh"
        echo "#!/system/bin/sh" > "$RECOVERY_SCRIPT"
        echo "rm -f /data/adb/modules/$MODULE_NAME/disable" >> "$RECOVERY_SCRIPT"
        echo "sed -i 's/（风险模块）//g' /data/adb/modules/$MODULE_NAME/module.prop" >> "$RECOVERY_SCRIPT"
        chmod 755 "$RECOVERY_SCRIPT"
    else
        log "模块 $MODULE_NAME 检查通过，解除禁用"
        rm -f "$MODULE_PATH/disable" "$MODULE_PATH/loading.log"
        sed -i 's/（等待重启实行检测）//g' "$MODULE_PATH/module.prop"
    fi
}

check_pending() {
    for MODULE_PATH in /data/adb/modules/*; do
        [ -d "$MODULE_PATH" ] || continue
        MODULE_NAME=$(basename "$MODULE_PATH")
        [ "$MODULE_NAME" = "${MODDIR##*/}" ] && continue

        WHITELIST_CLEAN=$(tr -d '\r' < "$WHITELIST_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d;/^#/d')
        if echo "$WHITELIST_CLEAN" | grep -Fqx "$MODULE_NAME"; then
            continue
        fi

        [ -f "$MODULE_PATH/loading.log" ] || continue

        log "开始检测模块 $MODULE_NAME"
        run_detection "$MODULE_NAME"
    done
}

if [ "$1" = "check_pending" ]; then
    check_pending
    exit 0
fi