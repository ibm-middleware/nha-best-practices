#!/bin/bash
#
# Show qdepth
#
# Reference utility script
#
echo -e "$(date) \nDEPTH QUEUE";echo "dis ql(*) curdepth" |runmqsc |grep "(" |tr -s '[:space:]' '\n'|egrep '*QUEUE|*CURDEPTH'|tr -d '\n' |sed -E 's/QUEUE\(/\(\n/g' |awk -F'[()]' '{printf "%-5s %-50s\n",$3,$1}' |grep -v ^0
echo
