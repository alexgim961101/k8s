#!/usr/bin/env bash
#
# 00-create-vms.sh — Multipass로 노드 VM 생성 (호스트에서 실행)
#
# VM 2대(control-plane 1 + worker 1)를 만들고 스크립트를 전송한다.
# HA(CP 3대)로 확장하려면 --cp 3 처럼 개수를 늘린다.
#
# 사용:
#   ./00-create-vms.sh                    # 기본: cp 1 + worker 1
#   ./00-create-vms.sh --cp 3 --worker 2  # HA: cp 3 + worker 2
#   ./00-create-vms.sh --name-prefix lab  # 이름을 lab-cp1, lab-w1 로
#   ./00-create-vms.sh --recreate         # 기존 VM을 지우고 새로 만든다
#
# 전제: macOS 또는 Linux에 multipass 설치 (brew install --cask multipass)
#
set -euo pipefail

CP_COUNT=1
WORKER_COUNT=1
NAME_PREFIX="k8s"
CPUS=2
MEMORY="4G"
DISK="20G"
UBUNTU_RELEASE="24.04"
RECREATE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[경고] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[실패] %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cp)           CP_COUNT="$2"; shift 2 ;;
    --worker)       WORKER_COUNT="$2"; shift 2 ;;
    --name-prefix)  NAME_PREFIX="$2"; shift 2 ;;
    --cpus)         CPUS="$2"; shift 2 ;;
    --memory)       MEMORY="$2"; shift 2 ;;
    --disk)         DISK="$2"; shift 2 ;;
    --release)      UBUNTU_RELEASE="$2"; shift 2 ;;
    --recreate)     RECREATE=1; shift ;;
    -h|--help)      sed -n '2,16p' "$0"; exit 0 ;;
    *) die "알 수 없는 옵션: $1" ;;
  esac
done

command -v multipass >/dev/null || die "multipass가 없다. brew install --cask multipass"

# ---------------------------------------------------------------------------
# 메모리 사전 점검
#
# k8s 노드는 최소 2GB, 컨트롤 플레인은 2 CPU가 필요하다.
# 04단계 HA 실습은 CP 3대가 필요하고, 그때는 노드당 메모리를 2G로 낮춘다.
# ---------------------------------------------------------------------------
log "사전 점검"
echo "multipass   : $(multipass version | head -1 | awk '{print $2}')"
echo "노드 구성    : control-plane ${CP_COUNT}대 + worker ${WORKER_COUNT}대"
echo "노드 사양    : cpu ${CPUS}, memory ${MEMORY}, disk ${DISK}"
echo "Ubuntu      : ${UBUNTU_RELEASE}"

TOTAL_MEM_MB=$(( (CP_COUNT + WORKER_COUNT) * ${MEMORY%G} * 1024 ))
HOST_MEM_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 ))
if [[ "$HOST_MEM_MB" -gt 0 ]]; then
  AVAIL_MB=$(( HOST_MEM_MB - 4096 ))   # 호스트용 4GB 여유
  echo "호스트 메모리: $(( HOST_MEM_MB / 1024 ))GB (VM에 $(( TOTAL_MEM_MB / 1024 ))GB 할당 예정)"
  if [[ "$TOTAL_MEM_MB" -gt "$AVAIL_MB" ]]; then
    warn "호스트 메모리가 빠듯하다. 노드 수를 줄이거나 --memory 2G 로 낮춰라."
  fi
fi

# ---------------------------------------------------------------------------
# VM 생성
# ---------------------------------------------------------------------------
make_node() {
  local name="$1"
  local exists
  exists="$(multipass list --format csv | tail -n +2 | cut -d, -f1 | grep -x "$name" || true)"

  if [[ -n "$exists" ]]; then
    if [[ $RECREATE -eq 1 ]]; then
      log "$name 삭제 후 재생성"
      multipass delete --purge "$name" >/dev/null
    else
      warn "$name 이 이미 있다. 건너뛴다 (재생성하려면 --recreate)"
      return 0
    fi
  fi

  log "$name 생성 (cpu $CPUS, mem $MEMORY, disk $DISK)"
  multipass launch "$UBUNTU_RELEASE" --name "$name" --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" 2>&1 | tail -1
}

