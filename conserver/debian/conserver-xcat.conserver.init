#!/bin/sh
#
# Startup for conserver
#
### BEGIN INIT INFO
# Provides:          conserver
# Required-Start:    $network
# Required-Stop:     
# Should-Start:      
# Default-Start:     2 3 4 5
# Default-Stop:      
# Short-Description: Serial console server daemon/client
# Description:       Conserver is an application that allows multiple users to watch a
#                    serial console at the same time.  It can log the data, allows users to
#                    take write-access of a console (one at a time), and has a variety of
#                    bells and whistles to accentuate that basic functionality.
### END INIT INFO


PATH=/usr/sbin:/usr/bin:/bin:/usr/local/bin
PIDFILE="/var/run/conserver.pid"

signalmaster() {
    sig=$1
    if [ -f "$PIDFILE" ]; then
	master=`cat "$PIDFILE"`
    else
	master=`ps -ef | grep conserver | awk '$3 == "1"{print $2}'`
    fi
    [ "$master" ] && kill -$sig $master
}

case "$1" in
	'start')
		echo "Starting console server daemon"
		conserver -d
		;;

	'stop')
		echo "Stopping console server daemon"
		signalmaster TERM
		;;

	'restart')
		echo "Restarting console server daemon"
		signalmaster HUP
		;;

	*)
		echo "Usage: $0 { start | stop | restart }"
		;;

esac
exit 0
