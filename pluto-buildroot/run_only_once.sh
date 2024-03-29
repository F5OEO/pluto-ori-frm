#cp plutosdr_fw_patch/Makefile ../plutosdr-fw/
cp plutosdr_fw_patch/zynq_pluto_defconfig ../plutosdr-fw/linux/arch/arm/configs

cp plutosdr_fw_patch/zynq-pluto-sdr-revc.dts ../plutosdr-fw/linux/arch/arm/boot/dts/
cp plutosdr_fw_patch/zynq-pluto-sdr-revb.dts ../plutosdr-fw/linux/arch/arm/boot/dts/
cp plutosdr_fw_patch/zynq-pluto-sdr-revplus.dts ../plutosdr-fw/linux/arch/arm/boot/dts/
cp plutosdr_fw_patch/zynq-pluto-sdr.dtsi ../plutosdr-fw/linux/arch/arm/boot/dts/
cp plutosdr_fw_patch/pluto.its ../plutosdr-fw/scripts
cp plutosdr_fw_patch/pluto.mk ../plutosdr-fw/scripts

cp plutosdr_fw_patch/uboot/zynq-common.h ../plutosdr-fw/u-boot-xlnx/include/configs

cp plutosdr_fw_patch/linux/ad9361_regs.h ../plutosdr-fw/linux/drivers/iio/adc/
cp plutosdr_fw_patch/linux/ad9361.c ../plutosdr-fw/linux/drivers/iio/adc/
cp plutosdr_fw_patch/linux/f_uac2.c ../plutosdr-fw/linux/drivers/usb/gadget/function/

# For dtc -@ oscimp
cp plutosdr_fw_patch/linux/scripts/Makefile.lib ../plutosdr-fw/linux/scripts
