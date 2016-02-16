This document explains the process of building and publishing new Tor
images in the Amazon EC2 cloud.

1. Set up your build environment

    I usually spin up an Ubuntu instance in the EC2 cloud and set it up
    as the Tor Cloud build machine. You can use another server, or your
    laptop, if you want.

    You need to install two packages; ec2-api-tools and git-core. The
    ec2-api-tools package can be found in multiverse, so you'll need to
    add this to /etc/apt/sources.list.

    Note that ec2-api-tools will download and install
    openjdk-6-jre-headless. There's a bug in Ubuntu which may cause your
    Ubuntu instance to crash when installing that package. If that's the
    case, try using a 64-bit image for the build machine instead.

    As root, clone the Tor Cloud git repository from
    https://git.torproject.org/tor-cloud.git, and create two
    directories; certs and keys.

    Download the private certificates (pk.cert and cert.pem) for your
    AWS account and put them in the certs directory. Run the following
    two commands:

      root@tor-build:~# export EC2_PRIVATE_KEY=/root/certs/pk.cert
      root@tor-build:~# export EC2_CERT=/root/certs/cert.pem

    Make sure that you also update tor-cloud/build.sh with the correct
    path to pk.cert and cert.pem.

2. Test that everything's working

    To test that everything's working, run the command
    'ec2-describe-regions'. The output should be something like this:

      root@tor-build:~# ec2-describe-regions
      REGION  eu-west-1       ec2.eu-west-1.amazonaws.com
      REGION  sa-east-1       ec2.sa-east-1.amazonaws.com
      REGION  us-east-1       ec2.us-east-1.amazonaws.com
      REGION  ap-northeast-1  ec2.ap-northeast-1.amazonaws.com
      REGION  us-west-2       ec2.us-west-2.amazonaws.com
      REGION  us-west-1       ec2.us-west-1.amazonaws.com
      REGION  ap-southeast-1  ec2.ap-southeast-1.amazonaws.com

3. Generate private keys

    Log on to the AWS console, choose the region you want to create keys
    for, click on "Key Pairs" in the menu on the left, and create a key
    pair. If you are creating a key pair for the region ap-southeast-2,
    name the key pair tor-cloud-ap-southeast-2. Upload the key pair to
    the Tor Cloud build server, and give the keys the right set of
    permissions with 'chmod 600 keys/*'.

4. Create a security group

    In AWS, create a security group called "tor-cloud-build" and allow
    SSH inbound. Note that you will need to create this security group in every
    region that you want to create an image for.

5. Build Tor Cloud images

    To build a Tor Cloud image for the region "us-east-1", cd into the
    tor-cloud directory and run the following command:

      root@tor-build:~/tor-cloud# ./build.sh bridge us-east-1 /root/keys/tor-cloud-us-east-1.pem tor-cloud-us-east-1

6. Test the image yourself

    Just before build.sh completes the build process, it prints out the AMI ID
    of the image you just created:

      Registering and publishing the image...
      IMAGE   ami-8939f0e0

    You should be able to find the same image under "IMAGES" and "AMIs" in AWS.

    To test the image, click on "EC2 Dashboard" and "Launch Instance". Select
    "My AMIs" in the box that pops up, and you should see the image you created
    a few minutes ago. 

    Go through the setup process, and wait for your instance to boot up. You'll
    want to wait five minutes or so for the image to boot once, install
    packages, configure Tor, and then reboot.

    Here are some things to look for once you've logged in:

      - Check that Tor is running and check the log file for errors
      - Check that /etc/ec2-prep.sh says that the system has been configured as a Tor bridge
      - Test the bridge yourself

7. Make the images public

    To make the image available to the rest of the world, click on "AMIs" under
    "IMAGES", right click the image you want to make public and select "Edit
    Permissions". Select "Public" and click "Save".

8. Update the Tor Cloud website

    Open tor-cloud/html/index.html and update the AMI ID for the region you
    created the image for. Save the file, commit, push to git and ask someone
    to update https://cloud.torproject.org/.
