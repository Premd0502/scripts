#!/bin/bash

# Kubernetes Cluster Automation Script (Latest Always Install)
# Supports:
# - Setup master (--master)
# - Setup worker (--worker <join_command>)
# - Cleanup (--cleanup)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Logging helpers
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" >&2; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2; exit 1; }

usage() {
  echo -e "${YELLOW}Usage:${NC}"
  echo -e "  $0 [options]"
  echo -e "Options:"
  echo -e "  --master                 Setup as master node"
  echo -e "  --worker <join_command>  Setup as worker node"
  echo -e "  --pod-cidr <cidr>        Pod CIDR (default: 192.168.0.0/16)"
  echo -e "  --api-addr <ip>          API server advertise address"
  echo -e "  --cleanup                Cleanup and reset node"
  echo -e "  --help                   Show this help"
  exit 1
}

# Args
MASTER=false
WORKER=false
CLEANUP=false
POD_CIDR="192.168.0.0/16"
API_ADDR=""
NODE_NAME=$(hostname)
JOIN_CMD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --master) MASTER=true; shift ;;
    --worker) WORKER=true; JOIN_CMD="$2"; shift 2 ;;
    --cleanup) CLEANUP=true; shift ;;
    --pod-cidr) POD_CIDR="$2"; shift 2 ;;
    --api-addr) API_ADDR="$2"; shift 2 ;;
    --help) usage ;;
    *) error "Unknown parameter: $1" ;;
  esac
done

# ---------------- CLEANUP FUNCTION ----------------
cleanup_node() {
  [[ $EUID -ne 0 ]] && error "Run as root or with sudo"
  log "Resetting kubeadm..."
  kubeadm reset -f || true

  log "Stopping services..."
  systemctl stop kubelet || true
  systemctl stop containerd || true

  log "Removing Kubernetes packages..."
  apt-get purge -y kubeadm kubelet kubectl || true
  apt-get autoremove -y
  apt-mark unhold kubeadm kubelet kubectl || true

  log "Removing containerd and runc..."
  systemctl disable containerd || true
  rm -rf /usr/local/bin/containerd* /usr/local/sbin/runc \
         /usr/local/lib/systemd/system/containerd.service

  log "Cleaning up configs..."
  rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd \
         /etc/containerd /var/lib/containerd \
         /opt/cni /etc/cni \
         /root/.kube $HOME/.kube

  log "Flushing iptables and CNI links..."
  iptables -F || true
  iptables -t nat -F || true
  iptables -t mangle -F || true
  iptables -X || true
  ip link delete cni0 || true
  ip link delete flannel.1 || true
  ip link delete tunl0 || true

  log "Reloading networking..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl restart networking || true

  log "Cleanup complete."
  exit 0
}

# If cleanup is requested, run and exit
if [[ "$CLEANUP" == "true" ]]; then
  cleanup_node
fi

# ---------------- PREREQUISITES ----------------
setup_prerequisites() {
  log "Preparing node..."
  [[ $EUID -ne 0 ]] && error "Run as root or with sudo"
  swapoff -a; sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  modprobe overlay; modprobe br_netfilter
  cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system
}

# ---------------- INSTALLERS ----------------
install_containerd() {
  log "Installing containerd..."
  VER=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//')
  VER=${VER:-1.7.11}
  curl -LO https://github.com/containerd/containerd/releases/download/v${VER}/containerd-${VER}-linux-amd64.tar.gz
  tar Cxzvf /usr/local containerd-${VER}-linux-amd64.tar.gz
  curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
  mkdir -p /usr/local/lib/systemd/system/; mv containerd.service /usr/local/lib/systemd/system/
  mkdir -p /etc/containerd; containerd config default | tee /etc/containerd/config.toml
  sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
  systemctl daemon-reload; systemctl enable --now containerd
}

install_runc() {
  log "Installing runc..."
  VER=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//')
  VER=${VER:-1.1.10}
  curl -LO https://github.com/opencontainers/runc/releases/download/v${VER}/runc.amd64
  install -m 755 runc.amd64 /usr/local/sbin/runc
}

install_cni() {
  log "Installing CNI plugins..."
  VER=$(curl -s https://api.github.com/repos/containernetworking/plugins/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//')
  VER=${VER:-1.3.0}
  curl -LO https://github.com/containernetworking/plugins/releases/download/v${VER}/cni-plugins-linux-amd64-v${VER}.tgz
  mkdir -p /opt/cni/bin; tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v${VER}.tgz
}

install_kubernetes_tools() {
  log "Installing Kubernetes tools..."
  apt-get install -y apt-transport-https ca-certificates curl gpg
  KUBE_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt | cut -d'.' -f1,2 | sed 's/v//')
  MAJOR_MINOR=$(echo "$KUBE_VERSION" | cut -d '.' -f1,2 | sed 's/v//')
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${MAJOR_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${MAJOR_MINOR}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubeadm kubelet kubectl
  systemctl enable --now kubelet
  crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock
  crictl config image-endpoint unix:///var/run/containerd/containerd.sock
}

# ---------------- MASTER/WORKER ----------------
setup_master() {
  log "Initializing master..."
  [[ -z "$API_ADDR" ]] && API_ADDR=$(ip route get 1 | awk '{print $7;exit}')
  kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-advertise-address="$API_ADDR"
  mkdir -p "$HOME/.kube"; cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"; chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  kubeadm token create --print-join-command > /root/kube_join_cmd.sh; chmod +x /root/kube_join_cmd.sh
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
}

setup_worker() {
  log "Joining worker node..."
  eval "$JOIN_CMD"
}

install_calico() {
  log "Installing Calico..."
  CALICO_VERSION=$(curl -s https://api.github.com/repos/projectcalico/calico/releases/latest | grep "tag_name" | head -n 1 | cut -d'"' -f4 | sed 's/v//')
  CALICO_VERSION=${CALICO_VERSION:-3.27.0}
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml"
  for i in {1..60}; do
    if kubectl get crd installations.operator.tigera.io &>/dev/null; then break; fi
    sleep 5
  done
  curl -sLO "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml"
  kubectl apply -f custom-resources.yaml
  kubectl get pods -n calico-system || true
}

# ---------------- MAIN ----------------
log "Starting Kubernetes setup..."

setup_prerequisites
install_containerd
install_runc
install_cni
install_kubernetes_tools

if [[ "$MASTER" == "true" ]]; then
  setup_master
  install_calico
elif [[ "$WORKER" == "true" ]]; then
  setup_worker
fi

log "Kubernetes setup completed!"
exit 0

