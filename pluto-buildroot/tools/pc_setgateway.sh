#Make the PC internet sharing for pluto. Just check your ethernet subnetwork

INET_SUBNETWORK=192.168.1
IFACE_PLUTO=$(netstat -ie | grep -B1 "192.168.2.10" | head -n1 | awk '{print substr($1, 1, length($1)-1)}')
IFACE_PC=$(netstat -ie | grep -B1 "$INET_SUBNETWORK" | head -n1 | awk '{print substr($1, 1, length($1)-1)}')

sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -A FORWARD -o $IFACE_PC -i $IFACE_PLUTO -s 192.168.2.0/24 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o $IFACE_PC -s 192.168.2.0/24 -j MASQUERADE

echo "Internet connexion from $IFACE_PC is shared with pluto interface $IFACE_PLUTO"