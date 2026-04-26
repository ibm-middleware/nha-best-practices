#!/bin/bash
#
# Restructured from mqsc-watcher to interactively run all mqsc
# in the /mq-config directory.
#
#Syntax:
#  apply-mqsc.sh [no options available yet]
#set -eu       # Not for interactive since mqsc often fails for valid reasons
#echo "Watcher script running..."
cfgpath="/mq-config"
for f in $(ls ${cfgpath}/*.mqsc); do runmqsc < ${f}; done
