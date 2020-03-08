# Check whether sysvinit-core is installed.
# In this case enforce one reboot cycle in order to really switch to this init system.

if dpkg -l sysvinit-core | grep -q ^ii; then
    # sysvinit-core is installed: now we need to check, whether it is already active
    # or if another reboot is necessary
    if [ -d /run/systemd/system ]; then
        if [ -z "${ADT_REBOOT_MARK:-}" ]; then
            echo "Rebooting into SysV init ..."
            /tmp/autopkgtest-reboot into-sysv
            exit 0
        else
            # the reboot was executed before - we can assume, that we are running as sysvinit now
            true
        fi
    fi

    # wait for the boot process being finished (all init scripts need to be executed)
    # This should be done by autopkgtest in the future:
    #     https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=953655
    timeout=60
    while ps -ef | grep -q "/etc/init\.d/rc" && [ "$timeout" -gt 0 ]; do
        sleep 1
        timeout=$((timeout - 1))
    done
fi
