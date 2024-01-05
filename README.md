# vscode-reaper

This Perl script, when run as root, will clean up user server-side VSCode processes when they have no sshd running.  It is tuned for our particular systems (ignoring specific system users, only reaping processes on certain forms of username, counting a handful of non-VSCode processes as VSCode for reaping purposes)  The tuning is hard-coded.  You will almost certainly need to alter the code to use it on your systems.

The script is written to be conservative about what processes get reaped.  You will likely need to log in and run it by hand every now and again to see what it's not reaping, and check those.  It's been educational to see what else our users leave behind...
