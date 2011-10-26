#!/sbin/sh
LOGFILE=/tmp/offmode_tasks.log
OFFMODE_BUTTON_BACKLIGHT=1
OFFMODE_E2FSCK=0

log() {
    echo "$@" >> $LOGFILE
}
log_exec() {
    log "Starting: \`$@\`"
    log "$($@ 2>&1)"
    log "Ended: \`$@\`"
}
do_save_log() {
    CACHE_LOGFILE=/cache/recovery/`basename $LOGFILE`
    CACHE_LAST_LOGFILE=/cache/recovery/last_`basename $LOGFILE`
    if [ -f $CACHE_LOGFILE ]; then
        mv -f $CACHE_LOGFILE $CACHE_LAST_LOGFILE
    else
        rm -rf $CACHE_LOGFILE
    fi
    cp $LOGFILE $CACHE_LOGFILE
}
disable_adb() {
    setprop persist.service.adb.enable 0
    log "ADB disabled."
}
enable_adb() {
    setprop persist.service.adb.enable 1
    log "ADB enabled."
}
set_button_backlight() {
    FILE=/sys/class/leds/button-backlight/brightness
    if [ "$1" ]; then
        echo "$1" > $FILE
        log "$FILE => $1"
    fi
}
do_button_backlight() {
    log ""
    if [ "$1" = 0 ]; then
        set_button_backlight 0
    else
        set_button_backlight $BUTTON_BACKLIGHT_ON
    fi
}
do_check_sdext() {
    if [ "$1" = 1 ]; then
        log ""
        if [ -x "$(which e2fsck)" ]; then
            for MMC_NUM in `seq 0 9`; do
                MMC_TYPE=`cat /sys/block/mmcblk$MMC_NUM/device/type`
                if [ "$MMC_TYPE" = "SD" ]; then
                    SDEXT_BLOCK=/dev/block/mmcblk${MMC_NUM}p2
                    break
                fi
            done
            if [ -b "$SDEXT_BLOCK" ]; then
                disable_adb
                log_exec e2fsck -vfy $SDEXT_BLOCK
                enable_adb
            else
                log "Fail to find any SD-Ext partition."
            fi
        else
            log "e2fsck not found or not executable."
        fi
    fi
}

# Main
[ -z "$BUTTON_BACKLIGHT_ON" ] && BUTTON_BACKLIGHT_ON=200
[ -z "$OFFMODE_VSZ_OFF" ] && OFFMODE_VSZ_OFF=444
while [ $# -gt 0 ]; do
    case "$1" in
        --button-backlight-on)
            if [ "$2" ]; then
                shift
                BUTTON_BACKLIGHT_ON=$1
            else
                log "Expecting another argument after $1"
            fi
            ;;
        --offmode-vsz-off)
            if [ "$2" ]; then
                shift
                OFFMODE_VSZ_OFF=$1
            else
                log "Expecting another argument after $1"
            fi
            ;;
        *)
            log "Unknown argument: $1"
            ;;
    esac
    shift
done
if [ -n "$(ps | grep $OFFMODE_VSZ_OFF' S */sbin/offmode_charging')" ]; then
    until [ "$(mount | grep $ANDROID_DATA)" ] || [ -e /etc/fstab ]; do
        sleep 1
    done
    MOUNTED=`mount | grep $ANDROID_DATA`
    if [ "$MOUNTED" ] || mount $ANDROID_DATA; then
        for PROP in $(find $ANDROID_DATA/property/ -type f -name persist.recovery.*); do
            KEY=`basename $PROP`
            VAL=`cat $PROP`
            case "$KEY" in
                persist.recovery.offmode.button-backlight)
                    OFFMODE_BUTTON_BACKLIGHT="$VAL"
                    ;;
                persist.recovery.offmode.e2fsck)
                    OFFMODE_E2FSCK="$VAL"
                    ;;
            esac
            log "$KEY=$VAL"
            #setprop "$KEY" "$VAL"
        done
        [ "$MOUNTED" ] || umount $ANDROID_DATA
    fi
    do_check_sdext "$OFFMODE_E2FSCK"
    do_button_backlight 0
    sleep 1
    do_button_backlight "$OFFMODE_BUTTON_BACKLIGHT"
fi
do_save_log
