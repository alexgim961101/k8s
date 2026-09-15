#!/usr/bin/env bash
#
# 03-verify.sh — 클러스터 설치 검증 (컨트롤 플레인에서 실행)
#
# 노드 Ready, 컨트롤 플레인 static pod, CNI, CoreDNS, Pod 간 통신,
# 노드 간 필수 포트를 순서대로 확인한다.
#
# 사용:
#   ./03-verify.sh
#   ./03-verify.sh --skip-network-test
#
set -uo pipefail

SKIP_NETWORK_TEST=0
for arg in "$@"; do
  case "$arg" in
    --skip-network-test) SKIP_NETWORK_TEST=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

PASS=0
FAIL=0

ok()   { printf '  \033[1;32m[OK]\033[0m   %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[1;33m[WARN]\033[0m %s\n' "$*"; }
head_() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

command -v kubectl >/dev/null || { echo "kubectl이 없다"; exit 1; }

# ---------------------------------------------------------------------------
head_ "1. 노드 상태"
# ---------------------------------------------------------------------------
kubectl get nodes -o wide

not_ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}')"
if [[ -z "$not_ready" ]]; then
  ok "모든 노드가 Ready"
else
  bad "Ready가 아닌 노드: $not_ready"
  echo "     NotReady 원인의 대부분은 CNI 미설치다. 다음을 확인한다:"
  echo "       kubectl get pods -n kube-system -o wide | grep -E 'calico|cilium|flannel'"
  echo "       kubectl describe node <노드> | sed -n '/Conditions/,/Addresses/p'"
fi

# ---------------------------------------------------------------------------
head_ "2. 컨트롤 플레인 / kube-system Pod"
# ---------------------------------------------------------------------------
kubectl get pods -n kube-system -o wide

for name in kube-apiserver kube-scheduler kube-controller-manager etcd; do
  if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q "^${name}.*Running"; then
    ok "$name Running"
  else
    bad "$name 이 Running 이 아니다 (static pod)"
  fi
done

if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q '^coredns.*Running'; then
  ok "CoreDNS Running"
else
  bad "CoreDNS 가 Running 이 아니다 — CNI가 없으면 여기서 멈춘다"
fi

# ---------------------------------------------------------------------------
head_ "3. static pod manifest"
# ---------------------------------------------------------------------------
if [[ -d /etc/kubernetes/manifests ]]; then
  ls -1 /etc/kubernetes/manifests
  count="$(ls -1 /etc/kubernetes/manifests | wc -l | tr -d ' ')"
  ok "/etc/kubernetes/manifests 에 static pod manifest ${count}개"
else
  bad "/etc/kubernetes/manifests 가 없다 — 이 노드는 컨트롤 플레인이 아니다"
fi

# ---------------------------------------------------------------------------
head_ "4. kubelet / containerd / cgroup driver"
# ---------------------------------------------------------------------------
for svc in kubelet containerd; do
  if systemctl is-active --quiet "$svc"; then
    ok "$svc active"
  else
    bad "$svc inactive — journalctl -u $svc -n 50"
  fi
done
kubelet_driver="$(grep -E '^cgroupDriver:' /var/lib/kubelet/config.yaml 2>/dev/null | awk '{print $2}')"
containerd_driver="$(grep -c 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null || echo 0)"
if [[ "$kubelet_driver" == "systemd" && "$containerd_driver" -gt 0 ]]; then
  ok "cgroup driver 일치 (systemd)"
else
  bad "cgroup driver 불일치: kubelet=${kubelet_driver:-?} containerd SystemdCgroup=${containerd_driver}"
fi

# crictl 은 런타임과 직접 대화하므로 kubelet 이 죽었을 때 유일한 단서가 된다.
# root 가 아니면 쓰기(소켓 접근)가 막힐 수 있어 sudo 로 확인한다.
if sudo crictl ps >/dev/null 2>&1; then
  ok "crictl 로 컨테이너 런타임 조회 가능"
