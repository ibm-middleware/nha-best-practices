#!/bin/bash
#
# Match AMQ errors with the time it happened
#
# Reference utility script
#
qmgr=$(dspmq |awk -F'[()]' '{print $2}')
egrep '^[0-9]{2}/[0-9]{2}/[0-9]{2}|^AMQ' /var/mqm/qmgrs/${qmgr}/errors/AMQERR01.LOG |grep -B 1 ^AMQ |awk '/AMQ/ { printf " %s", $0; next} {if (NR>1) printf "\n"; printf "%s", $0}'
echo
