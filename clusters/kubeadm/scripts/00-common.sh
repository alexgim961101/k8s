#!/usr/bin/env bash
#
# 00-common.sh — 모든 노드 공통 준비
#
# 컨트롤 플레인과 워커 모두에서 1회 실행한다.
#   - 커널 모듈(br_netfilter, overlay) / sysctl(ip_forward, bridge-nf-call-iptables)
#   - swap 비활성화
#   - containerd 2.x + runc + CNI 플러그인 + crictl
#   - kubelet / kubeadm / kubectl 설치 (kubelet은 아직 실행하지 않는다)
#
# 사용:
#   sudo ./00-common.sh
#   sudo K8S_MINOR=v1.37 CONTAINERD_VERSION=v2.3.5 ./00-common.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# 설치 버전 — 필요하면 환경변수로 덮어쓴다.
# kubelet/kubeadm/kubectl은 반드시 같은 마이너 버전이어야 한다.
# ---------------------------------------------------------------------------
K8S_MINOR="${K8S_MINOR:-v1.37}"                 # 패키지 저장소 마이너 버전
CONTAINERD_VERSION="${CONTAINERD_VERSION:-v2.3.5}"
RUNC_VERSION="${RUNC_VERSION:-v1.5.1}"
CNI_PLUGINS_VERSION="${CNI_PLUGINS_VERSION:-v1.9.1}"
CRICTL_VERSION="${CRICTL_VERSION:-v1.37.0}"
PAUSE_VERSION="${PAUSE_VERSION:-3.10.2}"          # k8s 1.37 의 sandbox 이미지 태그

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[경고] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[실패] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root 로 실행해야 한다: sudo $0"

# ---------------------------------------------------------------------------
# 0. 사전 확인
# ---------------------------------------------------------------------------
log "사전 확인"

# 이 노드가 이미 클러스터에 참여 중이면 kubelet/containerd를 재시작하지 않는다.
# (재시작하면 그 노드의 Pod가 모두 흔들린다)
NODE_IN_CLUSTER=0
[[ -f /etc/kubernetes/kubelet.conf ]] && NODE_IN_CLUSTER=1
if [[ $NODE_IN_CLUSTER -eq 1 ]]; then
  warn "이미 클러스터에 참여한 노드다. 설치된 패키지를 유지하고 실행 중인 서비스는 재시작하지 않는다."
  warn "노드를 초기화하고 다시 설치하려면 먼저 kubeadm reset 을 실행하라."
fi

. /etc/os-release
ARCH="$(dpkg --print-architecture)"            # amd64 | arm64
case "$ARCH" in
  amd64|arm64) ;;
  *) die "지원하지 않는 아키텍처: $ARCH" ;;
esac
[[ "$ID" == "ubuntu" || "$ID_LIKE" == *debian* ]] || die "Debian/Ubuntu 계열만 지원한다 (현재: $ID)"

echo "OS      : $PRETTY_NAME"
echo "Arch    : $ARCH"
echo "Kernel  : $(uname -r)"
echo "Host    : $(hostname)"
echo "K8s     : $K8S_MINOR"
echo "containerd: $CONTAINERD_VERSION"

# 노드마다 hostname / product_uuid / MAC이 유일해야 한다 (kubeadm이 노드 식별에 쓴다)
cat /sys/class/dmi/id/product_uuid >/dev/null 2>&1 || warn "product_uuid를 읽을 수 없다"

log "필수 패키지 설치"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  apt-transport-https ca-certificates curl gpg gnupg lsb-release \
  conntrack socat ebtables ethtool iproute2 ipset iptables kmod \
  jq netcat-openbsd nfs-common open-iscsi \
  >/dev/null

