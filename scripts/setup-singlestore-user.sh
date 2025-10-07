#!/usr/bin/env bash

# use pipefail so that the return value of pipeline commands is not just the right most return value
set -uo pipefail

# the singlestore user should be 999, change any user that was 999 to something different
# in alma this is currently systemd-coredump
user_memsql=$(id -nu 998)
RESULT_USER=$?

# the singlestore user group should be 998, change any groupid that was 998 to something different
# in alma this is currently rancher
group_memsql=$(getent group 998 | cut -d: -f1)
RESULT_GROUP=$?

# Fail fast.  Fail hard.  Fail often.
set -eu

groupadd -g 1999 singlestore
useradd singlestore -u 1999 -g 1999
