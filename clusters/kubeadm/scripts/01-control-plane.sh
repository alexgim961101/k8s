#!/usr/bin/env bash
#
# 01-control-plane.sh — 컨트롤 플레인 초기화 (첫 노드에서만)
#
#   kubeadm init  → kubeconfig/admin.conf 생성 → Calico CNI 설치 → 클러스터 Ready 확인
#
# 반드시 00-common.sh 를 먼저 실행한 뒤에 실행한다.
#
# 사용:
#   sudo ./01-control-plane.sh
#   sudo ./01-control-plane.sh --name ha-study --endpoint 192.168.64.10 \
#        --pod-cidr 10.244.0.0/16 --skip-cni
#
set -euo pipefail

CLUSTER_NAME="k8s-study"
POD_CIDR="10.244.0.0/16"      # Calico 기본값(192.168.0.0/16)은 UTM/Multipass VM 대역과 겹친다. 반드시 호스트 대역을 피한다.
CONTROL_PLANE_ENDPOINT=""      # 비우면 이 노드의 IP를 자동 감지
APISERVER_ADVERTISE_ADDRESS="" # 비우면 자동 감지
KUBERNETES_VERSION=""          # 비우면 kubeadm이 설치된 버전을 사용. HA 확장 시 명시하는 편이 좋다.
SKIP_CNI=0
CRI_SOCKET="unix:///run/containerd/containerd.sock"
CALICO_VERSION="v3.32.2"
PAUSE_VERSION="3.10.2"         # k8s 1.37 의 sandbox 이미지 태그

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[경고] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[실패] %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        CLUSTER_NAME="$2"; shift 2 ;;
    --pod-cidr)    POD_CIDR="$2"; shift 2 ;;
    --endpoint)    CONTROL_PLANE_ENDPOINT="$2"; shift 2 ;;
    --apiserver-advertise-address) APISERVER_ADVERTISE_ADDRESS="$2"; shift 2 ;;
    --kubernetes-version) KUBERNETES_VERSION="$2"; shift 2 ;;
    --skip-cni)    SKIP_CNI=1; shift ;;
    -h|--help)     sed -n '2,14p' "$0"; exit 0 ;;
    *) die "알 수 없는 옵션: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "root 로 실행해야 한다: sudo $0"
command -v kubeadm >/dev/null || die "kubeadm이 없다. 00-common.sh 를 먼저 실행하라."
[[ -f /var/lib/kubelet/config.yaml ]] && warn "이미 초기화된 노드로 보인다. 재실행하려면 먼저 kubeadm reset"

# ---------------------------------------------------------------------------
# 컨트롤 플레인 주소 결정
#
# --apiserver-advertise-address: 이 노드의 API 서버가 광고할 주소.
# --control-plane-endpoint   : 모든 컨트롤 플레인 노드가 공유할 주소.
#                              단일 노드에서는 같게 두고, HA로 확장할 때
#                              로드밸런서/DNS 주소로 바꾼다.
#                              인증서 SAN에 박히므로 나중에 바꾸려면 인증서 재발급이 필요하다.
# ---------------------------------------------------------------------------
detect_node_ip() {
  local iface
  iface="$(ip -4 route show default | awk '{print $5; exit}')"
  [[ -n "$iface" ]] || die "기본 게이트웨이를 찾을 수 없다. --apiserver-advertise-address 로 직접 지정하라."
  ip -4 addr show "$iface" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
}

NODE_IP="${APISERVER_ADVERTISE_ADDRESS:-$(detect_node_ip)}"
CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-$NODE_IP}"

log "초기화 파라미터"
cat <<EOF
클러스터 이름        : $CLUSTER_NAME
노드 IP              : $NODE_IP
control-plane-endpoint: $CONTROL_PLANE_ENDPOINT
Pod CIDR             : $POD_CIDR
CNI                  : $([[ $SKIP_CNI -eq 1 ]] && echo "건너뜀" || echo "Calico $CALICO_VERSION")
EOF

# ---------------------------------------------------------------------------
# kubeadm 설정 파일
#
# 플래그를 길게 나열하는 대신 YAML로 남긴다. 클러스터를 재현할 때 이 파일 하나면 되고,
# 나중에 HA로 확장할 때 같은 파일에 controlPlaneEndpoint만 바꿔 쓸 수 있다.
# ---------------------------------------------------------------------------
log "kubeadm 설정 파일 생성"

KUBEADM_CONFIG=/root/kubeadm-config.yaml