# ---------------------------------------------------------------------------
# 1. 커널 모듈과 sysctl
#
# containerd/runc가 overlayfs를 쓰므로 overlay가,
# Service 트래픽을 iptables로 처리하므로 br_netfilter가 필요하다.
# br_netfilter만 로드하면 bridge를 지나는 패킷이 iptables를 거치게 되지만
# IPv4 포워딩은 별도로 켜야 한다.
# ---------------------------------------------------------------------------
log "커널 모듈과 sysctl 설정"

cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null

# 적용 확인 — 여기서 0이 나오면 이후 Pod 통신이 깨진다
[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] || die "net.ipv4.ip_forward 적용 실패"
[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == "1" ]] || die "bridge-nf-call-iptables 적용 실패"

# ---------------------------------------------------------------------------
# 2. swap 비활성화
#
# kubelet은 기본적으로 swap이 켜져 있으면 아예 시작하지 않는다(failSwapOn).
# fstab에서 지워 재부팅 후에도 유지되게 한다.
# ---------------------------------------------------------------------------
log "swap 비활성화"

swapoff -a
# swap 라벨이 붙은 fstab 라인을 주석 처리한다.
# 정규식이 이미 주석인 줄(#으로 시작)은 건드리지 않으므로 몇 번 실행해도 안전하다.
sed -i -E 's/^([^#].*[[:space:]]swap[[:space:]].*)$/# \1/' /etc/fstab
systemctl mask swap.target >/dev/null 2>&1 || true

if [[ -n "$(swapon --show --noheadings)" ]]; then
  die "swap이 아직 활성화되어 있다"
fi

# ---------------------------------------------------------------------------
# 3. containerd 2.x
#
# 배포판 패키지 대신 공식 tarball을 쓴다. 버전이 고정되고 노드마다 동일해진다.
# (cgroup v2를 쓰는 Ubuntu 24.04에서는 systemd cgroup driver가 권장이다)
# ---------------------------------------------------------------------------
log "containerd $CONTAINERD_VERSION 설치"

# 배포판 패키지로 containerd가 이미 깔려 있으면 그 바이너리를 먼저 지운다.
# 남아 있으면 PATH/유닛 우선순위가 엇갈려 엉뚱한 버전이 소켓을 잡는다.
if [[ -x /usr/bin/containerd && ! -x /usr/local/bin/containerd ]]; then
  warn "/usr/bin/containerd(배포판 패키지)를 발견했다. systemd 유닛을 정리하고 공식 tarball로 교체한다."
  systemctl stop containerd >/dev/null 2>&1 || true
  apt-get remove -y -qq containerd containerd.io >/dev/null 2>&1 || true
  rm -f /usr/bin/containerd /usr/bin/ctr /usr/bin/containerd-shim-runc-v2
fi

