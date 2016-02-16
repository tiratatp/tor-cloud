#!/bin/bash -e
# Copyright (c) 2011 The Tor Project, Inc
# git://git.torproject.org/tor-cloud.git
# Set up an EC2 instance as either an (obfsproxy) bridge or a normal
# private bridge
USER="`whoami`";
DISTRO="`lsb_release -c|cut -f2`";
SOURCES="/etc/apt/sources.list";
CONFIG="$1";
CONFIG_FILE="/etc/tor/torrc";
RESERVATION="`curl -m 5 http://169.254.169.254/latest/meta-data/reservation-id | sed 's/-//'`";
PERIODIC="/etc/apt/apt.conf.d/10periodic"
UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/50unattended-upgrades"
IPTABLES_RULES="/etc/iptables.rules"
NETWORK="/etc/network/interfaces"
GPGKEY="/etc/apt/trusted.gpg.d/tor.asc"

# Make sure that we are root
if [ "$USER" != "root" ]; then
echo "root required; re-run with sudo";
  exit 1;
fi

# Get the latest package updates
echo "Updating the system..."
apt-get update
apt-get -y upgrade

# Configure unattended-upgrades. The system will automatically download,
# install and configure all packages, and reboot if necessary.
echo "Configuring the unattended-upgrades package..."

# Back up the original configuration
mv /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/10periodic.bkp
mv /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.bkp

# Choose what to upgrade in 10periodic
cat << EOF > $PERIODIC
# Update the package list, download, and install available upgrades
# every day. The local archive is cleaned once a week.
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Enable automatic package updates in 50unattended-upgrades
cat << EOF > $UNATTENDED_UPGRADES
// Automatically upgrade packages from these (origin, archive) pairs
Unattended-Upgrade::Allowed-Origins {
    "Ubuntu $DISTRO";
	"Ubuntu $DISTRO-security";
	"Ubuntu $DISTRO-updates";
	"TorProject $DISTRO";
	"TorProject experimental-$DISTRO";
};

// Automatically reboot *WITHOUT CONFIRMATION* if the file
// /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "true";

// Do not cause conffile prompts
Dpkg::Options { --force-confold; }
EOF

# Configure iptables to redirect traffic to port 443 to port 9001
# instead, and make that configuration stick.
echo "Configuring iptables..."
cat << EOF > $IPTABLES_RULES
*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [77:6173]
:OUTPUT ACCEPT [77:6173]
-A PREROUTING -i eth0 -p tcp -m tcp --dport 443 -j REDIRECT --to-ports 9001 
COMMIT
EOF

mv /etc/network/interfaces /etc/network/interfaces.bkp
cat << EOF > $NETWORK
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp
  pre-up iptables-restore < /etc/iptables.rules
EOF

# Choose how to configure Tor
case "$CONFIG" in
   "bridge" ) echo "selecting $CONFIG config...";;
   "privatebridge" ) echo "selecting $CONFIG config...";;
   "blockingdiagnostics" ) echo "selecting $CONFIG config...";;
   * )
echo "You did not select a proper configuration: $CONFIG";
echo "Please try the following examples: ";
echo "$0 bridge";
echo "$0 privatebridge";
echo "$0 blockingdiagnostics";
exit 2;
    ;;
esac

# Add deb.torproject.org to /etc/apt/sources.list
echo "Adding Tor's repo for $DISTRO...";
cat << EOF >> $SOURCES
deb http://deb.torproject.org/torproject.org $DISTRO main
deb http://deb.torproject.org/torproject.org experimental-$DISTRO main
EOF

# Install Tor's GPG key
echo "Installing Tor's gpg key...";
#gpg --keyserver keys.gnupg.net --recv 886DDD89
#gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
cat << EOF > $GPGKEY
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.10 (GNU/Linux)

