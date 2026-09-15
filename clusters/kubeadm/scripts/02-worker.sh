#!/usr/bin/env bash
#
# 02-worker.sh — 워커 노드를 클러스터에 join (워커에서만)
#
# 반드시 00-common.sh 를 먼저 실행한 뒤에 실행한다.
#
# 사용 (컨트롤 플레인에서 join 명령을 받아 그대로 실행):
#   sudo ./02-worker.sh "kubeadm join 192.168.64.5:6443 --token abcdef.1234567890abcdef \
#        --discovery-token-ca-cert-hash sha256:..."
#
#   # 토큰을 직접 만들고 싶을 때
#   sudo ./02-worker.sh --token abcdef.1234567890abcdef --hash sha256:...
#   # 컨트롤 플레인 노드를 추가할 때
#   sudo ./02-worker.sh "kubeadm join ... --control-plane --certificate-key ..."
#
set -euo pipefail

CRI_SOCKET="unix:///run/containerd/containerd.sock"
JOIN_CMD=""
TOKEN=""
HASH=""
ENDPOINT=""

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[경고] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[실패] %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)    TOKEN="$2"; shift 2 ;;
    --hash)     HASH="$2"; shift 2 ;;
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    -h|--help)  sed -n '2,17p' "$0"; exit 0 ;;
    *)          JOIN_CMD="$*"; break ;;
  esac
done

[[ $EUID -eq 0 ]] || die "root 로 실행해야 한다: sudo $0"
command -v kubeadm >/dev/null || die "kubeadm이 없다. 00-common.sh 를 먼저 실행하라."

# ---------------------------------------------------------------------------
# join 명령 구성
# ---------------------------------------------------------------------------
if [[ -n "$JOIN_CMD" ]]; then
  [[ "$JOIN_CMD" == kubeadm\ join* ]] || die "join 명령은 'kubeadm join ...' 형식이어야 한다"
  echo "전달받은 명령을 실행한다:"
  echo "  $JOIN_CMD"
elif [[ -n "$TOKEN" && -n "$HASH" && -n "$ENDPOINT" ]]; then
  JOIN_CMD="kubeadm join ${ENDPOINT} --token ${TOKEN} --discovery-token-ca-cert-hash ${HASH}"
else
  die "join 명령을 인자로 넘기거나 --endpoint/--token/--hash 를 모두 지정하라"
fi

# --cri-socket 을 명시한다. 런타임이 여러 개거나 자동 감지에 실패하면 join이 중단된다.
if [[ "$JOIN_CMD" != *"--cri-socket"* ]]; then
  JOIN_CMD="$JOIN_CMD --cri-socket ${CRI_SOCKET}"
fi

# ---------------------------------------------------------------------------
# 사전 확인 — 여기서 확인하지 않으면 join이 부분적으로 실패한다
# ---------------------------------------------------------------------------
log "사전 확인"

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  warn "이미 join된 노드로 보인다. 다시 join하려면 컨트롤 플레인에서 노드를 지우고 이 노드에서 kubeadm reset 을 실행한다."
fi

swapon --show --noheadings | grep -q . && die "swap이 켜져 있다. 00-common.sh 를 먼저 실행하라"
[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] || die "net.ipv4.ip_forward=0. 00-common.sh 를 먼저 실행하라"

systemctl is-active --quiet containerd || die "containerd가 실행 중이 아니다"
systemctl is-active --quiet kubelet || {
  log "kubelet 활성화"
  systemctl enable --now kubelet
}

# ---------------------------------------------------------------------------
# join
#
# 하는 일: 컨트롤 플레인에서 CA를 받아 kubelet 인증서를 발급받고
#          kubelet 설정(/var/lib/kubelet/config.yaml)과 kubelet.conf를 배치한다.
# ---------------------------------------------------------------------------
log "kubeadm join 실행"

set +e
$JOIN_CMD
JOIN_RC=$?
set -e

if [[ $JOIN_RC -ne 0 ]]; then
  die "join 실패. 토큰 만료(--token), CA 해시 불일치(--discovery-token-ca-cert-hash),
컨트롤 플레인 6443 포트 도달 여부를 확인하라.
  nc -zv ${ENDPOINT:-<control-plane>} 6443"
fi

log "완료"
cat <<'EOF'

컨트롤 플레인에서 확인:
  kubectl get nodes -o wide
  kubectl get pods -n kube-system

새 노드는 CNI Pod가 뜬 뒤에 Ready가 된다 (수십 초 걸릴 수 있다).
NotReady가 계속되면 CNI(DaemonSet)가 이 노드에 스케줄되었는지 본다:
  kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=<노드이름>
  kubectl describe node <노드이름> | grep -A5 Conditions
EOF
