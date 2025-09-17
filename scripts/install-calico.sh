#!/bin/bash
set -e

# Install the Calico operator and custom resource definitions
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/tigera-operator.yaml

# Wait for the operator to be ready
kubectl wait --for=condition=ready pod -l name=tigera-operator -n tigera-operator --timeout=60s

# Create custom resources for Calico configuration
cat << EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  registry: docker.io
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Wait for Calico to be ready
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=120s