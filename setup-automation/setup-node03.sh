#!/bin/bash
# AWS images set manage_repos=0 since they use RHUI instead of RHSM for repos.
sed -i 's/^manage_repos.*=.*0/manage_repos = 1/' /etc/rhsm/rhsm.conf

# Clear any stale Satellite registration before re-registering
subscription-manager clean || true
sleep 2

curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
KATELLO_INSTALLED=$(rpm -qa | grep -c katello)
if [ $KATELLO_INSTALLED -eq 0 ]; then
  rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm || true
fi
subscription-manager status
if [ $? -ne 0 ]; then
    subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}
fi

# Ensure rhel user has password and sudo
echo "rhel:ansible123!" | chpasswd
echo "rhel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/rhel

dnf install httpd nano -y

cat <<EOF | tee /var/www/html/index.html


<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nothing to See Here</title>
    <style>
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            font-family: Arial, sans-serif;
            background-color: #f8f4e8;
            color: #333;
        }
        h1 {
            font-size: 3em;
            text-align: center;
        }
    </style>
</head>
<body>
    <h1>Nothing to See Here - Not Yet Anyway - Node3</h1>
</body>
</html>

EOF

systemctl start httpd

mkdir /backup
chmod -R 777 /backup