# 비워두면 kubeadm이 설치된 버전을 쓴다
KUBE_VERSION_LINE=""
if [[ -n "$KUBERNETES_VERSION" ]]; then
  KUBE_VERSION_LINE="kubernetesVersion: ${KUBERNETES_VERSION}"
fi

cat >"$KUBEADM_CONFIG" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: ${CRI_SOCKET}
  imagePullPolicy: IfNotPresent
---
# kubernetesVersion 은 반드시 ClusterConfiguration 안에 있어야 한다.
# 문서 끝에 붙이면 뒤의 KubeletConfiguration 에 들어가 kubeadm 이 거부한다.
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ${CLUSTER_NAME}
${KUBE_VERSION_LINE}
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}:6443
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

cat "$KUBEADM_CONFIG"

# ---------------------------------------------------------------------------
# kubeadm init
#
# 하는 일: PKI 생성 → static pod manifest 배치(/etc/kubernetes/manifests) →
#          etcd/apiserver/scheduler/controller-manager 기동 → 부트스트랩 토큰 발급.
# ---------------------------------------------------------------------------
log "kubeadm init 실행 (이미지 다운로드로 수 분 걸릴 수 있다)"
kubeadm init --config "$KUBEADM_CONFIG" --upload-certs

# ---------------------------------------------------------------------------
# kubectl 사용 설정
#
# admin.conf 는 cluster-admin 권한을 가진 superuser 자격이다. 노드 밖으로 복사하지 않는다.
# ---------------------------------------------------------------------------
log "kubeconfig 설정"

TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

mkdir -p "${TARGET_HOME}/.kube"
cp -f /etc/kubernetes/admin.conf "${TARGET_HOME}/.kube/config"
chown -R "${TARGET_USER}:$(id -gn "$TARGET_USER")" "${TARGET_HOME}/.kube"
chmod 600 "${TARGET_HOME}/.kube/config"

export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# CNI 설치
#
# CNI가 없으면 노드가 NotReady이고 CoreDNS도 뜨지 않는다. 이 단계가 빠지면
# "노드는 보이는데 Pod가 Pending" 상태가 된다.
# ---------------------------------------------------------------------------
if [[ $SKIP_CNI -eq 0 ]]; then
  log "Calico $CALICO_VERSION 설치 (operator 방식)"

  # CRD → operator → IPPool 순서. operator가 먼저 뜨면 CRD를 인식하지 못한다.
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/v1_crd_projectcalico_org.yaml"
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

  # 기본 매니페스트의 IPPool CIDR(192.168.0.0/16)을 --pod-cidr 값으로 맞춘다.
  # kubeadm --pod-subnet 과 Calico IPPool CIDR은 반드시 같아야 한다.
  kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: ${POD_CIDR}
        encapsulation: VXLANCrossSubnet
        # VXLANCrossSubnet: 같은 서브넷이면 직접 라우팅, 다르면 캡슐화.
        # 온프렘/VM 환경에서 무난한 기본값이다.
        natOutgoing: Enabled
        nodeSelector: all()
EOF

  log "Calico 준비 대기"
  for i in $(seq 1 60); do
    if status="$(kubectl get tigerastatus calico -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)" && [[ "$status" == "True" ]]; then
      echo "calico: Available"
      break
    fi
    echo "  대기 중... (${i}/60)"
    sleep 5
  done
  kubectl get tigerastatus || warn "tigerastatus 를 확인하지 못했다"
else
  warn "--skip-cni: CNI를 설치하지 않았다. 노드는 NotReady 상태로 남는다."
fi

# ---------------------------------------------------------------------------
# Ready 확인
# ---------------------------------------------------------------------------
log "클러스터 상태"

kubectl wait --for=condition=Ready node --all --timeout=180s || warn "일부 노드가 Ready가 아니다"
kubectl get nodes -o wide
kubectl get pods -n kube-system

# ---------------------------------------------------------------------------
# 다음 단계 안내
# ---------------------------------------------------------------------------
log "완료"
cat <<EOF

워커 노드를 추가하려면 각 워커에서 00-common.sh 를 실행한 뒤,
아래 명령이 출력하는 join 명령을 그대로 실행한다 (토큰은 기본 24시간 유효):

  sudo kubeadm token create --print-join-command

컨트롤 플레인 노드를 추가할 때는 --control-plane 과 --certificate-key 가 더 필요하다:

  sudo kubeadm token create --print-join-command --ttl 2h
  sudo kubeadm init phase upload-certs --upload-certs

이 노드에 일반 워크로드도 올리려면 (학습용 단일 노드):
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-

설정 파일: ${KUBEADM_CONFIG}
되돌리기 : sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/cni
EOF
