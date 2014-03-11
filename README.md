rg
==

rg - recursive git - backup cluster


Quick Install
=============

Simply clone this project. Even though it's called rg.git,
I've actually got my working copy in ~/.rg/src .
That's not required, but will help keep related things
together.

          $ mkdir ~/.rg
          $ git clone https://github.com/alexgenaud/rg.git ~/.rg/src

Now, you can run it from the command line with 'dash ~/.rg/src/rg.sh'
add a symlink to a bin directory, or add it to your .bashrc as an alias.
I synchronize the same .bashrc (and related files) between numerous machines,
so I have the following in .bashrc, which helps Cygwin discover a few env vars:


          #
          # rg - recursive git
          #
          if [[ `uname|grep -i CYGWIN|wc -c` -gt 5 ]]; then
            alias rg='export COLUMNS;dash $HOME/.rg/src/rg.sh'
          else
            alias rg='dash $HOME/.rg/src/rg.sh'
          fi



Quick start
=========

This quick start guide should get you up to speed pretty quickly.
But there will still be a bit more you should learn.
However, if the two commands ($) below do not make immediate sense to you,
perhaps rg is not for you. Use at your own risk.

  * Grab an empty USB disk big enough to store all of your git repositories
  * Mount the disk on /media/foo
  * Insert the device name into a .label file at the root of the device:
     * $ echo foo > /media/foo/.label
  * Backup all of your data from /home and other devices to your USB:
     * $ rg  -b  /media/foo


Slow start
=========

Suppose your username is 'zelda' on the host named 'world' and you
have a single small git repository under /home/zelda/Project/legend
that you want to backup to a USB stick. If the commands ($) below
do not make immediate sense to you, perhaps rg is not for you. Use
at your own risk.
  
  * Mount the USB disk on /media/myproj
  * Insert the device name into a .label file at the root of the device:
     * $ echo myproj > /media/myproj/.label
  * Backup your legend project on the USB disk:
     * $ rg  -b  /media/myproj/zelda/Project/legend
  * Continue working and commit:
     * $ echo fix > ~/Project/legend/bugs
     * $ git add ~/Project/legend/bugs; git commit -m fixed
  * Summarize everything and synchronize /home and USB disk:
     * $ rg

You should now see something like:

                  mw   Project/legend       23:0:w > 22:0:m
                  ==   Project/legend       23:0:m,w
                   w   Project/other/stuff  12:34:w

What this is telling you is that Project/legend were found on both
myproj (m) and world (w) but were out of synch.  World was at commit
23 (23:0:w) while myproj was a commit 22 (22:0:m). Both had no
uncommit changes (the :0: in the middle). The second line represents
the synchronization after which, both repositories were at commit
23 and no uncommit changes. The last line shows that world has another
project with 34 changes. 


Background
==========

rg works in most Linux and Cygwin environments. In its most basic mode, rg will simply
list all repositories in /home, /cygdrive/c/Users and external media such as
/media/x, /mnt/y, /cygdrive/z. Rg will also synchronize parallel abstract repositories.


Abstract repo
=============

What's an abstract repository? Glad you asked. Rg considers the following repositories
to be siblings (parallel abstract repos):

                        /home/bob/foo
            /media/superdrive/bob/foo.git
                     /mnt/ext/bob/foo

In the above example, the only abstract repo is 'bob/foo' on three
'devices': /home, /media/superdrive, and /mnt/ext.


Some things to know
===================

rg will store repository details in $HOME/.rg/data

.rg/data will eventually contain a single file for each 'device'.
Each device file will contain a summary of all repositories on that
device. The device name is the hostname for /home and
/cygdrive/c/Users, the label for external usb drives on Linux.

I recommend that you place a '.label' file at the root of any
external media that you wish to synch.  This will guarantee that
the device label will be consistent (some Linux installations don't
automatically create a directory in /media nor does Windows always
support Linux labels).

In Cygwin /home is ignored or is assumed to represent /cygdrive/c/Users
(assuming c is your system drive).  If this makes you uncomfortable,
perhaps you should never synchronize from /home, knowing that /home
will never be synchronized on Cygwin (unless it actually is (symlink)
/cygdrive/c/Users).


Some basic commands
===================

            rg
               (with no arguments) simply summarizes and synchs all devices. With no path,
               this command will search all repositories under all 'devices' and will
               store the resultant summaries in .rg/data.

            rg -l
               (with L flag) lists all devices stored in .rg/data (it may not be up to date)

            rg /some/path
               (with a path but no flags) will summarize and synch all devices, but only
               the subtree

            rg -w /home/bob/foo/bar
               (W flag and a path) this command will summarize and synch all devices based
               on the subtree (all 'bob/foo/bar' and child directories). Any repository
               not found in /home (under /home/bob/foo/bar) will be cloned as a working
               copy from the latest of all found repositories.

            rg -b /media/mydevice/bob/baz
               (B flag and a path) this command will summarize and synch all devices based
               on the subtree (all 'bob/baz' and child directories). Any repository not
               found on /media/mydevice (under bob/baz) will be cloned as a bare repository
               from the latest of all found repositories.