else
  bad "crictl 이 containerd 에 접속하지 못한다 (sudo crictl ps / systemctl status containerd)"
fi

# ---------------------------------------------------------------------------
head_ "5. 노드 간 필수 포트"
# ---------------------------------------------------------------------------
# 6443(kube-apiserver)은 컨트롤 플레인에만 있다. 워커에 요구하면 안 된다.
# 10250(kubelet API)은 모든 노드에 있다.
# ---------------------------------------------------------------------------
cp_nodes="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')"
node_ips="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')"
[[ -z "$cp_nodes" ]] && cp_nodes="$node_ips"

for ip in $cp_nodes; do
  if nc -z -w2 "$ip" 6443 2>/dev/null; then
    ok "$ip:6443 (kube-apiserver) 도달 — 컨트롤 플레인"
  else
    bad "$ip:6443 도달 실패 — 컨트롤 플레인인데 apiserver 가 안 듣는다"
  fi
done

for ip in $node_ips; do
  if nc -z -w2 "$ip" 10250 2>/dev/null; then
    ok "$ip:10250 (kubelet API) 도달"
  else
    bad "$ip:10250 도달 실패 — kubelet 또는 방화벽 확인"
  fi
done

# 워커에서 컨트롤 플레인의 apiserver 로 실제 접속되는지 (join 이 된 이유)
if kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | grep -q .; then
  ok "워커 노드가 등록됨 — 컨트롤 플레인 $(echo "$cp_nodes" | head -1):6443 접속 확인됨"
fi

# ---------------------------------------------------------------------------
if [[ $SKIP_NETWORK_TEST -eq 0 ]]; then
head_ "6. Pod 간 통신 / DNS"
# ---------------------------------------------------------------------------

cleanup() {
  kubectl delete pod netcheck-a netcheck-b -n default --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl delete pod netcheck-a netcheck-b -n default --ignore-not-found >/dev/null 2>&1

kubectl run netcheck-a --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --restart=Never --command -- /agnhost netexec --http-port=8080 >/dev/null
kubectl run netcheck-b --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --restart=Never --command -- /agnhost netexec --http-port=8080 >/dev/null

if kubectl wait --for=condition=Ready pod/netcheck-a pod/netcheck-b --timeout=120s >/dev/null 2>&1; then
  ok "테스트 Pod 2개 Ready"

  # Pod IP 직접 통신 (CNI 데이터플레인)
  b_ip="$(kubectl get pod netcheck-b -o jsonpath='{.status.podIP}')"
  if kubectl exec netcheck-a -- /agnhost connect --timeout=5s --protocol=tcp "${b_ip}:8080" >/dev/null 2>&1; then
    ok "Pod → Pod IP 통신 ($b_ip:8080)"
  else
    bad "Pod IP 통신 실패 — CNI 라우팅/캡슐화 확인"
  fi

  # Service / DNS (kube-proxy + CoreDNS)
  if kubectl exec netcheck-a -- /agnhost connect --timeout=5s --protocol=tcp kubernetes.default.svc:443 >/dev/null 2>&1; then
    ok "DNS + Service 통신 (kubernetes.default.svc)"
  else
    bad "Service/DNS 통신 실패 — kube-proxy, CoreDNS, iptables 확인"
  fi
else
  bad "테스트 Pod가 Ready가 되지 않았다"
  kubectl describe pod netcheck-a | tail -30
fi
fi

# ---------------------------------------------------------------------------
head_ "결과"
# ---------------------------------------------------------------------------
printf '통과 %d / 실패 %d\n' "$PASS" "$FAIL"
if [[ $FAIL -eq 0 ]]; then
  printf '\033[1;32m설치 검증 통과\033[0m\n'
  exit 0
else
  printf '\033[1;31m실패 항목을 먼저 해결하라\033[0m\n'
  exit 1
fi
