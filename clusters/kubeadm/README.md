# kubeadm 클러스터 구축 (Multipass)

Multipass VM 2대를 **kubeadm**으로 클러스터로 만든다. kind가 대신 해주던 일을 직접 하는 단계이고,
[04-onprem-cka](../../04-onprem-cka/) W11~W12의 기반이다.

> **개념·이유는 [`00-setup/notes/kubeadm-setup.md`](../../00-setup/notes/kubeadm-setup.md) 에 있다.**
> 이 문서는 **실행 절차**만 다룬다.

**검증 환경**: macOS (Apple Silicon M4) / Multipass 1.16.3 / Ubuntu 24.04.5 / Kubernetes v1.37.0

## 왜 Multipass인가

| | Multipass | UTM |
|---|---|---|
| VM 생성 | `multipass launch` 한 줄 | GUI (또는 AppleScript 직접 작성) |
| IP 조회 | `multipass info` | 게스트 에이전트 필요 |
| 명령 실행 | `multipass exec` (에이전트 불필요) | 게스트 에이전트(`qemu-guest-agent`) 필요 |
| 파일 전송 | `multipass transfer` | 게스트 에이전트 필요 |
| cloud-init | 1급 지원 (`--cloud-init`) | 수동 |
| 스냅샷 | `multipass snapshot` | 지원 안 함 |

UTM은 `utmctl`이 `create`를 지원하지 않아 **VM 생성 자동화가 불가능**하다(AppleScript로 직접 짜야 함).
Multipass는 생성·실행·파일 전송·삭제가 모두 CLI로 되므로 이 리포의 자동화와 맞는다.

## 디렉토리

```
clusters/kubeadm/
├── README.md                  ← 지금 이 문서 (실행 절차)
├── scripts/                   ← 00-create-vms.sh 만 호스트에서, 나머지는 VM 안에서
│   ├── 00-create-vms.sh       # [호스트] VM 생성 + 스크립트 전송 + 네트워크·CIDR 검증
│   ├── 00-common.sh           # [노드] 커널·swap·containerd·kubelet/kubeadm/kubectl
│   ├── 01-control-plane.sh    # [CP]   kubeadm init + Calico
│   ├── 02-worker.sh           # [노드] kubeadm join
│   └── 03-verify.sh           # [CP]   노드·CNI·DNS·Pod 통신 검증
└── ansible/                   ← 반복 훈련용 (호스트에서 실행)
    ├── inventory/hosts.ini          # 00-create-vms.sh 가 자동 생성 (커밋 제외)
    └── playbooks/                   # prepare / install / init / join / verify / reset
```

## 설치 버전

2026-09 확인. 스크립트 상단의 환경변수로 바꿀 수 있다.

| 구성 요소 | 버전 | 비고 |
|---|---|---|
| Ubuntu | 24.04 LTS | cgroup v2 → containerd/systemd cgroup driver |
| Multipass | 1.16.3 | `brew install --cask multipass` |
| Kubernetes | v1.37.0 | `K8S_MINOR=v1.37` (패키지 저장소가 마이너별로 분리) |
| containerd | v2.3.5 | 공식 tarball |
| runc | v1.5.1 | tarball에 포함되지 않아 별도 설치 |
| CNI plugins | v1.9.1 | `/opt/cni/bin` |
| crictl | v1.37.0 | k8s와 버전 맞춤 |
| Calico | v3.32.2 | operator 방식 |
| pause 이미지 | 3.10.2 | k8s 1.37의 sandbox 이미지 |

> ⚠️ `kubelet`·`kubeadm`·`kubectl`은 **반드시 같은 마이너 버전**이어야 한다.

---

## 빠른 실행 (전체 4단계)

