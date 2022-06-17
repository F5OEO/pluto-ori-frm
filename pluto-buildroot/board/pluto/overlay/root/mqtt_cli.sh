#!/bin/sh


key=$(cat /sys/kernel/config/usb_gadget/composite_gadget/strings/0x409/serialnumber)
dt_root="dt/pluto/$key"
cmd_root="cmd/pluto/$key"

function get_status () {

cd /sys/bus/iio/devices/iio\:device0

	echo "     ****** RX ******"
	echo "Freq       : " $(cat out_altvoltage0_RX_LO_frequency)
	echo "ADCSamplerate : " $(cat out_altvoltage0_RX_LO_frequency)
	echo "FinalSR : " $(mosquitto_sub -t $dt_root/rx/finalsr -C 1 -W 2)
	echo "RXFORMAT : " $(mosquitto_sub -t $dt_root/rx/format -C 1 -W 2)
	echo "BW         : " $(cat in_voltage_rf_bandwidth)
	echo "Gain       : " $(cat in_voltage0_hardwaregain) " ("$(cat in_voltage0_gain_control_mode)" mode)"
	echo "RSSI       : " $(cat in_voltage0_rssi)
	echo
	echo 
	echo "     ****** TX ******"
        echo "Freq       : " $(cat out_altvoltage1_TX_LO_frequency)
        echo "Samplerate : " $(cat out_voltage_sampling_frequency)
        echo "BW         : " $(cat out_voltage_rf_bandwidth)
        echo "Att.       : " $(cat out_voltage0_hardwaregain)
	echo
	echo
#echo $status
#reset
}



function display_cmds () {
echo "
*** ADALM-Pluto remote control
*** LamaBleu 05/2019

   Pluto listener commands :
   -----------------------

F 123456789  : set frequency (RX/TX)
BW : set Bandwidth (RX/TX)
RXSR : set Samplerate RX
TXSR : set Samplerate TX
TXF : set TX frequency
TXBW : set TX bandwidth
TXGAIN [-89:0] : set TX attenuation ( 0 = max power)
RXF : set RX frequency
RXBW : set RX bandwidth
RXGAIN [0-73]: set RX gain
RXO [0-2]: Format 0=CS16,1=CS8,2=cs16+fft
S : display status
H : display commands list
X or Q : disconnect
KK : disconnect and KILL server
SF : Sweepfft Frequency
SS : SweepfftSpan
"

}

display_cmds
get_status


#while true; do

while :
do
command=""
freq=""
pluto_com=""
arg1=""
power=""
mode=""

echo -n "Command : "
read pluto_com
reset
command=$(echo $pluto_com | awk '{print $1}')
arg1=$(echo $pluto_com | awk '{print $2}')
#arg1=${arg1//[![:digit:]]}
#echo $command

echo
case $command in
	F) echo "    **** set Frequency $arg1"
		if [ -z "$arg1" ]; then echo "**** noarg !"; fi
		echo $arg1
		echo
        $(mosquitto_pub -t $cmd_root/rx/frequency -m $arg1)
		get_status;
		;;
	[XxQq]) echo "       **** DISCONNECT "
		echo "       Goodbye. "
		exit 0;
		;;
	[Ss]) get_status;
		;;
	[Hh]) display_cmds;
		;;
	KK) echo "Disconnect and kill server - Goodbye forever !"
		sudo killall socat
		exit 0;
		;;
	BW ) if [ -z "$arg1" ]; then echo "**** noarg !"; fi
		echo "    **** set TX/RX Bandwidth $arg1 "
		echo
		iio_attr -q -c ad9361-phy voltage0 rf_bandwidth $((arg1)) 1>/dev/null
		get_status;
		;;
	TXF ) echo "    **** set TX Frequency $arg1"
		if [ -z "$arg1" ]; then echo "**** noarg !"; fi
		echo
		$(mosquitto_pub -t $cmd_root/tx/frequency -m $arg1)
		get_status;
		;;
	TXBW ) if [ -z "$arg1" ]; then echo "**** noarg !"; fi
		echo "    **** set TX Bandwidth $arg1 "
		echo
		iio_attr -q -c -o ad9361-phy voltage0 rf_bandwidth $((arg1)) 1>/dev/null
		get_status;
		;;
	TXGAIN ) echo "    **** set TX attenuation  $arg1"
		echo
		$(mosquitto_pub -t $cmd_root/tx/gain -m $arg1)
		get_status;		
		;;
	RXF ) echo "    **** set RX Frequency $arg1"
		if [ -z "$arg1" ]; then echo "noarg"; fi
		echo $arg1
		$(mosquitto_pub -t $cmd_root/rx/frequency -m $arg1)
        sleep 1
		get_status;
		;;
	RXBW ) if [ -z "$arg1" ]; then echo "**** noarg !"; fi
		echo "    **** set RX Bandwidth $arg1 "
		echo
		iio_attr -q -c -i ad9361-phy voltage0 rf_bandwidth $((arg1)) 1>/dev/null
		get_status;
		;;
	RXGAIN ) echo "    **** set RX gain  $arg1"
		echo
		$(mosquitto_pub -t $cmd_root/rx/gain -m $arg1)
        sleep 1
		get_status;		
		;;
	RXSR) echo "    **** set RX Samplerate  $arg1"
		$(mosquitto_pub -t $cmd_root/rx/sr -m $arg1)
        sleep 1
		get_status;		
		;;
	TXSR) echo "    **** set TX Samplerate  $arg1"
		$(mosquitto_pub -t $cmd_root/tx/sr -m $arg1)
        sleep 1
		get_status;		
		;;	
    SF) echo "    **** set Sweepfft Frequency  $arg1"
		$(mosquitto_pub -t $cmd_root/sweepfft/frequency -m $arg1)
        sleep 1
		get_status;		
		;;
    SS) echo "    **** set Sweepfft span  $arg1"
		$(mosquitto_pub -t $cmd_root/sweepfft/span -m $arg1)
        sleep 1
		get_status;		
		;;
	RXO) echo "    **** Rx format(0=cs16,1=cs8,2=cs16+fft)  $arg1"
		$(mosquitto_pub -t $cmd_root/rx/format -m $arg1)
        sleep 1
		get_status;		
		;;	
	f ) 	freq=$(/usr/bin/iio_attr -q -c ad9361-phy altvoltage0 frequency)  1>/dev/null
		echo "    **** Frequency :  $freq"		
		;;
	*) command=""
		echo "*** error 404 !"
		freq=""
		arg1=""
		#get_status;
		;;
esac


command=""
freq=""
#pluto_com=""
arg1=""

done

