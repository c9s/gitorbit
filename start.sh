#!/bin/sh
# -D flag avoids executing sshd as a daemon
# -d flag enables the debug mode
echo "Starting ssh daemon..."
/usr/sbin/sshd -D
