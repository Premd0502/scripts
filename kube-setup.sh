#!/bin/bash

# Kubernetes Cluster Automation Script
# This script automatically detects and installs the latest stable versions of:
# - containerd
# - runc
# - CNI plugins
# - kubeadm, kubelet, kubectl (with version matching)
# And sets up either a master or worker node based on input

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to display script usage
usage() {
  echo -e "${YELLOW}Usage:${NC}"
  echo -e "  $0 [options]"
  echo -e "${YELLOW}Options:${NC}"
  echo -e "  --master                 Setup as master node"
  echo -e "  --worker <join_command>  Setup as worker node (requires join command from master)"
  echo -e "  --pod-cidr <cidr>        Pod CIDR (default: 192.168.0.0/16)"
  echo -e "  --api-addr <ip>          API server advertise address (default: auto-detect)"
  echo -e "  --node-name <name>       Node name (default: hostname)"
  echo -e "  --help                   Display this help and exit"
  exit 1
}

# Logging helpers
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" >&2; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2; exit 1; }

# Function to safely update apt repositories
safe_apt_update() {
  log "Updating apt repositories..."
  if apt-get update 2>/tmp/apt_update_error; then return 0; fi
  if grep -q "404" /tmp/apt_update_error; then
    warning "Some repositories returned 404. Disabling them..."
    problematic_repos=$(grep -B 1 "404" /tmp/apt_update_error | grep "Err:" | awk '{print $2}')
    for repo in $problematic_repos; do
      repo_file=$(echo "$repo" | sed 's/http[s]*:\/\///' | sed 's/\//_/g')
      sudo touch "/etc/apt/sources.list.d/${repo_file}.disabled"
      if grep -q "$repo" /etc/apt/sources.list; then
        sudo sed -i "s|.*$repo.*|# & # Disabled due to 404|g" /etc/apt/sources.list
      fi
      for file in /etc/apt/sources.list.d/*.list; do
        if grep -q "$repo" "$file"; then
          sudo sed -i "s|.*$repo.*|# & # Disabled due to 404|g" "$file"
        fi
      done
      warning "Disabled repository: $repo"
    done
    apt-get update || warning "Repo update still failing, continuing anyway"
  else
    warning "Non-404 errors in apt update, continuing anyway"
    cat /tmp/apt_update_error
  fi
}

# Parse command line arguments
MASTER=false
WORKER=false
POD_CIDR="192.168.0.0/16"
API_ADDR=""
NODE_NAME=$(hostname)
JOIN_CMD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --master) MASTER=true; shift ;;
    --worker) WORKER=true; JOIN_CMD="$2"; [[ -z "$JOIN_CMD" || "$JOIN_CMD" == --* ]] && error "Join command required"; shift 2 ;;
    --pod-cidr) POD_CIDR="$2"; shift 2 ;;
    --api-addr) API_ADDR="$2"; shift 2 ;;
    --help) usage ;;
    *) error "Unknown parameter: $1" ;;
  esac
done

[[ "$MASTER" == "true" && "$WORKER" == "true" ]] && error "Cannot setup both master and worker on same node"
[[ "$MASTER" == "false" && "$WORKER" == "false" ]] && error "Must specify --master or --worker"

if [[ "$MASTER" == "true" && -z "$API_ADDR" ]]; then
  API_ADDR=$(ip route get 1 | awk '{print $7;exit}')
  log "Auto-detected API server address: $API_ADDR"
fi

# Common setup for all nodes
setup_prerequisites() {
  log "Preparing node prerequisites..."
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

# Install containerd
install_containerd() {
  log "Installing containerd..."
  if command -v containerd &>/dev/null; then log "Already installed: $(containerd --version)"; return; fi
  VER=$(curl -s https://api.github.com/repos/containerd/containerd/releases | grep tag_name | grep -v rc | head -n1 | cut -d'"' -f4 | sed 's/v//')
  VER=${VER:-1.7.11}
  curl -LO https://github.com/containerd/containerd/releases/download/v${VER}/containerd-${VER}-linux-amd64.tar.gz
  tar Cxzvf /usr/local containerd-${VER}-linux-amd64.tar.gz
  curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
  mkdir -p /usr/local/lib/systemd/system/; mv containerd.service /usr/local/lib/systemd/system/
  mkdir -p /etc/containerd; containerd config default | tee /etc/containerd/config.toml
  sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
  systemctl daemon-reload; systemctl enable --now containerd
}

# Install runc
install_runc() {
  log "Installing runc..."
  if command -v runc &>/dev/null; then log "Already installed: $(runc --version)"; return; fi
  VER=$(curl -s https://api.github.com/repos/opencontainers/runc/releases | grep tag_name | grep -v rc | head -n1 | cut -d'"' -f4 | sed 's/v//')
  VER=${VER:-1.1.10}
  curl -LO https://github.com/opencontainers/runc/releases/download/v${VER}/runc.amd64
  install -m 755 runc.amd64 /usr/local/sbin/runc
}

# Install CNI plugins
install_cni() {
  log "Installing CNI plugins..."
  [[ -d "/opt/cni/bin" && -f "/opt/cni/bin/bridge" ]] && { log "CNI already installed"; return; }
  VER=$(curl -s https://api.github.com/repos/containernetworking/plugins/releases | grep tag_name | head -n1 | cut -d'"' -f4 | sed 's/v//')
  VER=${VER:-1.3.0}
  curl -LO https://github.com/containernetworking/plugins/releases/download/v${VER}/cni-plugins-linux-amd64-v${VER}.tgz
  mkdir -p /opt/cni/bin; tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v${VER}.tgz
}

# Install Kubernetes tools
install_kubernetes_tools() {
  log "Installing kubeadm, kubelet, kubectl..."
  if command -v kubeadm &>/dev/null; then
    log "Already installed: $(kubeadm version -o short)"
    return
  fi
  apt-get install -y apt-transport-https ca-certificates curl gpg
  KUBE_MINOR=$(curl -Ls https://dl.k8s.io/release/stable.txt | cut -d'.' -f1,2 | sed 's/v//')
  KUBE_MINOR=${KUBE_MINOR:-1.28}
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  safe_apt_update
  VERSION=$(apt-cache madison kubeadm | awk '{print $3}' | cut -d'-' -f1 | head -n1)
  apt-get install -y kubeadm=${VERSION}-* kubelet=${VERSION}-* kubectl=${VERSION}-*
  apt-mark hold kubeadm kubelet kubectl
  crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock
  crictl config image-endpoint unix:///var/run/containerd/containerd.sock
}

# Setup master
setup_master() {
  log "Initializing control-plane..."
  kubeadm init --pod-network-cidr="$POD_CIDR" --apiserver-advertise-address="$API_ADDR"
  mkdir -p "$HOME/.kube"; cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"; chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  kubeadm token create --print-join-command > /root/kube_join_cmd.sh; chmod +x /root/kube_join_cmd.sh
  log "Join command saved at /root/kube_join_cmd.sh"
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
  log "Master setup complete"
}

# Setup worker
setup_worker() {
  log "Joining worker node..."
  eval "$JOIN_CMD"
}

# Function to install Calico CNI
install_calico() {
  log "Installing Calico CNI"
  CALICO_VERSION=$(curl -L -s https://api.github.com/repos/projectcalico/calico/releases | grep "tag_name" | head -n 1 | cut -d'"' -f4 | sed 's/v//')

  if [[ -z "$CALICO_VERSION" ]]; then
    CALICO_VERSION="3.27.0"
    log "Using default Calico version: $CALICO_VERSION"
  else
    log "Detected Calico version: $CALICO_VERSION"
  fi

  # Apply Tigera operator
  kubectl create -f "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml"

  log "Waiting for Tigera operator and CRDs to be available..."
  # Wait for the CRD 'installations.operator.tigera.io' to exist
  for i in {1..60}; do
    if kubectl get crd installations.operator.tigera.io &>/dev/null; then
      log "CRDs are installed."
      break
    fi
    echo -n "."
    sleep 5
  done

  # Apply Calico custom resources
  curl -sLO "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml"
  kubectl apply -f custom-resources.yaml

  log "Waiting for Calico pods to be ready..."
  timeout=300
  counter=0
  while [[ $(kubectl get pods -n calico-system --no-headers 2>/dev/null | grep -v Running || true) ]]; do
    echo -n "."
    sleep 5
    counter=$((counter + 5))
    if [[ $counter -ge $timeout ]]; then
      warning "Timed out waiting for Calico pods to be ready. Continuing..."
      break
    fi
  done
  echo ""

  log "Calico pods status:"
  kubectl get pods -n calico-system || true
  log "Calico CNI installed successfully"
}

# Main
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

log "Kubernetes setup completed successfully!"
exit 0
