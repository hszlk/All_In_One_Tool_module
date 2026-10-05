#!/system/bin/sh
MODDIR=${0%/*}
LOG_FILE="$MODDIR/run.log"
PROCESSED_LIST="$MODDIR/processed_modules.log"
PENDING_LIST="$MODDIR/pending_check.log"
WHITELIST_FILE="$MODDIR/白名单.conf"

if [ -n "$1" ]; then
    MODULE_NAME="$1"
    MODULE_PATH="/data/adb/modules/$MODULE_NAME"

    [ -d "$MODULE_PATH" ] || exit 0

    WHITELIST_CLEAN=$(tr -d '\r' < "$WHITELIST_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d;/^#/d')
    if echo "$WHITELIST_CLEAN" | grep -Fqx "$MODULE_NAME"; then
        exit 0
    fi

    [ -f "$MODULE_PATH/disable" ] && exit 0

    if [ -f "$PROCESSED_LIST" ]; then
        PROCESSED_CLEAN=$(tr -d '\r' < "$PROCESSED_LIST" 2>/dev/null)
        if echo "$PROCESSED_CLEAN" | grep -Fqx "$MODULE_NAME"; then
            exit 0
        fi
    fi

    touch "$MODULE_PATH/disable"
    touch "$MODULE_PATH/loading.log"
    if ! grep -q "（等待重启实行检测）" "$MODULE_PATH/module.prop" 2>/dev/null; then
        sed -i 's/^description=\(.*\)/description=\1（等待重启实行检测）/' "$MODULE_PATH/module.prop"
    fi
    echo "$MODULE_NAME" >> "$PROCESSED_LIST"
    echo "$MODULE_NAME" >> "$PENDING_LIST"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 检测到新模块 $MODULE_NAME，已禁用，等待重启后检测" >> "$LOG_FILE"
    exit 0
fi

ls /data/adb/modules 2>/dev/null | while read MODULE_NAME; do
    [ -z "$MODULE_NAME" ] && continue
    MODULE_PATH="/data/adb/modules/$MODULE_NAME"

    [ "$MODULE_NAME" = "${MODDIR##*/}" ] && continue

    WHITELIST_CLEAN=$(tr -d '\r' < "$WHITELIST_FILE" 2>/dev/null | sed '/^[[:space:]]*$/d;/^#/d')
    if echo "$WHITELIST_CLEAN" | grep -Fqx "$MODULE_NAME"; then
        continue
    fi

    if [ -f "$MODULE_PATH/disable" ]; then
        continue
    fi

    if [ -f "$PROCESSED_LIST" ]; then
        PROCESSED_CLEAN=$(tr -d '\r' < "$PROCESSED_LIST" 2>/dev/null)
        if echo "$PROCESSED_CLEAN" | grep -Fqx "$MODULE_NAME"; then
            continue
        fi
    fi

    touch "$MODULE_PATH/disable"
    touch "$MODULE_PATH/loading.log"
    if ! grep -q "（等待重启实行检测）" "$MODULE_PATH/module.prop" 2>/dev/null; then
        sed -i 's/^description=\(.*\)/description=\1（等待重启实行检测）/' "$MODULE_PATH/module.prop"
    fi
    echo "$MODULE_NAME" >> "$PROCESSED_LIST"
    echo "$MODULE_NAME" >> "$PENDING_LIST"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 检测到新模块 $MODULE_NAME，已禁用，等待重启后检测" >> "$LOG_FILE"
done

exit 0