if [[ ! -x /usr/local/bin/containerd ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "https://github.com/containerd/containerd/releases/download/${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION#v}-linux-${ARCH}.tar.gz" \
    -o "$TMP/containerd.tgz"
  tar -C /usr/local -xzf "$TMP/containerd.tgz"
fi
/usr/local/bin/containerd --version

# systemd 유닛 디렉터리가 없는 배포판이 있다. mkdir 없이 리다이렉트하면
# curl 이 "(23) Failure writing output to destination" 으로 실패한다.
mkdir -p /usr/local/lib/systemd/system
curl -fsSL "https://raw.githubusercontent.com/containerd/containerd/${CONTAINERD_VERSION}/containerd.service" \
  -o /usr/local/lib/systemd/system/containerd.service

# config.toml이 없을 때만 생성한다. 있으면 아래 cgroup driver 패치만 적용한다.
if [[ ! -f /etc/containerd/config.toml ]]; then
  mkdir -p /etc/containerd
  /usr/local/bin/containerd config default >/etc/containerd/config.toml
else
  # containerd 1.x는 version = 2, 2.x는 version = 3 을 쓴다.
  # 버전이 낮은 설정을 그대로 두면 플러그인 키가 어긋나 CRI가 동작하지 않는다.
  cfg_version="$(grep -E '^version[[:space:]]*=' /etc/containerd/config.toml | head -1 | awk -F= '{gsub(/[^0-9]/,"",$2); print $2}')"
  if [[ -z "$cfg_version" || "$cfg_version" -lt 3 ]]; then
    warn "기존 config.toml 이 containerd 2.x 형식이 아니다(version=${cfg_version:-?}). 백업 후 재생성한다."
    mv /etc/containerd/config.toml "/etc/containerd/config.toml.bak.$(date +%s)"
    /usr/local/bin/containerd config default >/etc/containerd/config.toml
  fi
fi

# cgroup driver를 systemd로 맞춘다. kubelet과 런타임이 다른 드라이버를 쓰면
# 자원 관리가 두 갈래로 나뉘어 리소스 압박 상황에서 노드가 불안정해진다.
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi
grep -q "SystemdCgroup = true" /etc/containerd/config.toml \
  || die "containerd config.toml 에 SystemdCgroup을 설정하지 못했다"

# CRI 플러그인이 꺼져 있으면 kubelet이 노드를 등록하지 못한다.
if grep -qE '^[[:space:]]*disabled_plugins[[:space:]]*=.*"cri"' /etc/containerd/config.toml; then
  die "containerd config.toml 에서 cri 플러그인이 비활성화되어 있다"
fi

# sandbox(pause) 이미지를 Kubernetes 버전에 맞게 고정한다.
# containerd 기본값과 kubeadm이 기대하는 값이 어긋나면 Pod가 절대 뜨지 않는다.
if grep -qE "^[[:space:]]*sandbox_image[[:space:]]*=" /etc/containerd/config.toml; then
  sed -i -E "s|^([[:space:]]*sandbox_image[[:space:]]*=).*|\1 \"registry.k8s.io/pause:${PAUSE_VERSION}\"|" \
    /etc/containerd/config.toml
fi
grep -q "registry.k8s.io/pause:${PAUSE_VERSION}" /etc/containerd/config.toml \
  || warn "sandbox_image를 ${PAUSE_VERSION}(으)로 고정하지 못했다. containerd 기본값을 사용한다."

# 최종 확인: CRI 런타임 플러그인 블록이 실제로 있어야 한다.
grep -q "containerd.runtimes.runc" /etc/containerd/config.toml \
  || die "config.toml 에 runc 런타임 설정이 없다"

systemctl daemon-reload
systemctl enable containerd
if [[ $NODE_IN_CLUSTER -eq 1 ]]; then
  # 이미 클러스터에 참여 중이면 건드리지 않는다. 설정을 바꿨다면 수동으로 재시작한다.
  echo "containerd 재시작 생략 (클러스터 참여 중). 설정을 바꿨다면: sudo systemctl restart containerd"
else
  # restart를 쓴다. 이전에 다른 containerd가 떠 있었다면 enable --now 만으로는
  # 바이너리가 바뀌지 않는다.
  systemctl restart containerd
fi
sleep 1
systemctl is-active --quiet containerd || die "containerd 기동 실패"

# 실행 중인 프로세스가 정말 우리가 설치한 바이너리인지 확인한다.
# 배포판 패키지의 containerd가 남아 있으면 조용히 다른 버전이 동작한다.
RUNNING_BIN="$(readlink -f "/proc/$(pgrep -x containerd | head -1)/exe" 2>/dev/null || true)"
if [[ "$RUNNING_BIN" != "/usr/local/bin/containerd" ]]; then
  warn "실행 중인 containerd가 /usr/local/bin/containerd 가 아니다: ${RUNNING_BIN:-알 수 없음}"
else
  echo "실행 중: ${RUNNING_BIN} ($(/usr/local/bin/containerd --version | awk '{print $3}'))"
fi

# ---------------------------------------------------------------------------
# 4. runc
#
# containerd tarball에는 runc가 포함되지 않는다.
# ---------------------------------------------------------------------------
log "runc $RUNC_VERSION 설치"

if [[ ! -x /usr/local/sbin/runc ]]; then
  curl -fsSL "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${ARCH}" \
    -o /usr/local/sbin/runc
  chmod 0755 /usr/local/sbin/runc
fi
/usr/local/sbin/runc --version | head -1

# ---------------------------------------------------------------------------
# 5. CNI 플러그인 + crictl
#
# CNI 플러그인은 CNI DaemonSet이 노드에 설치하는 경우가 많지만,
# 미리 넣어두면 CNI 설치 전에도 crictl로 노드를 디버깅할 수 있다.
# ---------------------------------------------------------------------------
log "CNI 플러그인 $CNI_PLUGINS_VERSION 설치"
mkdir -p /opt/cni/bin
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" \
  | tar -C /opt/cni/bin -xz

log "crictl $CRICTL_VERSION 설치"
curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" \
  | tar -C /usr/local/bin -xz
# crictl이 containerd 소켓을 찾도록 지정 (매번 --runtime-endpoint를 쓰지 않아도 된다)
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# ---------------------------------------------------------------------------
# 6. kubelet / kubeadm / kubectl
#
# 예전 apt.kubernetes.io 저장소는 동결되었으므로 pkgs.k8s.io를 쓴다.
# 저장소가 마이너 버전마다 따로 있어 K8S_MINOR이 곧 버전 고정 장치다.
# ---------------------------------------------------------------------------
log "kubelet / kubeadm / kubectl 설치 ($K8S_MINOR)"

mkdir -p -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl >/dev/null

# 업그레이드는 전용 절차(kubeadm upgrade)를 따라야 하므로 자동 업그레이드에서 제외한다.
apt-mark hold kubelet kubeadm kubectl >/dev/null

# kubelet 은 enable 해둔다.
#   - 설치 직후에는 kubeadm 이 설정을 주기 전까지 crashloop 에 빠지는 것이 정상이다.
#   - ⚠️ disable 하면 안 된다. 재부팅 시 kubelet 이 올라오지 않아
#     컨트롤 플레인 static pod 도 함께 사라지고 클러스터가 통째로 죽는다.
#     (kubeadm 이 나중에 kubelet 을 enable 한다는 보장이 없다)
#   - 이미 클러스터에 참여한 노드라면 재시작하지 않는다.
systemctl enable kubelet >/dev/null 2>&1 || true
if [[ $NODE_IN_CLUSTER -eq 1 ]]; then
  echo "kubelet 유지 (클러스터 참여 중): $(systemctl is-active kubelet)"
else
  # crashloop 이 정상이므로 지금 시작할 필요는 없다. kubeadm 이 시작시킨다.
  # 다만 enable 은 해두어야 재부팅 후 살아난다.
  echo "kubelet enable 완료 (kubeadm 이 시작시킨다)"
fi

# ---------------------------------------------------------------------------
# 7. 결과 요약
# ---------------------------------------------------------------------------
log "설치 완료"
echo "containerd : $(/usr/local/bin/containerd --version | awk '{print $3}')"
echo "runc       : $(/usr/local/sbin/runc --version | head -1 | awk '{print $3}')"
echo "kubeadm    : $(kubeadm version -o short)"
echo "kubelet    : $(kubelet --version | awk '{print $2}')"
echo "kubectl    : $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)"
echo "crictl     : $(crictl --version | awk '{print $NF}')"
echo "kubelet svc: $(systemctl is-enabled kubelet 2>/dev/null || echo '?') (enabled 여야 재부팅 후 살아난다)"
echo "swap       : $(swapon --show --noheadings | wc -l | tr -d ' ') 개 (0이어야 정상)"

cat <<'NEXT'

다음 단계:
  컨트롤 플레인 → sudo ./01-control-plane.sh
  워커 노드     → 컨트롤 플레인에서 join 명령을 받아 sudo ./02-worker.sh <join 명령>
NEXT
