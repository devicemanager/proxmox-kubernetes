#!/bin/bash
# scripts/init-cluster.sh
# Helper script to initialize the cluster from your workstation

set -e

MASTER_IP="${1:-192.168.20.51}"
WORKER_IP="${2:-192.168.20.52}"

echo "=== Initializing Kubernetes Cluster ==="
echo "Master: ${MASTER_IP}"
echo "Worker: ${WORKER_IP}"

# Initialize master
echo "Initializing master node..."
ssh debian@${MASTER_IP} "sudo /root/init-cluster.sh"

# Install Calico CNI
echo "Installing Calico CNI..."
ssh debian@${MASTER_IP} "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.3/manifests/calico.yaml"

# Wait for Calico to be ready
echo "Waiting for Calico pods to be ready..."
ssh debian@${MASTER_IP} "kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s"

# Get join command
echo "Getting join command..."
JOIN_CMD=$(ssh debian@${MASTER_IP} "sudo cat /root/join-command.txt")

# Join worker
echo "Joining worker node..."
ssh debian@${WORKER_IP} "sudo ${JOIN_CMD}"

# Verify cluster
echo "Verifying cluster..."
ssh debian@${MASTER_IP} "sudo kubectl get nodes"

echo "Cluster initialized successfully!"
