# pluto-ori firmware
A custom firmware for pluto-ori dvbs2
# Install : ONLY ONCE

```
git clone --recursive --depth 1 --shallow-submodules https://github.com/analogdevicesinc/plutosdr-fw.git --branch v0.33
git clone --recursive --depth 1 --shallow-submodules https://github.com/F5OEO/hdl --branch pluto-ori
cd pluto-buildroot
./run_only_once.sh
```
#building
(from pluto-buildroot folder)
You should have Vivado 2020.1 installed 
```
source sourceme.ggm
cd ../plutosdr-fw
make
```