```bash
cd clusters/kubeadm/scripts

# 1. VM 생성 (호스트에서) — 약 2분
./00-create-vms.sh

# 2. 공통 설치 (두 노드) — 각 20~25초
for n in k8s-cp1 k8s-w1; do
  multipass exec $n -- sudo bash /home/ubuntu/00-common.sh
done

# 3. 컨트롤 플레인 초기화 (약 75초, Calico 포함)
multipass exec k8s-cp1 -- sudo bash /home/ubuntu/01-control-plane.sh

# 4. 워커 join
JOIN=$(multipass exec k8s-cp1 -- sudo kubeadm token create --print-join-command)
multipass exec k8s-w1 -- sudo bash /home/ubuntu/02-worker.sh "$JOIN"

# 검증 (약 60초)
multipass exec k8s-cp1 -- sudo bash /home/ubuntu/03-verify.sh
```

**실측 소요 시간** (M4 Mac, 이미지 캐시 후): VM 생성 1.5분 + 공통 0.8분 + CP 1.3분 + join 0.02분 + 검증 1분
= **약 5분**. 04단계 완료 기준 "문서 없이 40분"에 여유가 생긴다.

---

## 1. VM 생성 (`00-create-vms.sh`)

호스트에서 실행한다. **VM 생성·스크립트 전송·네트워크 검증·CIDR 충돌 검사를 한 번에** 한다.

```bash
./00-create-vms.sh                    # cp 1 + worker 1 (기본)
./00-create-vms.sh --cp 3 --worker 2  # HA 구성 (04단계 후반)
./00-create-vms.sh --recreate         # 기존 VM을 지우고 새로 생성
./00-create-vms.sh --memory 2G        # 메모리를 줄임 (HA 실습 시)
./00-create-vms.sh --help
```

| 옵션 | 기본 | 설명 |
|---|---|---|
| `--cp N` | 1 | control-plane 노드 수 |
| `--worker N` | 1 | worker 노드 수 |
| `--name-prefix P` | `k8s` | VM 이름 접두사 (`P-cp1`, `P-w1`) |
| `--cpus` / `--memory` / `--disk` | 2 / 4G / 20G | 노드 사양 |
| `--release` | 24.04 | Ubuntu 릴리스 |
| `--recreate` | — | 기존 VM 삭제 후 재생성 |

**스크립트가 검사하는 것**

1. **호스트 메모리** — VM에 할당할 총량 + 호스트 여유 4GB를 비교해 경고
2. **노드 간 통신** — 컨트롤 플레인에서 각 노드로 ping. 실패하면 k8s 노드로 쓸 수 없으므로 즉시 중단
3. **외부 인터넷** — 패키지 설치에 필요
4. **CIDR 충돌** — Pod CIDR(기본 `10.244.0.0/16`)이 노드 대역과 겹치는지 검사

```
==> 네트워크 확인
  k8s-cp1 : 192.168.252.31
  k8s-w1  : 192.168.252.32
  k8s-cp1 → k8s-w1 (192.168.252.32) 통신 OK
  외부 인터넷 OK

==> CIDR 충돌 검사
  노드 대역 : 192.168.252.0/24
  Pod 대역  : 10.244.0.0/16
  겹치지 않음 OK
```

마지막에 **Ansible 인벤토리**(`ansible/inventory/hosts.ini`)를 자동 생성한다.

### 네트워크: 기본(NAT) 모드로 충분하다

Multipass 기본 모드는 NAT이고 노드 대역은 `192.168.252.0/24`다(호스트마다 다름).
**k8s가 요구하는 노드 간 IP 통신과 크로스노드 Pod 통신이 이 모드에서 모두 동작한다 — 실측 확인했다.**

```bash
# 호스트에서 VM으로 직접 접속 (SSH)
multipass shell k8s-cp1          # 또는 ssh ubuntu@192.168.252.31
```

`--bridged`(외부 LAN에 노출)는 **불필요하다.** 필요해지면 이때 켠다:

```bash
multipass launch 24.04 --name extra --network en0 --cpus 2 --memory 4G --disk 20G
```

