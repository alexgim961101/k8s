# 유형 F. kubeadm 클러스터 (VM)

> [← 유형 E. 서비스와 네트워크](05-service-dns-troubleshooting.md) · [▶ 유형 G. 스케줄링과 reconciliation](07-scheduling-reconciliation.md) · [목록](README.md)

> 00-setup에서 만든 [`clusters/kubeadm`](../../../clusters/kubeadm/) 자산이 그대로 시험 범위다.
> 도메인 비중 **25%** 중 상당 부분이 여기서 나온다. **시험은 실제 VM이 아니라 컨테이너/VM 환경이지만 절차는 동일**하다.

## F-1. 노드 사전 준비 — 무엇이 왜 필요한가

**문제**
`kubeadm init`이 실패한다. 다음 5가지 사전 조건을 **순서대로** 점검하는 스크립트를 작성하라. 각 항목이 없을 때 나타나는 **증상**도 함께 정리하라.

1. swap 비활성화
2. 커널 모듈 `br_netfilter`, `overlay`
3. sysctl `ip_forward`, `bridge-nf-call-iptables`
4. 컨테이너 런타임(containerd) 동작 + cgroup driver 일치
5. 노드마다 고유한 `hostname` / `product_uuid`

<details><summary>풀이</summary>

```bash
cat > /tmp/kubeadm-precheck.sh <<'EOF'
#!/usr/bin/env bash
set -u
fail=0
chk() { printf '%-34s %s\n' "$1" "$2"; }

# 1. swap
if [ -z "$(swapon --show --noheadings)" ]; then chk "swap 비활성화" "OK"
else chk "swap 비활성화" "FAIL — kubelet 이 시작을 거부한다"; fail=1
     echo "     복구: swapoff -a && sed -i 's/^\\(.*swap.*\\)$/# \\1/' /etc/fstab"; fi

# 2. 커널 모듈
for m in br_netfilter overlay; do
  if lsmod | grep -q "^$m"; then chk "모듈 $m" "OK"
  else chk "모듈 $m" "FAIL"; fail=1; echo "     복구: modprobe $m"; fi
done

# 3. sysctl
for k in net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables; do
  v=$(sysctl -n "$k" 2>/dev/null || echo missing)
  if [ "$v" = "1" ]; then chk "$k" "OK ($v)"
  else chk "$k" "FAIL ($v)"; fail=1; echo "     복구: sysctl -w $k=1"; fi
done

# 4. 컨테이너 런타임 + cgroup driver
if systemctl is-active --quiet containerd; then chk "containerd active" "OK"
else chk "containerd active" "FAIL"; fail=1; fi
if crictl info >/dev/null 2>&1; then chk "CRI 응답" "OK"
else chk "CRI 응답" "FAIL — 소켓/플러그인 확인"; fail=1; fi
d=$(grep -E '^cgroupDriver:' /var/lib/kubelet/config.yaml 2>/dev/null | awk '{print $2}')
echo "     kubelet cgroupDriver=${d:-미설정(init 전이면 정상)}"
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml \
  && chk "containerd systemd cgroup" "OK" \
  || { chk "containerd systemd cgroup" "FAIL"; fail=1; }

# 5. 고유성
chk "hostname" "$(hostname)"
if [ -r /sys/class/dmi/id/product_uuid ]; then
  chk "product_uuid" "$(cat /sys/class/dmi/id/product_uuid)"
else chk "product_uuid" "읽을 수 없음"; fi

echo
[ $fail -eq 0 ] && echo "사전 점검 통과" || echo "실패 항목을 먼저 해결하라"
exit $fail
EOF
chmod +x /tmp/kubeadm-precheck.sh
sudo /tmp/kubeadm-precheck.sh
```

**각 항목이 없을 때의 증상**

| 조건 | 없으면 |
|---|---|
| swap off | `kubelet` 시작 실패: `running with swap on is not supported` |
| `br_netfilter` | 노드는 Ready인데 **Service만 동작하지 않음** (조용히 깨진다) |
| `overlay` | 컨테이너 생성 실패 (containerd가 overlayfs 사용) |
| `ip_forward=0` | Pod 간 라우팅 실패, 노드 간 통신 불가 |
| `bridge-nf-call-iptables=0` | Pod→Service DNAT 미적용 (**Pod→Pod는 성공**) |
| cgroup driver 불일치 | `kubelet` 시작 실패: `cgroup driver "systemd" is different from "cgroupfs"` |
| containerd 중지 | 노드 `NotReady`, 컨테이너 전부 소실 |
| `product_uuid` 중복 | **두 번째 노드가 등록되지 않음** (kubeadm이 노드를 구분 못 함) |
| hostname 중복 | 노드 오브젝트가 덮어써짐 |

