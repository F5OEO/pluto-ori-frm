source source.me
cp /home/suoto/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit ./
bootgen -w -image zynq.bif -arch zynq -process_bitstream bin
sshpass -p analog scp -o StrictHostKeyChecking=no system_top.bit.bin root@pluto.local:/root
sshpass -p analog ssh -o StrictHostKeyChecking=no -t root@pluto.local '/mnt/jffs2/update_bitstream.sh system_top.bit.bin'