> **IP는 재부팅해도 유지된다.** MAC이 고정되어 DHCP가 같은 주소를 준다 — 실측 확인했다.
> (`join` 명령과 kubeconfig에 IP가 박히므로 중요하다.)

---

## 2. 공통 설치 (`00-common.sh`)

**모든 노드**에서 각각 1회. 컨트롤 플레인과 워커가 동일하다.

```bash
multipass exec k8s-cp1 -- sudo bash /home/ubuntu/00-common.sh
```

```bash
# 버전을 바꾸려면
multipass exec k8s-cp1 -- sudo env K8S_MINOR=v1.37 bash /home/ubuntu/00-common.sh
```

하는 일은 [`00-setup/notes/kubeadm-setup.md`](../../00-setup/notes/kubeadm-setup.md#1단계--공통-준비-두-vm-모두) 참조.
요약: 커널 모듈 → sysctl → swap off → containerd 2.3.5 → runc → CNI plugins → crictl → kubelet/kubeadm/kubectl.

**재실행해도 안전하다.** 이미 클러스터에 참여한 노드(`/etc/kubernetes/kubelet.conf` 존재)에서는
containerd/kubelet을 재시작하지 않는다.

> **kubelet은 enable된 상태로 둔다.** 설치 직후 kubelet이 crashloop에 빠지는 건 정상이지만
> `disable`하면 **재부팅 시 클러스터가 통째로 죽는다**(kubeadm이 나중에 enable해주지 않는다).

---

## 3. 컨트롤 플레인 (`01-control-plane.sh`)

**첫 컨트롤 플레인 노드에서만** 실행한다.

```bash
multipass exec k8s-cp1 -- sudo bash /home/ubuntu/01-control-plane.sh
```

```bash
# 옵션
--name <이름>              클러스터 이름 (기본 k8s-study)
--pod-cidr <CIDR>         Pod 대역 (기본 10.244.0.0/16)
--endpoint <주소>          control-plane-endpoint (HA로 확장할 때 LB 주소)
--apiserver-advertise-address <IP>
--kubernetes-version <버전>
--skip-cni
```

`kubeadm-config.yaml`을 `/root`에 남기므로 재현·업그레이드에 그대로 쓸 수 있다.

**Calico 설치 시 `apply`가 아니라 `create`를 쓴다.** Calico CRD가 커서 `apply`를 쓰면
`kubectl.kubernetes.io/last-applied-configuration` annotation이 262144바이트 한도를 넘어
`metadata.annotations: Too long`으로 실패한다. Calico 공식 문서도 `create`를 쓴다.

**Pod CIDR은 `10.244.0.0/16`을 쓴다.** Calico 기본값 `192.168.0.0/16`은 Multipass/UTM 노드 대역과
겹칠 수 있고, 겹치면 에러 없이 통신이 timeout 난다. `00-create-vms.sh`가 미리 검사해준다.

확인:

```bash
multipass exec k8s-cp1 -- sudo bash -c 'export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl get nodes'
# k8s-cp1   Ready   control-plane   ...
```

**HA로 확장할 때**: `--endpoint`는 apiserver 인증서 SAN에 박히고, kubeadm은 단일 CP로 만든
클러스터의 HA 전환을 지원하지 않는다. CP를 2대 이상 만들 계획이면 **처음부터** 지정한다.

---

## 4. 워커 join (`02-worker.sh`)

```bash
JOIN=$(multipass exec k8s-cp1 -- sudo kubeadm token create --print-join-command)
multipass exec k8s-w1 -- sudo bash /home/ubuntu/02-worker.sh "$JOIN"
```

스크립트가 `--cri-socket`을 자동으로 붙인다.

join 직후 `NotReady`는 정상이다. Calico의 `calico-node` DaemonSet이 그 노드에 뜬 뒤 Ready가 된다.

```bash
multipass exec k8s-cp1 -- sudo bash -c 'export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl get pods -n calico-system -o wide'
```

### 토큰

`--token`은 기본 **24시간** 유효하다. 만료되면 컨트롤 플레인에서 재발급한다.

```bash
multipass exec k8s-cp1 -- sudo kubeadm token create --print-join-command
```

---

## 5. 검증 (`03-verify.sh`)

```bash
multipass exec k8s-cp1 -- sudo bash /home/ubuntu/03-verify.sh
```

```
통과 18 / 실패 0
설치 검증 통과
```

| 검사 | 무엇을 증명하나 |
|---|---|
| 노드 Ready | kubelet이 API 서버에 등록됨 |
| 컨트롤 플레인 Pod | apiserver/scheduler/controller-manager/etcd가 static pod로 동작 |
| CoreDNS | CNI가 준비되어 Pod IP가 할당됨 |
| cgroup driver 일치 | kubelet(systemd) == containerd(SystemdCgroup) |
| 노드 포트 | 컨트롤 플레인 `6443`, 모든 노드 `10250` |
| **Pod → Pod IP** | CNI 데이터플레인 (VXLAN) |
| **Pod → Service/DNS** | CoreDNS + kube-proxy + Service ClusterIP |

**Pod IP는 되는데 Service만 실패하면** CNI는 정상이고 Service 경로가 깨진 것이다
→ `br_netfilter`, `bridge-nf-call-iptables`, kube-proxy를 본다. 이 구분이 진단의 핵심이다.

---

## 6. 호스트에서 kubectl 쓰기

```bash
mkdir -p ~/.kube
multipass exec k8s-cp1 -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/multipass-config
export KUBECONFIG=~/.kube/multipass-config
kubectl get nodes
```

`admin.conf`는 **cluster-admin 권한의 superuser 자격**이다. Git에 넣지 않는다
(`.gitignore`에 `kubeconfig` 계열이 등록되어 있다).

## 7. 반복 훈련 (해체 → 재구축)

04단계 완료 기준은 **"문서 없이 40분 내 구축"** 이다. Multipass는 이 훈련이 가장 빠르다.

```bash
# 가장 빠른 방법 — VM을 지우고 처음부터
multipass delete --purge k8s-cp1 k8s-w1
./00-create-vms.sh
# 이후 4단계 반복 (약 5분)
```

**VM은 유지하고 클러스터만 재구축**하려면 Ansible을 쓴다.

```bash
cd clusters/kubeadm/ansible

ansible-playbook -i inventory/hosts.ini playbooks/reset-cluster.yml
ansible-playbook -i inventory/hosts.ini playbooks/02-install-common.yml
ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml
ansible-playbook -i inventory/hosts.ini playbooks/verify.yml
```

강제 재실행은 `-e k8s_force_reinstall=true`.

### kubeadm과 Ansible의 역할 분담

| | 하는 일 |
|---|---|
| **Ansible** | 노드 상태(커널·swap·패키지)를 선언적으로 맞추고 **여러 노드에 동시 적용** |
| **kubeadm** | 클러스터 수명주기(init/join/upgrade/reset). **인증서와 static pod는 kubeadm만 안다** |

클러스터 자체를 Ansible로 "만들지" 않는다. Ansible은 kubeadm을 호출하는 오케스트레이터다.
`kubespray`가 이 둘을 합친 것이지만, 학습 단계에서는 분리해서 보는 편이 낫다.

---

## 8. 트러블슈팅

**Pod가 이상하면 `describe` → `logs` → static pod manifest 순서.**

| 증상 | 원인 후보 | 확인 |
|---|---|---|
| 노드 `NotReady` | CNI 미설치 | `kubectl get pods -n calico-system` |
| 노드 `NotReady` | `ip_forward=0` | `sysctl net.ipv4.ip_forward` |
| 모든 Pod `Pending` | CNI 없음 / IPPool CIDR 불일치 | `kubectl get tigerastatus`, `kubectl get ippool -o yaml` |
| kubelet 시작 실패 | swap 활성 | `swapon --show`, `journalctl -u kubelet -n 50` |
| Pod가 `ContainerCreating` 고정 | sandbox 이미지 pull 실패 | `crictl images \| grep pause` |
| Pod 간 통신 timeout (에러 없음) | CIDR 충돌 / `br_netfilter` | `sysctl net.bridge.bridge-nf-call-iptables` |
| Service만 안 됨 | kube-proxy / iptables | `kubectl get pods -n kube-system \| grep kube-proxy` |
| **재부팅 후 클러스터 죽음** | **kubelet이 disabled** | `systemctl is-enabled kubelet` → `enable --now kubelet` |
| `metadata.annotations: Too long` | Calico를 `apply`로 설치 | `kubectl create`를 쓴다 |
| `multipass exec`이 멈춤 | 출력 리다이렉트 조합 | 아래 참고 |
| join 토큰 오류 | 24시간 만료 | `kubeadm token create --print-join-command` |
| 두 번째 노드가 등록 안 됨 | `product_uuid`/hostname 중복 | `cat /sys/class/dmi/id/product_uuid` (양쪽 비교) |

### Multipass 관련 함정

**1. `multipass exec` + 출력 리다이렉트가 멈춘다** (1.16.3에서 확인)

```bash
# 멈춘다 — 25초 이상 무한 대기
multipass exec k8s-cp1 -- ping -c1 -W2 192.168.252.32 > /dev/null

# 우회: 출력을 받아서 쉘에서 판단한다
result="$(timeout 20 multipass exec k8s-cp1 -- ping -c1 -W2 192.168.252.32 2>&1 || true)"
printf '%s' "$result" | grep -q '1 received'
```

`00-create-vms.sh`는 이 우회를 적용해 두었다.

**2. macOS 기본 bash는 3.2** — 연관배열(`declare -A`)이 없다. `00-create-vms.sh`는 bash 3.2에서도
동작하도록 작성했다. (`#!/usr/bin/env bash`로 Homebrew bash를 쓰면 무관하다.)

**k8s가 안 될 때는 런타임을 직접 본다.** kubelet을 거치지 않으므로 더 원시적인 정보가 나온다.

```bash
multipass exec k8s-w1 -- sudo crictl ps -a
multipass exec k8s-w1 -- sudo crictl logs <container-id>
multipass exec k8s-w1 -- sudo journalctl -u kubelet -n 100 --no-pager
multipass exec k8s-w1 -- sudo journalctl -u containerd -n 100 --no-pager
```

---

## 9. 되돌리기

```bash
# 노드를 클러스터에서 제거 (컨트롤 플레인에서)
multipass exec k8s-cp1 -- sudo bash -c '
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl drain k8s-w1 --delete-emptydir-data --force --ignore-daemonsets
  kubectl delete node k8s-w1'

# 노드 초기화 (해당 노드에서)
multipass exec k8s-w1 -- sudo kubeadm reset -f
multipass exec k8s-w1 -- sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet

# VM 자체를 삭제
multipass delete --purge k8s-cp1 k8s-w1
```

`kubeadm reset`은 iptables/IPVS 규칙을 정리하지 않는다. 같은 IP로 재구축할 때 잔여 규칙이
문제를 만들 수 있다.

```bash
multipass exec k8s-w1 -- sudo bash -c '
  iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X'
```

Ansible을 쓴다면 `playbooks/reset-cluster.yml`이 위 과정을 대신한다.

---

## 다음 단계

- [04-onprem-cka](../../04-onprem-cka/) W12: etcd 스냅샷 백업·복구, n-1 → n 업그레이드, 인증서 갱신
- MetalLB 설치 후 LoadBalancer Service 실습
- 관통 프로젝트([app/](../../app/))를 이 클러스터로 이전
- **HA 구성**: `./00-create-vms.sh --cp 3 --worker 2 --memory 2G`