CP_NAMES=()
WORKER_NAMES=()
for i in $(seq 1 "$CP_COUNT"); do
  n="${NAME_PREFIX}-cp${i}"
  make_node "$n"
  CP_NAMES+=("$n")
done
for i in $(seq 1 "$WORKER_COUNT"); do
  n="${NAME_PREFIX}-w${i}"
  make_node "$n"
  WORKER_NAMES+=("$n")
done

ALL_NAMES=("${CP_NAMES[@]}" "${WORKER_NAMES[@]}")

# ---------------------------------------------------------------------------
# 설치 스크립트 전송
#
# Multipass 는 cloud-init 으로 부팅 시점에 설치도 가능하지만(27-cloud-init.md 참조),
# 학습 단계에서는 스크립트를 눈으로 보며 단계별로 실행하는 편이 낫다.
# ---------------------------------------------------------------------------
log "설치 스크립트 전송"
for n in "${ALL_NAMES[@]}"; do
  for f in "$SCRIPT_DIR"/*.sh; do
    multipass transfer "$f" "$n:/home/ubuntu/$(basename "$f")"
  done
  echo "  $n ← $(ls -1 "$SCRIPT_DIR"/*.sh | wc -l | tr -d ' ')개"
done

# ---------------------------------------------------------------------------
# 네트워크 검증
#
# k8s 는 노드 간 IP 통신이 필수다. 여기서 실패하면 join 도 실패한다.
# ---------------------------------------------------------------------------
log "네트워크 확인"

multipass list

# macOS 기본 bash 는 3.2 라 declare -A(연관배열)가 없다.
# 노드 이름 → IP 매핑은 파일로 처리해 bash 3.2 에서도 돌아가게 한다.
IP_FILE="$(mktemp)"
trap 'rm -f "$IP_FILE"' EXIT

for n in "${ALL_NAMES[@]}"; do
  ip="$(multipass info "$n" --format csv | tail -1 | cut -d, -f3)"
  [[ -z "$ip" || "$ip" == "--" ]] && die "$n 의 IP를 얻지 못했다. multipass list 로 상태를 확인하라."
  printf '%s %s\n' "$n" "$ip" >>"$IP_FILE"
  echo "  $n : $ip"
done

get_ip() { awk -v n="$1" '$1==n{print $2}' "$IP_FILE"; }

# 노드 간 통신 — 컨트롤 플레인에서 모든 노드로 ping
#
# ⚠️ multipass exec + 출력 리다이렉트 조합은 멈출 수 있다(multipass 1.16.3 에서 확인).
#    `multipass exec vm -- cmd > /dev/null` 이 무한 대기한다.
#    출력을 받아서 쉘에서 판단하는 방식으로 우회한다.
FIRST_CP="${CP_NAMES[0]}"
for n in "${ALL_NAMES[@]}"; do
  [[ "$n" == "$FIRST_CP" ]] && continue
  target="$(get_ip "$n")"
  # 리다이렉트 없이 결과를 변수로 받는다
  result="$(timeout 20 multipass exec "$FIRST_CP" -- ping -c1 -W3 "$target" 2>&1 || true)"
  if printf '%s' "$result" | grep -q '1 received\|1 packets received'; then
    echo "  $FIRST_CP → $n ($target) 통신 OK"
  else
    die "$FIRST_CP → $n ($target) 통신 실패. k8s 노드로 쓸 수 없다.
  출력: $result"
  fi
done

# 외부 인터넷 — 패키지 설치에 필요
result="$(timeout 20 multipass exec "$FIRST_CP" -- ping -c1 -W3 8.8.8.8 2>&1 || true)"
if printf '%s' "$result" | grep -q '1 received\|1 packets received'; then
  echo "  외부 인터넷 OK"
else
  die "외부 인터넷 불가. 프록시 설정이 필요할 수 있다.
  출력: $result"
fi

# ---------------------------------------------------------------------------
# CIDR 충돌 검사
#
# Pod CIDR(기본 10.244.0.0/16)이 노드 대역과 겹치면 라우팅이 조용히 깨진다.
# Calico 기본값(192.168.0.0/16)은 Multipass 대역과 겹치므로 쓰지 않는다.
# ---------------------------------------------------------------------------
log "CIDR 충돌 검사"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
node_cidr="$(get_ip "$FIRST_CP" | cut -d. -f1-3).0/24"
echo "  노드 대역 : $node_cidr"
echo "  Pod 대역  : $POD_CIDR"

python3 - "$node_cidr" "$POD_CIDR" <<'PY' || die "Pod CIDR이 노드 대역과 겹친다. --pod-cidr 로 다른 대역을 지정하라."
import ipaddress, sys
node = ipaddress.ip_network(sys.argv[1])
pod = ipaddress.ip_network(sys.argv[2])
if node.overlaps(pod):
    print(f"  겹침: {node} ∩ {pod}")
    sys.exit(1)
print("  겹치지 않음 OK")
PY

# ---------------------------------------------------------------------------
# join 명령 파일 저장 (편의)
# ---------------------------------------------------------------------------
log "완료"
JOIN_FILE="$SCRIPT_DIR/../ansible/inventory/hosts.ini"
mkdir -p "$(dirname "$JOIN_FILE")"
{
  echo "# 이 파일은 00-create-vms.sh 가 자동 생성한다. 직접 수정하지 않는다."
  echo "# 재생성: ./00-create-vms.sh --recreate 또는 IP가 바뀌었을 때 다시 실행"
  echo
  echo "[control_plane]"
  for i in "${!CP_NAMES[@]}"; do echo "${CP_NAMES[$i]} ansible_host=$(get_ip "${CP_NAMES[$i]}")"; done
  echo
  echo "[workers]"
  for i in "${!WORKER_NAMES[@]}"; do echo "${WORKER_NAMES[$i]} ansible_host=$(get_ip "${WORKER_NAMES[$i]}")"; done
  echo
  echo "[k8s_nodes:children]"
  echo "control_plane"
  echo "workers"
  echo
  echo "[k8s_nodes:vars]"
  echo "ansible_user=ubuntu"
  echo "ansible_python_interpreter=/usr/bin/python3"
  echo
  echo "[all:vars]"
  echo "k8s_minor=v1.37"
} >"$JOIN_FILE"
echo "Ansible 인벤토리 생성: $JOIN_FILE"

cat <<EOF

다음 단계 (Multipass 셸에서 실행):

  # 1. 모든 노드 공통 설치
  for n in ${ALL_NAMES[*]}; do
    multipass exec \$n -- sudo bash /home/ubuntu/00-common.sh
  done

  # 2. 컨트롤 플레인 초기화 (첫 CP 에서만)
  multipass exec ${FIRST_CP} -- sudo bash /home/ubuntu/01-control-plane.sh

  # 3. join 명령을 받아 워커 추가
  JOIN=\$(multipass exec ${FIRST_CP} -- sudo kubeadm token create --print-join-command)
  for n in ${WORKER_NAMES[*]}; do
    multipass exec \$n -- sudo bash /home/ubuntu/02-worker.sh "\$JOIN"
  done

  # 4. 검증
  multipass exec ${FIRST_CP} -- sudo bash /home/ubuntu/03-verify.sh

VM 접속:   multipass shell ${FIRST_CP}
kubectl:   multipass exec ${FIRST_CP} -- sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes
호스트에서: multipass exec ${FIRST_CP} -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/multipass-config

되돌리기: multipass delete --purge ${ALL_NAMES[*]}
EOF
