#!/usr/bin/env bash

# use pipefail so that the return value of pipeline commands is not just the right most return value
set -uxo pipefail

# the singlestore user should be 999, change any user that was 999 to something different
# in alma this is currently systemd-coredump
user999=$(id -nu 999)
RESULT_USER=$?

# the singlestore user group should be 998, change any groupid that was 998 to something different
# in alma this is currently rancher
group998=$(getent group 998 | cut -d: -f1)
RESULT_GROUP=$?

# Fail fast.  Fail hard.  Fail often.
set -eu

if [[ "$RESULT_USER" -eq 0 ]]; then
    # make sure there are no files for these users/groups that we are going to change otherwise
    # this is sketchy and we shouldnt proceed
    user_files=$(find / -path /sys -prune -o -path /proc -prune -o -user "${user999}" -print)
    if [[ ! -z "$user_files" ]]; then
        echo "found files of user ${user999}, cannot create singlestore user"
        exit 1
    fi

    usermod -u 1001 "${user999}"
fi

if [[ "$RESULT_GROUP" -eq 0 ]]; then
    group_files=$(find / -path /sys -prune -o -path /proc -prune -o -group "${group998}" -print)
    if [[ ! -z "$group_files" ]]; then
        echo "found files of group ${group998}, cannot create singlestore user"
        exit 1
    fi

    groupmod -g 1001 "${group998}"
fi

groupadd -g 998 singlestore
useradd singlestore -u 999 -g 998
