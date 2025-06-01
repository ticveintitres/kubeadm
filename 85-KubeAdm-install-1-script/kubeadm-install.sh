#!/bin/bash
## Script hecho con amor para el canal de Youtube @ticveintitres

## Instalacion automatizada de Kubernetes + CRI-O + Calico

##Declaramos las varibles para que sea mas facil de instalar.
##-----------------------------------------------------------------------------------

##Declaramos las variables

# Ver el versionado de Kubernetes aqui: https://kubernetes.io/releases/
KUBERNETES_VERSION=v1.33
# Ver el versionado de CRIO aqui: https://github.com/cri-o/cri-o/releases
CRIO_VERSION=v1.33
# Declarar el CIDR para la red de pods
POD_CIDR="10.23.0.0/16"
# Declarar el CIDR para la red de service
SERVICE_CIDR="10.24.0.0/16"
# Ver el versionado de Calico aqui: https://github.com/projectcalico/calico/releases
CALICO_VERSION=v3.30.0


##### INSTALANDO CONTROLPLANE

##Actualizamos y instalamos paqueteria.
##-------------------------------------------------------
apt update || { echo "Error actualizando paquetes"; exit 1; }
apt install -y software-properties-common curl

curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | tee /etc/apt/sources.list.d/cri-o.list

apt update
apt install -y cri-o kubelet kubeadm kubectl

##Arrancamos los servicios, quitamos el SWAP ..etc
##------------------------------------------------------------------------------------------
systemctl start crio.service
systemctl enable crio.service
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1

##Reiniciar CRIO.
##---------------------
systemctl restart crio.service

# Bashcompletion
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'source <(kubeadm completion bash)' >>~/.bashrc

##Instalamos el cluster de KUBEADM.
##--------------------------------------------------
kubeadm init --pod-network-cidr=$POD_CIDR --service-cidr=$SERVICE_CIDR

##Sacamos el Kubeconfig.
##----------------------------------

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

##Para sacar un token de JOIN.
##----------------------------------------
kubeadm token create --print-join-command

##Instalar Calico.
##---------------------
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml


###### INSTALANDO NODO

## Declaramos las variables
NODE_IP="192.168.88.251"
NODE_USER=root
JOIN_CMD=$(kubeadm token create --print-join-command)

## Configurar igual que en el Controlplane

ssh "$NODE_USER@$NODE_IP" bash -s <<EOF
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
apt update || { echo "Error actualizando paquetes"; exit 1; }
apt install -y software-properties-common curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" | tee /etc/apt/sources.list.d/cri-o.list
apt update
apt install -y cri-o kubelet kubeadm kubectl
systemctl start crio.service
systemctl enable crio.service
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'source <(kubeadm completion bash)' >>~/.bashrc
EOF

# Join el nodo al cluster
ssh "$NODE_USER@$NODE_IP" bash -s <<EOF
$JOIN_CMD
EOF

bash