mkfifo /root/datv/longmynd_main_status
killall -9 longmynd && killall -9 pluto_dvb && killall mnc && killall -9 datv_relay

/root/datv/longmynd -i 230.0.0.1 10000 -M 127.0.0.1 1000 747750 333 >/dev/null 2>/dev/null &
/root/mnc -l -p 10000 230.0.0.1 | /root/datv/pluto_dvb -T 0 -t 1252e6 -s 2e6 -m DVBS2 &
/root/datv/datv_relay &
