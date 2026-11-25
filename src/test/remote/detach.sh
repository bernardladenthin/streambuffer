#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2014-2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Machine side (README.md here): starts a command so that it outlives the ssh session and the
# ssh call returns at once. The command runs in a session of its own (setsid, so a hang-up of the
# ssh session reaches nothing of it), ignores SIGHUP (nohup), and every one of its file
# descriptors goes to the log or /dev/null: an ssh call returns only when no process holds its
# output any more, so a background job started as `cd x && cmd &` keeps the call open for as long
# as it runs (the subshell around it still holds ssh's stdout).
#
# Usage: detach.sh <log file> <command> [args...]   e.g. over ssh:
#   ssh <host> '<payload>/sb/src/test/remote/detach.sh <payload>/out/a18.out <payload>/sb/src/test/remote/run-a18.sh'
set -eu
log="$1"
shift
mkdir -p "$(dirname "$log")"
setsid nohup "$@" > "$log" 2>&1 < /dev/null &
echo "started pid $! ($*), log $log"
