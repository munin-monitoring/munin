# install sysvinit-core and reboot
#
# Include this snippet in any test requiring sysvinit.
#
# This allows tests of the System-V init scripts.
# Simple prepend your test command with this script name.
#
# Sadly it is not possible to simply specify "sysvinit-core" as a testbed dependency, since this
# involves a confirmation request during installation. Autopkgtest currently does not handle that.
#
# NOTE: this only works with full system virtualization (e.g. qemu)
#

set -eu


# taken from: systemd-shim tests
# https://sources.debian.org/src/systemd-shim/10-3/debian/tests/lifecycle
if [ -d /run/systemd/system ]; then
  if [ ! -x /tmp/autopkgtest-reboot ]; then
    echo "SKIP: testbed does not support reboot"
    exit 0
  fi
  if [ -n "${ADT_REBOOT_MARK:-}" ]; then
    echo "SKIP: Reboot with sysvinit-core still runs systemd; using init= ?"
    exit 0
  fi
  echo "Installing sysvinit-core..."
  # stderr: silence message "delaying package configuration" (due to missing apt-utils)
  apt-get install -y sysvinit-core 2>/dev/null
  echo "Rebooting into SysV init..."
  /tmp/autopkgtest-reboot into-sysv
fi
