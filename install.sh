#!/system/bin/sh
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=true
LATESTARTSERVICE=true

print_modname() {
  ui_print "*******************************"
  ui_print " aio系统优化"
  ui_print "   by hszlk"
  ui_print "*******************************"
}

on_install() {
  ui_print "- 解压模块文件"
  unzip -o "$ZIPFILE" 'module.prop' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'post-fs-data.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'service.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'uninstall.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'Automatic_brick_rescue.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'Automatic_brick_rescue2.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'boot_monitor.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'battery_info.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" 'power_save.sh' -d $MODPATH >&2
  unzip -o "$ZIPFILE" '7za' -d $MODPATH >&2 2>/dev/null
  unzip -o "$ZIPFILE" 'sys/*' -d $MODPATH >&2 2>/dev/null
  unzip -o "$ZIPFILE" 'app/*' -d $MODPATH >&2 2>/dev/null
  unzip -o "$ZIPFILE" 'webview.zip' -d $MODPATH >&2 2>/dev/null
  unzip -o "$ZIPFILE" 'config_webview_packages.xml' -d $MODPATH >&2 2>/dev/null

  ui_print "- 解压白名单文件"
  unzip -o "$ZIPFILE" '*.conf' -d $MODPATH >&2 2>/dev/null

  SDK=$(getprop ro.build.version.sdk)
  echo "$SDK" > "$MODPATH/sdk_version.txt"
  ui_print "  SDK: $SDK"

  ui_print "- 读取 CPU 频率列表"
  CPU_FREQS=""
  for i in 0 1 2 3 4 5 6 7; do
    F="/sys/devices/system/cpu/cpu$i/cpufreq/scaling_available_frequencies"
    if [ -f "$F" ]; then
      CPU_FREQS=$(cat "$F" 2>/dev/null)
      [ -n "$CPU_FREQS" ] && break
    fi
  done
if [ -z "$CPU_FREQS" ]; then
  ui_print "  警告：未读取到 CPU 频率，将留空"
  CPU_FREQS_CSV=""
else
  CPU_FREQS_CSV=$(echo "$CPU_FREQS" | tr ' ' ',' | sed 's/,$//')
fi
  CPU_FREQS_CSV=$(echo "$CPU_FREQS" | tr ' ' ',' | sed 's/,$//')

  USER_CONFIG="$MODPATH/user_config.prop"
  if [ -f "$USER_CONFIG" ]; then
    if ! grep -q "^power.freq.levels=" "$USER_CONFIG" 2>/dev/null; then
      echo "power.freq.levels=$CPU_FREQS_CSV" >> "$USER_CONFIG"
    else
      sed -i "s|^power.freq.levels=.*|power.freq.levels=$CPU_FREQS_CSV|" "$USER_CONFIG"
    fi
  else
    echo "power.freq.levels=$CPU_FREQS_CSV" > "$USER_CONFIG"
  fi
  ui_print "  CPU 频率: $CPU_FREQS_CSV"

  if [ "$SDK" -lt 30 ]; then
    ui_print "- 安装 rm 拦截器（SDK $SDK < 30）"
    unzip -o "$ZIPFILE" 'system/bin/rm' -d $MODPATH >&2 2>/dev/null
    unzip -o "$ZIPFILE" 'system/bin/command_checker.sh' -d $MODPATH >&2 2>/dev/null

    for wrapper in "$MODPATH/system/bin/rm" "$MODPATH/system/bin/command_checker.sh"; do
      if [ -f "$wrapper" ]; then
        tr -d '\r' < "$wrapper" > "$wrapper.tmp" 2>/dev/null && mv "$wrapper.tmp" "$wrapper"
      fi
    done
    ui_print "  拦截器换行符已修复"
  else
    ui_print "- SDK $SDK >= 30，跳过 rm 拦截器"
  fi

  ui_print "- 备份 framework-res.apk"
  if [ -f "/system/framework/framework-res.apk" ]; then
    cp -f "/system/framework/framework-res.apk" "$MODPATH/framework-res.apk.bak" 2>/dev/null
    if [ $? -eq 0 ]; then
      ui_print "  备份成功"
    else
      ui_print "  备份失败"
    fi
  else
    ui_print "  源文件不存在，跳过备份"
  fi

  ui_print "- 读取当前默认桌面"
  DEFAULT_LAUNCHER=""
  if command -v cmd >/dev/null 2>&1; then
    DEFAULT_LAUNCHER=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1)
  fi
  if [ -z "$DEFAULT_LAUNCHER" ]; then
    DEFAULT_LAUNCHER=$(pm resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -1)
  fi
  if [ -n "$DEFAULT_LAUNCHER" ]; then
    echo "$DEFAULT_LAUNCHER" > "$MODPATH/default_launcher.txt"
    ui_print "  默认桌面: $DEFAULT_LAUNCHER"
  else
    ui_print "  警告：未读取到默认桌面"
  fi

  ui_print "- 备份默认桌面相关文件到 backup/"
  BACKUP_DIR="$MODPATH/backup"
  mkdir -p "$BACKUP_DIR/data_app" "$BACKUP_DIR/system_app" "$BACKUP_DIR/data_user"

  DATA_APP_FULL=$(pm path com.xtc.i3launcher 2>/dev/null | grep "/data/app/" | sed 's/package://' | head -1)
  if [ -n "$DATA_APP_FULL" ]; then
    DATA_APP_DIR=$(dirname "$DATA_APP_FULL")
    DATA_APP_NAME=$(basename "$DATA_APP_DIR")
    echo "$DATA_APP_NAME" > "$BACKUP_DIR/data_app_name.txt"
    rm -rf "$BACKUP_DIR/data_app/$DATA_APP_NAME"
    cp -a "$DATA_APP_DIR" "$BACKUP_DIR/data_app/" 2>/dev/null
    if [ -d "$BACKUP_DIR/data_app/$DATA_APP_NAME" ]; then
      ui_print "  /data/app/$DATA_APP_NAME 备份完成"
    else
      ui_print "  /data/app 备份失败"
    fi
  else
    ui_print "  /data/app 未找到 com.xtc.i3launcher"
  fi

  if [ -d "/system/app/XTCLauncher" ]; then
    rm -rf "$BACKUP_DIR/system_app/XTCLauncher"
    cp -a "/system/app/XTCLauncher" "$BACKUP_DIR/system_app/" 2>/dev/null
    if [ -d "$BACKUP_DIR/system_app/XTCLauncher" ]; then
      ui_print "  /system/app/XTCLauncher 备份完成"
    else
      ui_print "  /system/app/XTCLauncher 备份失败"
    fi
  else
    ui_print "  /system/app/XTCLauncher 不存在"
  fi

  if [ -d "/data/user/0/com.xtc.i3launcher" ]; then
    rm -rf "$BACKUP_DIR/data_user/com.xtc.i3launcher"
    cp -a "/data/user/0/com.xtc.i3launcher" "$BACKUP_DIR/data_user/" 2>/dev/null
    if [ -d "$BACKUP_DIR/data_user/com.xtc.i3launcher" ]; then
      ui_print "  /data/user/0/com.xtc.i3launcher 备份完成"
    else
      ui_print "  /data/user/0 备份失败"
    fi
  else
    ui_print "  /data/user/0/com.xtc.i3launcher 不存在"
  fi

  ui_print "- 检测 WebView 内核"
  WEBVIEW_PKG=$(dumpsys webviewupdate 2>/dev/null | grep -i "Current WebView package" | grep -oE 'com\.[a-zA-Z0-9._]+' | head -1)
  ui_print "  当前 WebView: $WEBVIEW_PKG"

  mkdir -p "$MODPATH/system/framework"
  rm -f "$MODPATH/system/framework/framework-res.apk"

  SEVEN_ZA=""
  [ -f "$MODPATH/7za" ] && SEVEN_ZA="$MODPATH/7za"
  [ -n "$SEVEN_ZA" ] && chmod 755 "$SEVEN_ZA"

  case "$WEBVIEW_PKG" in
    *google*)
      ui_print "  已是谷歌内核，直接提取 framework-res.apk"
      cp -f /system/framework/framework-res.apk "$MODPATH/system/framework/framework-res.apk"
      ;;
    *)
      ui_print "  非谷歌内核，注入 config_webview_packages.xml"
      if [ ! -f "$MODPATH/config_webview_packages.xml" ]; then
        ui_print "  警告：未找到 config_webview_packages.xml，使用原版"
        cp -f /system/framework/framework-res.apk "$MODPATH/system/framework/framework-res.apk"
      elif [ ! -f "$SEVEN_ZA" ]; then
        ui_print "  警告：未找到 7za，使用原版"
        cp -f /system/framework/framework-res.apk "$MODPATH/system/framework/framework-res.apk"
      else
        TMP=/data/local/tmp/webview_inject
        rm -rf "$TMP"
        mkdir -p "$TMP/framework"

        cp -f /system/framework/framework-res.apk "$TMP/framework-res.apk"

        cd "$TMP/framework" || {
          ui_print "  切换目录失败，使用原版"
          cp -f "$TMP/framework-res.apk" "$MODPATH/system/framework/framework-res.apk"
          rm -rf "$TMP"
          return
        }

        "$SEVEN_ZA" x ../framework-res.apk -y >/dev/null 2>&1

        if [ -d "res/xml" ]; then
          cp -f "$MODPATH/config_webview_packages.xml" res/xml/config_webview_packages.xml

          cd "$TMP" || {
            ui_print "  回到上层失败，使用原版"
            cp -f "$TMP/framework-res.apk" "$MODPATH/system/framework/framework-res.apk"
            rm -rf "$TMP"
            return
          }

          "$SEVEN_ZA" a -tzip framework-res-new.apk ./framework/* >/dev/null 2>&1

          if [ $? -eq 0 ] && [ -f "$TMP/framework-res-new.apk" ]; then
            mv -f "$TMP/framework-res-new.apk" "$MODPATH/system/framework/framework-res.apk"
            ui_print "  framework-res.apk 注入完成"
          else
            ui_print "  打包失败，使用原版"
            cp -f "$TMP/framework-res.apk" "$MODPATH/system/framework/framework-res.apk"
          fi
        else
          ui_print "  解包失败，使用原版"
          cp -f "$TMP/framework-res.apk" "$MODPATH/system/framework/framework-res.apk"
        fi

        rm -rf "$TMP"
      fi
      ;;
  esac

  if [ -f "$MODPATH/system/framework/framework-res.apk" ]; then
    chmod 644 "$MODPATH/system/framework/framework-res.apk"
  fi

  ui_print "- 解压 webview.zip"
  if [ -f "$MODPATH/webview.zip" ]; then
    mkdir -p "$MODPATH/system/app"
    unzip -o "$MODPATH/webview.zip" -d "$MODPATH/system/app" >&2 2>/dev/null
    rm -f "$MODPATH/webview.zip"
    ui_print "  已解压到 system/app"
  else
    ui_print "  未找到 webview.zip，跳过"
  fi

  unzip -o "$ZIPFILE" 'module.apk' -d $MODPATH >&2 2>/dev/null
  if [ -f "$MODPATH/module.apk" ]; then
    ui_print "- 安装配套 APK"
    pm install -r --user 0 "$MODPATH/module.apk" 2>/dev/null
    if [ $? -eq 0 ]; then
      ui_print "  module.apk 安装成功"
    else
      ui_print "  module.apk 安装失败，请手动安装"
    fi
  else
    ui_print "- 未找到 module.apk，跳过安装"
  fi

  ui_print "- 修复所有 .sh 文件换行符"
  find "$MODPATH" -type f -name "*.sh" | while read f; do
    tr -d '\r' < "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
  done
  ui_print "  修复完成"
}

set_permissions() {
  set_perm_recursive $MODPATH 0 0 0755 0644
  find $MODPATH -type f -name "*.sh" -exec chmod 0755 {} \;
  chmod 0755 "$MODPATH/7za" 2>/dev/null
  find $MODPATH/sys -type f -exec chmod 0755 {} \; 2>/dev/null
  chmod 0755 "$MODPATH/system/bin/rm" 2>/dev/null
  chmod 0755 "$MODPATH/system/bin/command_checker.sh" 2>/dev/null
}