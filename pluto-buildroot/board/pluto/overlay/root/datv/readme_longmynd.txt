LONGMYND(1)		General Commands Manual 	    LONGMYND(1)

NAME
       longmynd  -  Outputs transport streams from the Minitiouner DVB-
       S/S2 demodulator

SYNOPSIS
       longmynd [-u USB_BUS USB_DEVICE]
		[-i MAIN_IP_ADDR  MAIN_PORT | -t MAIN_TS_FIFO]
		[-I STATUS_IP_ADDR  STATUS_PORT | -s MAIN_STATUS_FIFO]
		[-w] [-b] [-p h | -p v] [-r TS_TIMEOUT_PERIOD]
		[-S HALFSCAN_WIDTH]
	     MAIN_FREQ[,ALT_FREQ] MAIN_SR[,ALT_SR]

DESCRIPTION
       longmynd Interfaces to the Minitiouner hardware	to  search  for
       and demodulate a DVB-S or DVB-S2 stream. This stream can be out‐
       put either to a local FIFO (using the default or -t  option)  or
       to an IP address/port via UDP.

       The  Main  TS  stream  is the one coming out of the Primary FTDI
       Board.

OPTIONS
       -u USB_BUS USB_DEVICE
	      Sets the USB Bus and USB Device Number  of  the  required
	      Minitiouner  in  a multi device system.  Default uses the
	      first detected Minitiouner.

       -i IP_ADDR PORT
	      If UDP output is required (instead of  the  default  FIFO
	      output), this option sets the IP Address and Port to send
	      the Main TS Stream to.  Default is to use a FIFO for Main
	      TS Stream.

       -I IP_ADDR PORT
	      If  UDP  output  is required (instead of the default FIFO
	      output), this option sets the IP Address and Port to send
	      the  Main Status Stream to.  Default is to use a FIFO for
	      Main Status Stream.

       -t TS_FIFO
	      Sets the name of the Main TS Stream output FIFO.	Default
	      is "./longmynd_main_ts".

       -s STATUS_FIFO
	      Sets  the  name  of  the	Status output FIFO.  Default is
	      "./longmynd_main_status".

       -w     If selected, this option swaps over the RF input so  that
	      the  Main  TS Stream is fed from the BOTTOM F-Type of the
	      NIM.  Default uses the TOP  RF  input  for  the  Main  TS
	      stream.

       -b     If selected, this option enables a tone audio output that
	      will be present when DVB-S2  is  being  demodulated,  and
	      will  increase  in  pitch  for an increase in MER, to aid
	      pointing.  By default this option is disabled.

       -p h | -p v
	      Controls and enables the LNB supply voltage  output  when
	      an  RT5047A LNB Voltage Regulator is fitted.  "-p v" will
	      set 13V output (Vertical Polarisation), "-p h"  will  set
	      18V  output  (Horizontal	Polarisation).	 By default the
	      RT5047A output is disabled.

       -r TS_TIMEOUT_PERIOD
	      Resets and reconfigures the NIM after this period in mil‐
	      liseconds   without   any  valid	TS  packets  (including
	      Nulls.), or since last reset cycle. If multiple  frequen‐
	      cies  or	multiple  symbolrates  are specified then these
	      will be cycled through on each reset. When multiple  fre‐
	      quencies	and  symbolrates are given, each frequency will
	      be scanned for each symbolrate before moving  on	to  the
	      next  frequency.	 Set to -1 to disable.	By default this
	      is 5000 milliseconds.

       -S HALFSCAN_WIDTH
	      Sets the frequency scan half-width in ratio of the Symbol
	      Rate.  For example a value of '0.6' configures a ratio of
	      +/-0.6. A value of  approx. 20% greater than the intended
	      functional  width  appears to work well.	By default this
	      is +/-1.5 * Symbol Rate.

       MAIN_FREQ[,ALT_FREQ]
	      specifies the starting frequency (in KHz) of the Main  TS
	      Stream search algorithm, and up to 3 alternative frequen‐
	      cies that will be scanned. The TS  TIMEOUT  must	not  be
	      disabled	to enable scanning functionality. When multiple
	      frequencies and symbolrates  are	given,	each  frequency
	      will  be	scanned for each symbolrate before moving on to
	      the next frequency.

       MAIN_SR
	      specifies the starting Symbol Rate (in KSPS) of the  Main
	      TS  Stream search algorithm, and up to 3 alternative sym‐
	      bolrates that will be scanned. The TS TIMEOUT must not be
	      disabled	to enable scanning functionality. When multiple
	      frequencies and symbolrates  are	given,	each  frequency
	      will  be	scanned for each symbolrate before moving on to
	      the next frequency.

EXAMPLES
       longmynd 2000 2000
	      will find the first available Minitiouner, search  for  a
	      2MHz  TS	Stream at 2MSPS on the TOP RF input, output the
	      TS to a FIFO called "longmynd_main_ts" and the status  to
	      a FIFO called "longmynd_main_status".

       longmynd -w 2000 2000
	      As above but uses the BOTTOM RF input.

       longmynd -u 1 4 2000 2000
	      As  above  but  will attempt to find a minitiouner at usb
	      device 4 on usb bus 1.

       longmynd -i 192.168.1.1 87 2000 2000
	      As above	but  any  TS  output  will  be	to  IP	address
	      192.168.1.1 on port 87

       longmynd -i 192.168.1.1 87 -r 5000 145000,146000 35,66,125
	      As  above but after 5000 milliseconds with no TS data the
	      Tuner configuration will be cycled to  the  next	of  the
	      following combinations:
	       * 145 MHz, 35 Ks/s
	       * 145 MHz, 66 Ks/s
	       * 145 MHz, 125 Ks/s
	       * 146 MHz, 35 Ks/s
	       * 146 MHz, 66 Ks/s
	       * 146 MHz, 125 Ks/s
	       * [repeat from start]

							    LONGMYND(1)
