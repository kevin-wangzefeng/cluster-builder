#!/bin/bash
echo "$(hostname) 127.0.0.1" >> /etc/hosts

sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config


cp -f /home/ubuntu/.ssh/authorized_keys /root/.ssh/
service ssh restart
passwd root<<EOF
root
root
EOF
apt-get update
apt-get install -y python python-pip

# install openstack relevant clients
sudo pip install -U --force 'python-openstackclient==2.4.0'
sudo pip install -U --force 'python-heatclient==1.1.0'
sudo pip install -U --force 'python-swiftclient==3.0.0'
sudo pip install -U --force 'python-glanceclient==2.0.0'
sudo pip install -U --force 'python-novaclient==3.4.0'


# prepare for docker installation
apt-get install -y apt-transport-https

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
# Install docker if you don't have it already.
# Install ebtables socat for kubeadm
apt-get install -y docker-engine ebtables socat kubernetes-cni

# set private docker registry
cat <<EOF >/etc/docker/daemon.json
{ "insecure-registries":["10.145.208.152:5000"] }
EOF

systemctl restart docker


export OS_USERNAME=kevin
export OS_PASSWORD=kevin
export OS_TENANT_NAME=kevin
export OS_AUTH_URL=http://10.145.208.11:35357/v3
export OS_IDENTITY_API_VERSION=3

if [[ "${swift_bucket}_xxx" != "_xxx" ]]; then
  echo "download kubeadm kubelet binaries from swift bucket ${swift_bucket}"
  DOWNLOAD_TMP=/home/${swift_bucket}
  mkdir -p  $DOWNLOAD_TMP
  swift download ${swift_bucket} -D $DOWNLOAD_TMP

  chmod +x -R $DOWNLOAD_TMP/node-bins/
  mv $DOWNLOAD_TMP/node-bins/* /usr/bin

  mkdir -p /etc/systemd/system/kubelet.service.d/
  mv $DOWNLOAD_TMP/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/
  mv $DOWNLOAD_TMP/kubelet.service /lib/systemd/system/
  systemctl daemon-reload
else
  echo "fetching kubeadm and kubelet binaries through apt-get"
  apt-get install -y kubeadm kubelet
fi

node_labels=${node_labels}
node_taints=${node_taints}

echo "Label nodes"
if [ -n "$node_labels" ]
then
    sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--node-labels=$node_labels |g" \
       /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
fi

echo "Taint nodes"
if [ -n "$node_taints" ]
then
    sed -i "s|KUBELET_KUBECONFIG_ARGS=|KUBELET_KUBECONFIG_ARGS=--register-with-taints=$node_taints |g" \
       /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
fi
systemctl daemon-reload
systemctl restart kubelet

echo "Trying to join master..."
kubeadm join --token ${kubeadm_token} "${master_ip}:6443"
