while true
do
	(mpc idleloop options player) | while read event
	do
		mpcstatus=`mpc status`

		echo $mpcstatus | egrep -q '\[playing\]'
		isplaying=$?

		echo $mpcstatus | egrep -q '\bsingle: on\b'
		issingle=$?

		if [ $issingle -eq 0 ] && [ $isplaying -eq 0 ]
		then
		    echo 1 > /sys/class/leds/blue\:ph21\:led1/brightness
		else
		    echo 0 > /sys/class/leds/blue\:ph21\:led1/brightness
		fi
	done
	sleep 60
done