mQENBEqg7GsBCACsef8koRT8UyZxiv1Irke5nVpte54TDtTl1za1tOKfthmHbs2I
4DHWG3qrwGayw+6yb5mMFe0h9Ap9IbilA5a1IdRsdDgViyQQ3kvdfoavFHRxvGON
tknIyk5Goa36GMBl84gQceRs/4Zx3kxqCV+JYXE9CmdkpkVrh2K3j5+ysDWfD/kO
dTzwu3WHaAwL8d5MJAGQn2i6bTw4UHytrYemS1DdG/0EThCCyAnPmmb8iBkZlSW8
6MzVqTrN37yvYWTXk6MwKH50twaX5hzZAlSh9eqRjZLq51DDomO7EumXP90rS5mT
QrS+wiYfGQttoZfbh3wl5ZjejgEjx+qrnOH7ABEBAAG0JmRlYi50b3Jwcm9qZWN0
Lm9yZyBhcmNoaXZlIHNpZ25pbmcga2V5iQE8BBMBAgAmAhsDBgsJCAcDAgQVAggD
BBYCAwECHgECF4AFAlA+M24FCQ0iFQAACgkQ7oy8noht3YkZsAf/Z+O15tDvGwLz
NROeMiTyOZ4fyQ1lynUpOS3fUJl3qM30oWPl1tK5pdAZgwleL0Co8d27Hv14zpCO
wwI3htgl7dsD8IS564v1sHGx+X1qfLzInwFxIlVxzrVbhUNeLSKiBJ6qwcZqAIep
eS2Lv+l3lELOvjbHQ4bx5DqoVZn0uUqksh3PkyN9Du4lZ2WGiTm1pIWDxY8kJIgx
pDFEL3e5i/cIQy6wsfeE2Nw2T0qoxn+sWSvwBUijtfq0K41w4jpEsnmjiZQ0l+VT
wcoGlF/oQuEkAV+FXQCLw26a2aPUXizttlPINJ8JiNzl68j8FaMnqkaFAzJffbM8
D1UOZVdmnbkBDQRKoO2QAQgA2uKxSRSKpd2JO1ODUDuxppYacY1JkemxDUEHG31c
qCVTuFz4alNyl4I+8pmtX2i+YH7W9ew7uGgjRzPEjTOm8/Zz2ue+eQeroveuo0hy
Fa9Y3CxhNMCE3EH4AufdofuCmnUf/W7TzyIvzecrwFPlyZhqWnmxEqu8FaR+jXK9
Jsx2Zby/EihNoCwQOWtdv3I4Oi5KBbglxfxE7PmYgo9DYqTmHxmsnPiUE4FYZG26
3Ll1ZqkbwW77nwDEl1uh+tjbOu+Y1cKwecWbyVIuY1eKOnzVC88ldVSKxzKOGu37
My4z65GTByMQfMBnoZ+FZFGYiCiThj+c8i93DIRzYeOsjQARAQABiQJEBBgBAgAP
AhsCBQJQPjNzBQkJX6zhASnAXSAEGQECAAYFAkqg7ZAACgkQdKlBuiGeyBC0EQf5
Af/G0/2xz0QwH58N6Cx/ZoMctPbxim+F+MtZWtiZdGJ7G1wFGILAtPqSG6WEDa+T
hOeHbZ1uGvzuFS24IlkZHljgTZlL30p8DFdy73pajoqLRfrrkb9DJTGgVhP2axhn
OW/Q6Zu4hoQPSn2VGVOVmuwMb3r1r93fQbw0bQy/oIf9J+q2rbp4/chOodd7XMW9
5VMwiWIEdpYaD0moeK7+abYzBTG5ADMuZoK2ZrkteQZNQexSu4h0emWerLsMdvcM
LyYiOdWP128+s1e/nibHGFPAeRPkQ+MVPMZlrqgVq9i34XPA9HrtxVBd/PuOHoaS
1yrGuADspSZTC5on4PMaQgkQ7oy8noht3Yn+Nwf/bLfZW9RUqCQAmw1L5QLfMYb3
GAIFqx/h34y3MBToEzXqnfSEkZGM1iZtIgO1i3oVOGVlaGaE+wQKhg6zJZ6oTOZ+
/ufRO/xdmfGHZdlAfUEau/YiLknElEUNAQdUNuMB9TUtmBvh00aYoOjzRoAentTS
+/3p3+iQXK8NPJjQWBNToUVUQiYD9bBCIK/aHhBhmdEc0YfcWyQgd6IL7547BRJb
PDjuOyAfRWLJ17uJMGYqOFTkputmpG8n0dG0yUcUI4MoA8U79iG83EAd5vTS1eJi
Tmc+PLBneknviBEBiSRO4Yu5q4QxksOqYhFYBzOj6HXwgJCczVEZUCnuW7kHww==
=10NR
-----END PGP PUBLIC KEY BLOCK-----
EOF
apt-key add $GPGKEY