**시험 포인트**: 시험은 **이미 구성된 노드에서 하나를 일부러 깨뜨려 놓는다.**
예: `/etc/fstab`에 swap을 다시 추가 → 재부팅 → kubelet NotReady. 증상을 보고 원인을 역추적해야 한다.

**참고 문서**: [Installing kubeadm — swap configuration / Network configuration](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

</details>

---

## F-2. kubeadm으로 클러스터 구축 (문서 없이 40분)

**문제**
VM 2대(`<CP-IP>`, `<WORKER-IP>`)로 kubeadm 클러스터를 구축하라. **컨트롤 플레인과 워커에서 각각 무엇을 설치하는지 구분**해서 설명하라.

<details><summary>풀이</summary>

**두 노드에 공통 설치** (`00-common.sh`):
containerd, runc, CNI 플러그인, kubelet, kubeadm, kubectl — 그리고 커널/swap/sysctl 사전 준비.

**컨트롤 플레인에서만** (`01-control-plane.sh`):
`kubeadm init` + CNI(Calico) + kubeconfig.

**워커에서만** (`02-worker.sh`):
`kubeadm join`.

```bash
# 1) 공통 (두 노드)
sudo ./00-common.sh

# 2) 컨트롤 플레인
sudo ./01-control-plane.sh
mkdir -p $HOME/.kube && sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config \
  && sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 3) 워커 (컨트롤 플레인에서 join 명령 발급)
sudo kubeadm token create --print-join-command
sudo ./02-worker.sh "kubeadm join <CP-IP>:6443 --token ... --discovery-token-ca-cert-hash sha256:..."

# 4) 검증
./03-verify.sh
kubectl get nodes
```

**시험에서 물어보는 핵심 3가지**

① **CRI 소켓 명시가 필요한 경우**

```bash
# 런타임이 여러 개면 kubeadm 이 자동 감지를 못 한다
kubeadm init --cri-socket unix:///run/containerd/containerd.sock
```

② **`--pod-network-cidr`와 CNI의 관계**

```bash
kubeadm init --pod-network-cidr=10.244.0.0/16
# → CNI 매니페스트의 IPPool CIDR 과 반드시 일치해야 한다.
#    불일치하면 Pod 가 IP 를 못 받거나 라우팅이 깨진다.
kubectl get ippool -o yaml | grep cidr       # Calico 인 경우
```

③ **HA 컨트롤 플레인 (kubeadm 제약)**

```bash
# --control-plane-endpoint 는 인증서 SAN 에 박힌다.
# 단일 CP 로 만든 클러스터를 HA 로 전환하는 것은 kubeadm 이 지원하지 않는다.
kubeadm init --control-plane-endpoint "lb.example.com:6443" --upload-certs

# 두 번째 CP 추가
kubeadm token create --print-join-command --ttl 2h
kubeadm init phase upload-certs --upload-certs
kubeadm join lb.example.com:6443 --control-plane --certificate-key <key> --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

**정리/해체 — 시험에서 "노드를 제거하라"가 나온다**

```bash
# 컨트롤 플레인에서
kubectl drain <node> --delete-emptydir-data --force --ignore-daemonsets
kubectl delete node <node>

# 해당 노드에서
kubeadm reset -f
rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
```

**자주 하는 실수**
- `kubeadm reset`이 **iptables를 정리하지 않는다**는 점. 같은 IP로 재구축하면 잔여 규칙이 문제를 만든다.
- `drain` 없이 노드를 지우면 그 노드의 Pod가 그대로 사라진다(서비스 중단).
- `--ignore-daemonsets` 없이 drain 하면 DaemonSet Pod 때문에 drain이 실패한다.

</details>

---

## F-3. CRI / CNI / CSI 인터페이스 구분

**문제**
① `CRI`, `CNI`, `CSI`가 각각 무엇을 표준화하는지 한 줄로 설명하라. ② 이 클러스터에서 각각을 **실제로 확인**하라(구현체, 소켓/경로, 설정).

<details><summary>풀이</summary>

| 인터페이스 | 표준화 대상 | 확인 위치 |
|---|---|---|
| **CRI** | kubelet ↔ 컨테이너 런타임 | 소켓 `/run/containerd/containerd.sock` |
| **CNI** | Pod 네트워크 (IP 할당, 라우팅) | `/etc/cni/net.d/*.conf`, 바이너리 `/opt/cni/bin/` |
| **CSI** | 스토리지 (볼륨 attach/mount) | CSIDriver/CSINode 오브젝트 |

```bash
# CRI — kubelet 이 어느 런타임과 대화하는가
docker exec study-control-plane grep -i criSocket /var/lib/kubelet/config.yaml 2>/dev/null
docker exec study-control-plane crictl info | head -30
docker exec study-control-plane crictl version

# CNI — 파드 네트워크 구현체
docker exec study-control-plane ls /etc/cni/net.d/         # kindnet.conflist
docker exec study-control-plane ls /opt/cni/bin/ | head
kubectl get pods -n kube-system | grep -iE 'kindnet|calico|cilium|flannel'
# CSI — 스토리지 드라이버 (kind 는 기본 CSI 없음)
kubectl get csidrivers
kubectl get csinodes
kubectl get storageclass          # 02 범위
```

**왜 이게 시험에 나오는가**
- **CRI**: 런타임 문제(컨테이너가 안 뜸)와 런타임 교체(`containerd` → `cri-o`) 문제
- **CNI**: 노드 `NotReady`의 최대 원인. CNI 매니페스트 재적용
- **CSI**: 02/Storage 도메인의 근거. "왜 PVC가 Pending인가"의 답이 CSI/StorageClass

**시험 포인트**: "kubelet이 사용하는 컨테이너 런타임 소켓 경로를 찾아라" 같은 문제가 나온다 →
**`/var/lib/kubelet/config.yaml`의 `containerRuntimeEndpoint`** (또는 구버전 `criSocket`)이다.
`kubeadm`은 `/var/lib/kubelet/kubeadm-flags.env`에 `--container-runtime-endpoint`로도 남긴다.

```bash
docker exec study-control-plane cat /var/lib/kubelet/kubeadm-flags.env
```

</details>

---

## F-4. 업그레이드 전 확인 (W12 예고)

**문제**
클러스터를 `v1.37 → v1.38`로 올리려 한다. ① **지금 올려도 되는지** 확인하는 명령을 실행하고, ② 컨트롤 플레인과 워커의 **순서**를 설명하라.

<details><summary>풀이</summary>

```bash
# ① 계획 확인 — 업그레이드 가능한 버전과 주의사항을 보여준다
sudo kubeadm upgrade plan

# 현재 버전
kubectl get nodes
kubeadm version -o short
```

**② 순서: 컨트롤 플레인 → 워커. 한 번에 한 마이너 버전.**

```
1. 컨트롤 플레인 (노드마다 반복)
   a. kubeadm 패키지 업그레이드 (1.37 → 1.38)
   b. kubeadm upgrade plan
   c. kubeadm upgrade apply v1.38.x
   d. kubelet/kubectl 패키지 업그레이드
   e. drain → restart kubelet → uncordon

2. 워커 (노드마다 반복)
   a. kubeadm 패키지 업그레이드
   b. drain <node> --ignore-daemonsets --delete-emptydir-data
   c. kubeadm upgrade node
   d. kubelet/kubectl 패키지 업그레이드
   e. restart kubelet → uncordon

3. CNI 등 애드온 업그레이드
```

**왜 컨트롤 플레인 먼저인가** — [공식 version skew policy](https://kubernetes.io/releases/version-skew-policy/) 기준:

| 컴포넌트 | skew 허용 범위 |
|---|---|
| `kubelet` | **API 서버보다 높을 수 없다.** 최대 3개 마이너 낮은 것까지 (1.25 미만은 2개) |
| `kube-proxy` | API 서버보다 높을 수 없다. 최대 3개 마이너 낮은 것까지 |
| `kubectl` | API 서버보다 1개 마이너 낮거나 높은 것까지 |
| `kube-controller-manager` / `kube-scheduler` | API 서버보다 높을 수 없다. 최대 1개 마이너 낮은 것까지 |

→ 워커를 먼저 올리면 **kubelet 1.38 > apiserver 1.37**이 되어 정책 위반이고,
   노드 등록이 거부된다(`NotReady`).

> ⚠️ 공식 문서 경고: **kubelet이 API 서버보다 3개 마이너 낮은 상태가 계속되면
> 컨트롤 플레인을 올리기 전에 kubelet을 먼저 올려야 한다.**
> 그리고 kubelet 마이너 업그레이드는 **in-place가 지원되지 않는다** → 반드시 `drain` 후 진행.

지원되는 릴리스 브랜치는 최근 3개 마이너(현재 1.37 / 1.36 / 1.35)다. 패치 지원은 약 1년.

**자주 하는 실수**
- `apt upgrade`로 kubelet을 먼저 올림 → 노드가 NotReady. **`apt-mark hold`를 풀고 명시적으로 버전 지정.**
- `drain` 없이 kubelet 재시작 → 그 노드의 Pod가 순단 중단.
- 여러 마이너를 한 번에 점프 (1.36 → 1.38 불가).
- 업그레이드 후 **CNI/애드온을 안 올림** → 구버전 CNI가 새 API와 충돌.

**이 문제는 04-onprem-cka W12의 예고편이다.** 지금은 `kubeadm upgrade plan`만 실행해보면 충분하다.

</details>
