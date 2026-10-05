#!/system/bin/sh
MODDIR=${0%/*}
BUSYBOX=/data/adb/magisk/busybox
export PATH=/system/bin:/data/adb/magisk:$PATH

USER_CONFIG="$MODDIR/user_config.prop"

get_prop() {
    local key="$1"
    local def="$2"
    if [ -f "$USER_CONFIG" ]; then
        local v=$(grep "^${key}=" "$USER_CONFIG" 2>/dev/null | tail -1 | cut -d= -f2-)
        [ -n "$v" ] && echo "$v" && return
    fi
    echo "$def"
}

DOZE_MODE=$(get_prop "power.doze.mode" "force")
FREQ_MODE=$(get_prop "power.freq.mode" "intelligent")
SELECTED_FREQ=$(get_prop "power.freq.selected" "0")
FREQ_LEVELS=$(get_prop "power.freq.levels" "")
GPU_UNLOCK=$(get_prop "power.gpu.unlock.enabled" "false")

set_cpu_max_freq() {
    local freq=$1
    [ -z "$freq" ] && return
    [ "$freq" = "0" ] && return

    local old_enforce=$(getenforce 2>/dev/null)
    setenforce 0 2>/dev/null

    for cpu in /sys/devices/system/cpu/cpu[0-3]; do
        if [ -f "$cpu/cpufreq/scaling_max_freq" ]; then
            echo "$freq" > "$cpu/cpufreq/scaling_max_freq" 2>/dev/null
        fi
    done

    [ "$old_enforce" = "Enforcing" ] && setenforce 1 2>/dev/null
}

clean_and_set_whitelist() {
    local user_wl=$(get_prop "power.doze.whitelist" "")

    for pkg in $(dumpsys deviceidle whitelist | grep -oE 'com\.[a-zA-Z0-9._]+' | sort -u); do
        dumpsys deviceidle whitelist -$pkg >/dev/null 2>&1
    done

    dumpsys deviceidle whitelist +com.firewall_aio.hszlk >/dev/null 2>&1

    if [ -n "$user_wl" ]; then
        local old_ifs="$IFS"
        IFS=','
        set -- $user_wl
        IFS="$old_ifs"
        for pkg in "$@"; do
            pkg=$(echo "$pkg" | tr -d ' ')
            [ -z "$pkg" ] && continue
            dumpsys deviceidle whitelist +$pkg >/dev/null 2>&1
        done
    fi
}

adjust_cpu_freq_intelligent() {
    [ -z "$FREQ_LEVELS" ] && return

    local old_ifs="$IFS"
    IFS=','
    set -- $FREQ_LEVELS
    IFS="$old_ifs"

    local count=$#
    [ "$count" -eq 0 ] && return

    if [ "$screen_state" = "false" ]; then
        local lowest=$1
        [ -n "$lowest" ] && set_cpu_max_freq "$lowest"
        return
    fi

    local load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    [ -z "$load" ] && return

    $BUSYBOX awk -v l="$load" 'BEGIN {
        if (l < 0.8) exit 0;
        else if (l < 1.8) exit 1;
        else if (l < 3.0) exit 2;
        else exit 3;
    }'
    local level=$?

    local idx
    case $level in
        0) idx=1 ;;
        1) idx=$(( (count + 2) / 3 )) ;;
        2) idx=$(( (count * 2 + 2) / 3 )) ;;
        3) idx=$count ;;
        *) idx=1 ;;
    esac
    [ "$idx" -lt 1 ] && idx=1
    [ "$idx" -gt "$count" ] && idx=$count

    local i=1
    local target=""
    for f in "$@"; do
        if [ "$i" -eq "$idx" ]; then
            target="$f"
            break
        fi
        i=$((i + 1))
    done

    [ -n "$target" ] && set_cpu_max_freq "$target"
}

GPU_DEVFREQ="/sys/class/kgsl/kgsl-3d0/devfreq"
GPU_FREQ_MAX=1010000000

adjust_gpu_freq() {
    [ "$SDK_VERSION" -ge 30 ] || return
    [ "$GPU_UNLOCK" = "true" ] || return
    [ -d "$GPU_DEVFREQ" ] || return
    echo userspace > "$GPU_DEVFREQ/governor" 2>/dev/null
    echo "$GPU_FREQ_MAX" > "$GPU_DEVFREQ/max_freq" 2>/dev/null
    echo "$GPU_FREQ_MAX" > "$GPU_DEVFREQ/min_freq" 2>/dev/null
}

BG_STATE_FILE="$MODDIR/.bg_sh_state"
BG_LIST_FILE="$MODDIR/.bg_sh_list"

manage_bg_sh() {
    local screen="$1"
    local prev_state=""
    [ -f "$BG_STATE_FILE" ] && prev_state=$(cat "$BG_STATE_FILE" 2>/dev/null)

    if [ -z "$prev_state" ]; then
        if [ "$screen" = "false" ]; then
            echo "off" > "$BG_STATE_FILE"
        else
            echo "on" > "$BG_STATE_FILE"
        fi
        return
    fi

    local self_pid=$$

    if [ "$screen" = "false" ] && [ "$prev_state" != "off" ]; then
        : > "$BG_LIST_FILE"

        for p in /proc/[0-9]*; do
            local pid=${p#/proc/}
            [ "$pid" = "$self_pid" ] && continue

            local cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
            [ -z "$cmd" ] && continue

            case "$cmd" in
                /system/bin/sh\ *) ;;
                *) continue ;;
            esac

            local rest=${cmd#/system/bin/sh }
            [ -z "$rest" ] && continue

            local first=$(echo "$rest" | awk '{print $1}')
            case "$first" in
                /*)
                    [ -f "$first" ] || continue
                    ;;
                *)
                    continue
                    ;;
            esac

            case "$first" in
                /system/*|/vendor/*|/system_ext/*|/product/*|/apex/*) continue ;;
            esac

            case "$first" in
                */power_save.sh) continue ;;
                */Automatic_brick_rescue.sh) continue ;;
                */post-fs-data.sh) continue ;;
                */service.sh) continue ;;
            esac

            echo "$first" >> "$BG_LIST_FILE"
            for cpid in $(pgrep -P "$pid" 2>/dev/null); do
                kill -9 "$cpid" 2>/dev/null
            done
            kill -9 "$pid" 2>/dev/null
        done

        echo "off" > "$BG_STATE_FILE"

    elif [ "$screen" != "false" ] && [ "$prev_state" = "off" ]; then
        if [ -f "$BG_LIST_FILE" ]; then
            while IFS= read -r path; do
                [ -z "$path" ] && continue
                [ -f "$path" ] || continue
                nohup /system/bin/sh "$path" >/dev/null 2>&1 &
            done < "$BG_LIST_FILE"
        fi

        echo "on" > "$BG_STATE_FILE"
    fi
}

SDK_VERSION=$(getprop ro.build.version.sdk 2>/dev/null)
[ -z "$SDK_VERSION" ] && SDK_VERSION=0

screen_state=$(dumpsys deviceidle get screen)

manage_bg_sh "$screen_state"

case "$DOZE_MODE" in
    smart)
        if [ "$screen_state" = "false" ]; then
            clean_and_set_whitelist
            dumpsys deviceidle enable deep
            dumpsys deviceidle force-idle
        else
            dumpsys deviceidle unforce
        fi
        ;;
    force)
        clean_and_set_whitelist
        dumpsys deviceidle enable deep
        dumpsys deviceidle force-idle
        ;;
esac

case "$FREQ_MODE" in
    intelligent)
        adjust_cpu_freq_intelligent
        ;;
    fixed)
        set_cpu_max_freq "$SELECTED_FREQ"
        ;;
esac

adjust_gpu_freq