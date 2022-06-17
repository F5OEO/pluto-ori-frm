cp plutosdr_fw_patch/Makefile ../plutosdr-fw/
cp plutosdr_fw_patch/zynq_pluto_defconfig ../plutosdr-fw/linux/arch/arm/configs

cp plutosdr_fw_patch/zynq-pluto-sdr-revc.dts ../plutosdr-fw/linux/arch/arm/boot/dts/
cp plutosdr_fw_patch/zynq-pluto-sdr-revb.dts ../plutosdr-fw/linux/arch/arm/boot/dts/

cp plutosdr_fw_patch/linux/ad9361_regs.h ../plutosdr-fw/linux/drivers/iio/adc/
cp plutosdr_fw_patch/linux/f_uac2.c ../plutosdr-fw/linux/drivers/usb/gadget/function/

# For dtc -@ oscimp
cp plutosdr_fw_patch/linux/scripts/Makefile.lib ../plutosdr-fw/linux/scripts
