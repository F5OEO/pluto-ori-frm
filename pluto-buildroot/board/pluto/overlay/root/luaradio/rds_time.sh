#!/bin/sh
filename='/tmp/toto.txt'
rm $filename
rm /tmp/pid.luaradio
sleep 1
cd /root/luaradio
echo " --> waiting for RDS timesync..."
#eval 'timeout -t 130 /root/luaradio/luaradio /root/luaradio/rds_plutosdr.lua $1 ' 
# echo $! >/tmp/pid.luaradio
sleep 2
rm /tmp/date.txt
touch /tmp/date.txt
#tail -f $filename |
#cat $filename  |
/root/luaradio/luaradio /root/luaradio/rds_pluto.lua $1 2>/dev/null | 
while read line
do
     # do what ever it does 
echo $line | grep 'group_code\":4' >> /tmp/date.txt
#echo $line | grep 'group_code'
#done
#hh=$(jq -r '.data.time.hour | select(. != null) ' /tmp/date.txt | tail -n1)
#echo 'HH $hh'

if [[ -f /tmp/date.txt && -s /tmp/date.txt ]]
	then
		break
	fi

done

MM1=$(jq -r '.data.date.month | select(. != null) ' /tmp/date.txt | tail -n1 )
DD1=$(jq -r '.data.date.day | select(. != null) ' /tmp/date.txt | tail -n1)
YYYY=$(jq -r '.data.date.year | select(. != null) ' /tmp/date.txt | tail -n1)
mm1=$(jq -r '.data.time.minute | select(. != null) ' /tmp/date.txt | tail -n1)
hh1=$(jq -r '.data.time.hour | select(. != null) ' /tmp/date.txt | tail -n1)
mm=$(printf "%02d" $mm1)
DD=$(printf "%02d" $DD1)
MM=$(printf "%02d" $MM1)
hh=$(printf "%02d" $hh1)
timezone=$(jq -r '.data.time.offset | select(. != null) ' /tmp/date.txt )
#timezone=$(jq -r '.data.time.offset ' /tmp/toto.txt )
#echo ============================================
printf "\n======  RDS Time ======\n*** Date : %02d/%02d/%04d \n" "$DD" "$MM" "$YYYY" 
printf "*** UTC Time : %02d:%02d UTC \n"  "$hh" "$mm" 
printf "*** TZ offset : %d hours\n"   "$timezone"

echo $YYYY/$MM/$DD
echo "$hh:$mm UTC - offset : $timezone hours"
#killall -9 luajit
#disown $(cat /tmp/pid.luaradio)
#kill -9 $(cat /tmp/pid.luaradio)  2>/dev/null
echo "Set time :"

#sudo date -s $YYYY-$MM-$DDT$hh:$mm:00Z
#sudo date +%T%Z -s 07:00:01UTC
date   -s "${YYYY}-${MM}-${DD} ${hh}:${mm}:04"
#sudo date -s  $YYYY/$MM/$DD
#date -s '$YYYY/$MM/$DD ${hh}:${mm}:04'
sleep 20

