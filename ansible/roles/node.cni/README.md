Calico CNI role

This role applies the Calico manifest on the cluster using kubectl on the master node.

Usage:
- include role `node.cni` in a play targeting `k8s-master` or `k8s_nodes` (the tasks run only on `k8s-master`).
