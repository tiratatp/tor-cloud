#!/bin/bash -e
# Copyright (c) 2016 The Tor Project, Inc
# git://git.torproject.org/tor-cloud.git
# Set up an EC2 instance as either an (obfsproxy) bridge or a normal
# private bridge

# Make sure that we are root
if [ "$(whoami)" != "root" ]; then
  echo "root required; re-run with sudo";
  exit 1;
fi

CONFIG="bridge";
if [ "$#" -eq 1 ]; then
  CONFIG="$1";
fi

DISTRO=$(lsb_release -c | cut -f2)
CONFIG_FILE="/etc/tor/torrc";
EC2_RESERVATION_ID=$(wget -q -O - http://instance-data/latest/meta-data/reservation-id | sed 's/-//')
SOURCES="/etc/apt/sources.list";
PERIODIC="/etc/apt/apt.conf.d/10periodic"
UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/50unattended-upgrades"
IPTABLES_RULES="/etc/iptables.rules"
NETWORK="/etc/network/interfaces"

# Get the latest package updates
echo "Updating the system..."
apt-get update
apt-get -y upgrade

# Configure unattended-upgrades. The system will automatically download,
# install and configure all packages, and reboot if necessary.
echo "Configuring the unattended-upgrades package..."
apt-get -y install unattended-upgrades update-notifier-common

# Back up the original configuration
mv "$PERIODIC" "${PERIODIC}.bkp"
mv "$UNATTENDED_UPGRADES" "${UNATTENDED_UPGRADES}.bkp"

# Choose what to upgrade in 10periodic
cat << EOF > $PERIODIC
# Update the package list, download, and install available upgrades
# every day. The local archive is cleaned once a week.
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Enable automatic package updates in 50unattended-upgrades
cat << EOF > $UNATTENDED_UPGRADES
// Automatically upgrade packages from these (origin:archive) pairs
Unattended-Upgrade::Allowed-Origins {
  "\${distro_id}:\${distro_codename}";
  "\${distro_id}:\${distro_codename}-security";
  "\${distro_id}:\${distro_codename}-updates";
  "TorProject:$DISTRO";
};

// Automatically reboot *WITHOUT CONFIRMATION*
//  if the file /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "true";

// Do not cause conffile prompts
// ref: https://askubuntu.com/questions/104899/make-apt-get-or-aptitude-run-with-y-but-not-prompt-for-replacement-of-configu
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
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

mv "$NETWORK" "${NETWORK}.bkp"
cat << EOF > $NETWORK
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp
pre-up iptables-restore < $IPTABLES_RULES
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
deb-src http://deb.torproject.org/torproject.org $DISTRO main
EOF

# Install Tor's GPG key
echo "Installing Tor's gpg key...";
gpg --keyserver keys.gnupg.net --recv 886DDD89
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -

# Install Tor and arm
echo "Installing Tor...";
apt-get update
apt-get -y install tor deb.torproject.org-keyring tor-geoipdb tor-arm obfsproxy

# Configure Tor
echo "Configuring Tor...";
cp "$CONFIG_FILE" "${CONFIG_FILE}.bkp"

# (Obfsproxy) bridge
if [ $CONFIG == "bridge" ]; then
echo "Configuring Tor as a $CONFIG";
cat << EOF > $CONFIG_FILE
# Auto generated Tor $CONFIG config file

# A unique handle for your server.
Nickname ec2${CONFIG}${EC2_RESERVATION_ID}

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

# Enable the Extended ORPort
ExtORPort auto

# Run obfsproxy
ServerTransportPlugin obfs2,obfs3 exec /usr/bin/obfsproxy --managed
ServerTransportListenAddr obfs2 0.0.0.0:52176
ServerTransportListenAddr obfs3 0.0.0.0:40872

# Never send or receive more than 10GB of data per week. The accounting
# period runs from 10 AM on the 1st day of the week (Monday) to the same
# day and time of the next week.
AccountingStart week 1 10:00
AccountingMax 10GB
BandwidthRate 512KB
BandwidthBurst 1GB

# Running a bridge relay just passes data to and from the Tor network --
# so it shouldn't expose the operator to abuse complaints.
ExitPolicy reject *:*
EOF

echo "Done configuring the system, will reboot"
echo "Your system has been configured as a Tor obfsproxy bridge, see https://cloud.torproject.org/ for more info"
reboot
fi

# Private bridge
if [ $CONFIG == "privatebridge" ]; then
echo "Configuring Tor as a $CONFIG";
cat << EOF > $CONFIG_FILE
# Auto generated Tor $CONFIG config file

# A unique handle for your server.
Nickname ec2priv$EC2_RESERVATION_ID

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

# Enable the Extended ORPort
ExtORPort auto

# Run obfsproxy
ServerTransportPlugin obfs2,obfs3 exec /usr/bin/obfsproxy --managed
ServerTransportListenAddr obfs2 0.0.0.0:52176
ServerTransportListenAddr obfs3 0.0.0.0:40872

# Never send or receive more than 10GB of data per week. The accounting
# period runs from 10 AM on the 1st day of the week (Monday) to the same
# day and time of the next week.
AccountingStart week 1 10:00
AccountingMax 10GB
BandwidthRate 512KB
BandwidthBurst 1GB

# Running a bridge relay just passes data to and from the Tor network --
# so it shouldn't expose the operator to abuse complaints.
ExitPolicy reject *:*
EOF

# Edit /var/lib/tor/state and change the obfs port
echo "Done configuring the system, will reboot"
echo "Your system has been configured as a private obfsproxy Tor bridge, see https://cloud.torproject.org/ for more info"
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
echo "Your system has been configured for blocking diagnostics"
reboot
fi
