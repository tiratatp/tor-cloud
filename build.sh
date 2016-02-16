# Copyright (c) 2011 Expression Technologies <info@expressiontech.org>
# Copyright (c) 2011 SiNA <sina@expressiontech.org>
# Copyright (c) 2011 The Tor Project, Inc
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
# USA
#
# Tor Cloud is developed and maintained by partnership between
# ExpressionTech and The Tor Project.
#
# Bundle and publish instance of Ubuntu modified to run as a Tor bridge
# on Amazon EC2

# Define your Amazon credentials for ec2-api-tools to function
export EC2_PRIVATE_KEY=/path/to/pk.cert
export EC2_CERT=/path/to/cert.pem

relaytype=$1;
region=$2;
sshkey=$3;
keypair=$4
arch=i386

if [ -n "$relaytype" ]; then
        echo "Starting ..."
else
        echo "./build.sh bridge ap-southeast-1 /home/architect/keys/tor-cloud-ap-southeast-1.pem tor-cloud-ap-southeast-1"
	echo "(./build.sh relay-type region ssh-key ssh-keyname)"
        echo "get the list of regions using the ec2-api-tools: ec2-describe-regions"
        exit
fi

# get the associated AMI (amazon image) and AKI (amazon kernel) values for 
# the defined region & architecture. We only work with EBS instance types, as they are 
# elastic and easy to snapshot

echo ${region}
echo ${arch}

qurl=https://uec-images.ubuntu.com/query/precise/server/released.current.txt
curl --silent ${qurl} | grep ebs
ami=$(curl --silent "${qurl}" | awk '-F\t' '$5 == "ebs" && $6 == arch && $7 == region { print $8 }' arch=$arch region=$region )
aki=$(curl --silent "${qurl}" | awk '-F\t' '$5 == "ebs" && $6 == arch && $7 == region { print $9 }' arch=$arch region=$region )

echo ${ami}
echo ${aki}


iid=$(ec2-run-instances --region ${region} --instance-type t1.micro --key ${keypair}  ${ami} --group  tor-cloud-build| awk {'print $2'} | grep i-)
echo ${iid}
echo "After running ec2-run-instances, sleep for 45 seconds..."
sleep 45
zone=$(ec2-describe-instances --region ${region} $iid | awk '-F\t' '$2 == iid { print $12 }' iid=${iid} )
echo "After running ec2-describe-instances, sleep for 20 seconds..."
echo ${zone}
sleep 20
host=$(ec2-describe-instances --region ${region} $iid | awk '-F\t' '$2 == iid { print $4 }' iid=${iid} )
echo ${host}
echo "After running ec2-describe-instances again, sleep for 20 seconds..."
sleep 20

# create and attached ebs volume to be used for snapshot
vol=$(ec2-create-volume --size 4 --region ${region} --availability-zone ${zone} | awk {'print $2'})

echo "After creating the volume, sleep for 20 seconds..."
sleep 20

ec2-attach-volume --instance ${iid} --region ${region} --device /dev/sdh ${vol}

echo "After attaching the volume, sleep for 20 seconds..."
sleep 20

# Get the files we need
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "cd /mnt && sudo wget https://cloud-images.ubuntu.com/releases/precise/release/SHA256SUMS && sudo wget https://cloud-images.ubuntu.com/releases/precise/release/SHA256SUMS.gpg && sudo wget https://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-i386.tar.gz"

# Verify the signature
echo "Verify the signature"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "sudo gpg --keyserver keys.gnupg.net --recv-key 7DB87C81"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "if [ `echo $?` -eq "1" ]; then echo 'Could not get key, will lock you out of the instance' ; sudo rm /home/ubuntu/.ssh/authorized_keys ; fi"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "cd /mnt ; sudo gpg --verify SHA256SUMS.gpg SHA256SUMS"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "cd /mnt ; sudo sha256sum -c SHA256SUMS 2>&1 | grep OK"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "echo $?"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "if [ `echo $?` -eq "1" ]; then echo 'Hash does not match, will lock you out of the instance' ; sudo rm /home/ubuntu/.ssh/authorized_keys ; fi"

# Continue the build process
echo "Verified the signature, continue with the build process"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey} ubuntu@${host} -q -t "sudo chown ubuntu:ubuntu /mnt && cd /mnt && tar -Sxvzf /mnt/ubuntu-12.04-server-cloudimg-i386.tar.gz && sudo mkdir /mnt/src /mnt/target && sudo mount -o loop,rw /mnt/precise-server-cloudimg-i386.img /mnt/src && sudo mkfs.ext4 -F -L cloudimg-rootfs /dev/xvdh && sudo mount /dev/xvdh /mnt/target"

# this is our startup file that loads tor-prep.sh on first boot
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i  ${sshkey}  ubuntu@${host} -q -v -t "sudo wget https://gitweb.torproject.org/tor-cloud.git/blob_plain/HEAD:/rc.local -O /mnt/src/etc/rc.local"

# Update the rc.local file with the type of relay we want to create (bridge, private-bridge or relay)
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i ${sshkey}  ubuntu@${host} -q -v -t "sudo sed -i s/type/$1/ /mnt/src/etc/rc.local"

# this script is responsible for installation and configuration of the Tor application
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i  ${sshkey}  ubuntu@${host} -q -v -t "sudo wget https://gitweb.torproject.org/tor-cloud.git/blob_plain/HEAD:/ec2-prep.sh -O /mnt/src/etc/ec2-prep.sh"

# fix permissions
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i  ${sshkey}  ubuntu@${host} -q -v -t "sudo chmod +x /mnt/src/etc/ec2-prep.sh"

# rsync the retrieved Ubuntu image to mounted Volume
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i  ${sshkey}  ubuntu@${host} -q -v -t "sudo rsync -aXHAS /mnt/src/ /mnt/target"

# unmount volumes
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  -i  ${sshkey}  ubuntu@${host} -q -v -t "sudo umount /mnt/target && sudo umount /mnt/src"

# create a snapshot from Volume
snap=$(ec2-create-snapshot --region ${region} ${vol} | grep ${vol}  | awk {' print $2 '})

echo "ec2-describe-snapshots --region ${region}"
ec2-describe-snapshots --region ${region} 

# smarter sleep 

hold=$(ec2-describe-snapshots --region ${region} | grep ${snap}  | awk {'print $4}')
echo $hold

while [ "$hold" != "completed" ]
do
hold=$(ec2-describe-snapshots --region ${region} | grep ${snap}  | awk {'print $4}') && sleep 20
echo $hold
done

# create NOW and RANDOM variables to be used in the description field of the image
NOW=$(date +"%m-%d-%Y")
RANDOM=$(echo `</dev/urandom tr -dc A-Za-z0-9 | head -c8`)

# Finally register and publish the image
echo "Registering and publishing the image..."
ec2-register --region ${region} --snapshot ${snap} --architecture=i386 --kernel=${aki} --name "Tor-Cloud-EC2-${rel}-${region}-${NOW}-${RANDOM}" --description "Tor Cloud bridge Ubuntu 12.04 LTS [Precise Pangolin] - [${region}]"

# cleanup
ec2-detach-volume --region ${region}  ${vol}
echo "After detaching the volume, but before terminating it, sleep 20 seconds..."
sleep 20
ec2-terminate-instances --region ${region}  ${iid}
