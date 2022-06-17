# pluto-ori firmware
A custom firmware for pluto-ori dvbs2
# Install : ONLY ONCE

```
git clone --recursive --depth 1 --shallow-submodules https://github.com/analogdevicesinc/plutosdr-fw.git --branch v0.33
git clone --recursive --depth 1 --shallow-submodules https://github.com/F5OEO/hdl --branch pluto-ori
cd pluto-buildroot
./run_only_once.sh
```

# Debian dependencies
```
sudo apt-get install git build-essential fakeroot libncurses5-dev libssl-dev ccache
 sudo apt-get install dfu-util u-boot-tools device-tree-compiler libssl1.0-dev mtools
 sudo apt-get install bc python cpio zip unzip rsync file wget
sudo apt-get install gcc-multilib g++-multilib
```

# Building
(from pluto-buildroot folder)
You should have Vivado 2020.1 installed
If Vivado is not installed on /opt/Xilinx/Vivado/2020.1, modify sourceme.ggm to the correct path 
```
source sourceme.ggm
cd ../plutosdr-fw
make
```
