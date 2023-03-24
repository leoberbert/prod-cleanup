# prod-cleanup
Script to perform file compression and deletion on Linux systems.

**Prerequisites:**

Have the xz package installed.

```
perl prod-cleanup.pl
prod-cleanup :2403 112414:E:Usage: prod-cleanup [-n|-N] [-z <zdays>] [-m mdays (-t <path>|-a <archivetype>)] [-d <days>] [-p <pattern>]... [-x <exclude>] dir1...
prod-cleanup :2403 112414:I:   -n              fake - do not execute any gzip, rm or move
prod-cleanup :2403 112414:I:   -N              fake deletion - do not execute any rm or move
prod-cleanup :2403 112414:I:   -z <zdays>      days before compressing (default: no compression)
prod-cleanup :2403 112414:I:   -d <days>       days before deletion (default: 42)
prod-cleanup :2403 112414:I:   -p <pattern>    shell pattern to match files against (default: *.old)
prod-cleanup :2403 112414:I:   -x <exclude>    shell pattern of files to exclude (default: none)
prod-cleanup :2403 112414:I:   dirN            Nth directory to scan in
prod-cleanup :2403 112414:P:Check arguments.
```
** Example: **

Compress:

```
perl prod-cleanup.pl -z 0 -p *.log_* /var/log
```

Deletion:

```
perl prod-cleanup.pl -d 2 -p *.xz*
```
