#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -f "${SCRIPT_ROOT}/env.sh" ]; then
  source "${SCRIPT_ROOT}/env.sh"
fi

export KUBE_DOCKER_REGISTRY="${KUBE_DOCKER_REGISTRY:-10.145.208.152:5000}"
export KUBE_DOCKER_IMAGE_TAG="${KUBE_DOCKER_IMAGE_TAG:-v1.7.0-test392}"
export KUBE_ROOT="${KUBE_ROOT:-$GOPATH/src/k8s.io/kubernetes}"

pushd $KUBE_ROOT

make quick-release

mkdir -p ${SCRIPT_ROOT}/${KUBE_DOCKER_IMAGE_TAG}/node-bins

cat <<EOF >${SCRIPT_ROOT}/${KUBE_DOCKER_IMAGE_TAG}/kubelet.service
# /lib/systemd/system/kubelet.service
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >${SCRIPT_ROOT}/${KUBE_DOCKER_IMAGE_TAG}/10-kubeadm.conf
# /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf --require-kubeconfig=true"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
# Environment="KUBELET_NETWORK_ARGS=\"\""
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_DNS_ARGS \$KUBELET_AUTHZ_ARGS \$KUBELET_EXTRA_ARGS
EOF

BIN_DIR=$KUBE_ROOT/_output/release-stage/server/linux-amd64/kubernetes/server/bin
cp $BIN_DIR/kubeadm $BIN_DIR/kubectl $BIN_DIR/kubelet ${SCRIPT_ROOT}/${KUBE_DOCKER_IMAGE_TAG}/node-bins

#upload files to swift bucket
pushd ${SCRIPT_ROOT}/${KUBE_DOCKER_IMAGE_TAG}
swift upload $KUBE_DOCKER_IMAGE_TAG .
popd


# export KUBE_DOCKER_REGISTRY=10.145.208.152:5000
# export KUBE_DOCKER_IMAGE_TAG=v1.7.0-test392
docker images |grep -v hyperkube |grep $KUBE_DOCKER_IMAGE_TAG | awk '{print "docker push "$1":"$2}' | bash

# figureout etcd image version
export etcdVersion=$(grep "etcdVersion =" cmd/kubeadm/app/images/images.go |grep -oE "[0-9\.]+")

# pull etcd image and tag change repo prefix
docker pull "gcr.io/google_containers/etcd-amd64:$etcdVersion"
docker tag "gcr.io/google_containers/etcd-amd64:$etcdVersion" "$KUBE_DOCKER_REGISTRY/etcd-amd64:$etcdVersion"
docker push "$KUBE_DOCKER_REGISTRY/etcd-amd64:$etcdVersion"

export KubeDNSVersion=$(grep KubeDNSVersion cmd/kubeadm/app/phases/addons/manifests.go | grep -oE "[0-9\.]+")
for COMPONENT in sidecar kube-dns dnsmasq-nanny
do
  echo "pull/re-tag/push for k8s-dns-$COMPONENT-amd64:$KubeDNSVersion"
  docker pull "gcr.io/google_containers/k8s-dns-$COMPONENT-amd64:$KubeDNSVersion"
  docker tag "gcr.io/google_containers/k8s-dns-$COMPONENT-amd64:$KubeDNSVersion" "$KUBE_DOCKER_REGISTRY/k8s-dns-$COMPONENT-amd64:$KubeDNSVersion"
  docker push "$KUBE_DOCKER_REGISTRY/k8s-dns-$COMPONENT-amd64:$KubeDNSVersion"
done

popd
