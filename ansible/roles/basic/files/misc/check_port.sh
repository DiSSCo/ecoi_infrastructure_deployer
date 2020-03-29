#!/bin/bash
PORT=$1
TRIES=$2
WAIT=$3

while /bin/netstat -an | /bin/grep \:$PORT | /bin/grep LISTEN ; [ $? -ne 0 ]; do
   let TRIES-=1
   if [ $TRIES -gt 0 ];
   then
      sleep $WAIT
   else
      break
   fi
done

if [ $TRIES -gt 0 ];
then
   exit 0
else
  exit 1
fi