# Install Tor and arm
echo "Installing Tor...";
apt-get update
apt-get -y install tor tor-geoipdb tor-arm deb.torproject.org-keyring obfsproxy

# Configure Tor
echo "Configuring Tor...";
cp /etc/tor/torrc /etc/tor/torrc.bkp

# (Obfsproxy) bridge
if [ $CONFIG == "bridge" ]; then
echo "Configuring Tor as a $CONFIG";
cat << EOF > $CONFIG_FILE
# Auto generated Tor $CONFIG config file

# A unique handle for your server.
Nickname ec2$CONFIG$RESERVATION

# Set "SocksPort 0" if you plan to run Tor only as a server, and not
# make any local application connections yourself.
SocksPort 0

# What port to advertise for Tor connections.
ORPort 443

# Listen on a port other than the one advertised in ORPort (that is,
# advertise 443 but bind to 9001).
ORListenAddress 0.0.0.0:9001

# Start Tor as a bridge.
BridgeRelay 1

# Run obfsproxy
ServerTransportPlugin obfs2,obfs3 exec /usr/bin/obfsproxy --managed
ServerTransportListenAddr obfs2 0.0.0.0:52176
ServerTransportListenAddr obfs3 0.0.0.0:40872

# Never send or receive more than 10GB of data per week. The accounting
# period runs from 10 AM on the 1st day of the week (Monday) to the same
# day and time of the next week.
AccountingStart week 1 10:00
AccountingMax 10 GB
BandwidthRate 20KB
BandwidthBurst 1GB

# Running a bridge relay just passes data to and from the Tor network --
# so it shouldn't expose the operator to abuse complaints.
ExitPolicy reject *:*
EOF

echo "Done configuring the system, will reboot"
echo "Your system has been configured as a Tor obfsproxy bridge, see https://cloud.torproject.org/ for more info" > /etc/ec2-prep.sh
reboot
fi

# Private bridge
if [ $CONFIG == "privatebridge" ]; then
echo "Configuring Tor as a $CONFIG";
cat << EOF > $CONFIG_FILE
# Auto generated Tor $CONFIG config file

# A unique handle for your server.
Nickname ec2priv$RESERVATION

# Set "SocksPort 0" if you plan to run Tor only as a server, and not
# make any local application connections yourself.
SocksPort 0

# What port to advertise for Tor connections.
ORPort 443

# Listen on a port other than the one advertised in ORPort (that is,
# advertise 443 but bind to 9001).
ORListenAddress 0.0.0.0:9001

# Start Tor as a private obfsproxy bridge
BridgeRelay 1
PublishServerDescriptor 0
ServerTransportPlugin obfs2,obfs3 exec /usr/bin/obfsproxy --managed
ServerTransportListenAddr obfs2 0.0.0.0:52176
ServerTransportListenAddr obfs3 0.0.0.0:40872

# Never send or receive more than 10GB of data per week. The accounting
# period runs from 10 AM on the 1st day of the week (Monday) to the same
# day and time of the next week.
AccountingStart week 1 10:00
AccountingMax 10 GB
BandwidthRate 20KB
BandwidthBurst 1GB

# Running a bridge relay just passes data to and from the Tor network --
# so it shouldn't expose the operator to abuse complaints.
ExitPolicy reject *:*
EOF

# Edit /var/lib/tor/state and change the obfs port
echo "Done configuring the system, will reboot"
echo "Your system has been configured as a private obfsproxy Tor bridge, see https://cloud.torproject.org/ for more info" > /etc/ec2-prep.sh
reboot
fi

# Blocking diagnostics (private bridge and then some)
if [ $CONFIG == "blockingdiagnostics" ]; then
echo "Configuring a Tor blocking diagnostics image";

# Configure Tor to run as a private bridge
cat << EOF > $CONFIG_FILE
SocksPort 0
ORPort 443
ORListenAddress 0.0.0.0:9001
BridgeRelay 1
PublishServerDescriptor 0
Log info file /var/log/tor/info.log
AccountingStart week 1 10:00
AccountingMax 10 GB
ExitPolicy reject *:*
EOF

# Run tcpdump on boot
cat << EOF > /etc/rc.local
#!/bin/sh -e
sudo screen tcpdump -v -i any -s 0 -w /root/bridge_test.cap
EOF
echo "Done configuring the system, will reboot"
echo "Your system has been configured for blocking diagnostics" > /etc/ec2-prep.sh
reboot
fi
