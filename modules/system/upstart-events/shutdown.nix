{ config, pkgs, ... }:

with pkgs.lib;

{

  jobs.shutdown =
    { name = "shutdown";

      task = true;

      environment = { MODE = "poweroff"; };

      script =
        ''
          set +e # continue in case of errors

          ${pkgs.kbd}/bin/chvt 1
      
          exec < /dev/console > /dev/console 2>&1
          echo ""
          echo "<<< SYSTEM SHUTDOWN >>>"
          echo ""
      
          export PATH=${pkgs.utillinux}/bin:${pkgs.utillinux}/sbin:$PATH
      

          # Set the hardware clock to the system time.
          echo "setting the hardware clock..."
          hwclock --systohc --utc
      
      
          # Do an initial sync just in case.
          sync


          # Stop all Upstart jobs.
          initctl list | while IFS=", " read jobName status rest; do
              if test "$jobName" != shutdown -a "$status" != "stop/waiting"; then
                  echo "stopping $jobName..."
                  stop "$jobName"
              fi
          done
      
      
          # Kill all remaining processes except init and this one.
          echo "sending the TERM signal to all processes..."
          kill -TERM -1
      
          sleep 1 # wait briefly

          echo "sending the KILL signal to all processes..."
          kill -KILL -1


          # If maintenance mode is requested, start a root shell, and
          # afterwards emit the "startup" event to bring everything
          # back up.
          if test "$MODE" = maintenance; then
              echo ""
              echo "<<< MAINTENANCE SHELL >>>"
              echo ""
              while ! ${pkgs.bash}/bin/bash --login; do true; done
              initctl emit startup
              exit 0
          fi
                
      
          # Unmount helper functions.
          getMountPoints() {
              cat /proc/mounts \
              | grep -v '^rootfs' \
              | sed 's|^[^ ]\+ \+\([^ ]\+\).*|\1|' \
              | grep -v '/proc\|/sys\|/dev'
          }
      
          getDevice() {
              local mountPoint=$1
              cat /proc/mounts \
              | grep -v '^rootfs' \
              | grep "^[^ ]\+ \+$mountPoint \+" \
              | sed 's|^\([^ ]\+\).*|\1|'
          }
      
          # Unmount file systems.  We repeat this until no more file systems
          # can be unmounted.  This is to handle loopback devices, file
          # systems  mounted on other file systems and so on.
          tryAgain=1
          while test -n "$tryAgain"; do
              tryAgain=
      
              for mp in $(getMountPoints); do
                  device=$(getDevice $mp)
                  echo "unmounting $mp..."

                  # Note: don't use `umount -f'; it's very buggy.
                  # (For instance, when applied to a bind-mount it
                  # unmounts the target of the bind-mount.)  !!! But
                  # we should use `-f' for NFS.
                  if umount -n "$mp"; then
                      if test "$mp" != /; then tryAgain=1; fi
                  else
                      # `-i' is to workaround a bug in mount.cifs (it
                      # doesn't recognise the `remount' option, and
                      # instead mounts the FS again).
                      mount -n -i -o remount,ro "$mp"
                  fi
      
                  # Hack: work around a bug in mount (mount -o remount on a
                  # loop device forgets the loop=/dev/loopN entry in
                  # /etc/mtab).
                  if echo "$device" | grep -q '/dev/loop'; then
                      echo "removing loop device $device..."
                      losetup -d "$device"
                  fi
              done
          done
      
      
          # Final sync.
          sync
      
      
          # Either reboot or power-off the system.  Note that the "halt"
          # event also does a power-off.
          if test "$MODE" = reboot; then
              echo "rebooting..."
              sleep 1
              exec reboot -f
          else
              echo "powering off..."
              sleep 1
              exec halt -f -p
          fi
        '';
    };

}