#!/bin/bash
set -e

# Join the cluster
sudo kubeadm join 192.168.20.51:6443 --token sac9hb.gd6g5g28f8k65uru \
     --discovery-token-ca-cert-hash sha256:33ca8c945449aa08d9996b2049f39821ebf425614785eaeff6e1030bf86d0416