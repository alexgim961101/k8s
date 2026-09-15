# kubeadm 클러스터 구축 — 개념 정리

> 확인 시점: 2026-09 / Kubernetes **v1.37.0**, containerd v2.3.5, Calico v3.32.2
>
> **이 문서는 "무엇을 왜 하는가"를 기록하는 노트다.** 명령을 그대로 따라 치는 용도라면
> [`clusters/kubeadm/README.md`](../../clusters/kubeadm/README.md)를 본다.

## 실행 자산

| 종류 | 위치 | 용도 |
|---|---|---|
| 설치 스크립트 | [`clusters/kubeadm/scripts/`](../../clusters/kubeadm/scripts/) | VM 안에서 수동 실행 (00 공통 → 01 CP → 02 워커 → 03 검증) |
| Ansible | [`clusters/kubeadm/ansible/`](../../clusters/kubeadm/ansible/) | 호스트에서 실행. 반복 훈련(해체→재구축) |
| 실행 절차 | [`clusters/kubeadm/README.md`](../../clusters/kubeadm/README.md) | 명령과 옵션, 트러블슈팅 |

이 노트는 그 자산들이 **왜 그렇게 생겼는지**를 설명한다.

## 왜 UTM VM + kubeadm 인가

00~03단계는 kind 위에서 논다. kind의 노드는 **kubeadm으로 구성된 컨테이너**라,
VM 위에 직접 kubeadm을 돌리는 것과 구조가 같다. 다른 점은 다음과 같다.

| | kind | UTM VM + kubeadm |
|---|---|---|
| 노드 | 컨테이너 (호스트 커널 공유) | VM (커널 포함 독립) |
| 네트워크 | Docker 브리지 | VM 브리지 (외부 IP 보유) |
| 노드 준비 | 이미지에 포함 | **직접 해야 함** (커널·swap·런타임) |
| 컨트롤 플레인 | static pod (동일) | static pod (동일) |
| 용도 | 오브젝트 학습 | 클러스터 수명주기 학습 (CKA) |

→ **"노드 준비"라는 단계가 새로 생기는 것**이 핵심 차이다. CKA와 실무에서 사고가 나는 지점도 대부분 여기다.

## 전체 순서

```
[호스트]  VM 2대 준비, SSH 접속 설정      → clusters/kubeadm/README.md 0장
             │
[VM 공통] 00-common.sh      커널 모듈 · sysctl · swap · containerd · kubelet/kubeadm/kubectl
             │
[CP]      01-control-plane.sh   kubeadm init · kubeconfig · Calico CNI
             │
[Worker]  02-worker.sh          kubeadm join
             │
[CP]      03-verify.sh          노드·CNI·DNS·Pod 통신 검증
```

---

## 0단계 — VM 준비

UTM으로 VM 2대를 띄운다. 스크립트는 **Ubuntu 24.04**를 기준으로 작성했다.

| VM | 역할 | CPU | RAM | Disk |
|---|---|---|---|---|
| `k8s-cp` | control-plane | 2 | 4G | 20G |
| `k8s-w1` | worker | 2 | 4G | 20G |

### UTM에서 주의할 점

**네트워크 모드는 `Bridged (Advanced)`.** "Shared Network"은 호스트에서 게스트로 직접 접속할 수 없어
SSH와 join이 번거로워진다. Bridged로 두면 VM이 공유기에서 IP를 받아 **두 VM이 서로 IP로 통신**할 수 있다.

`product_uuid`가 겹치면 두 번째 노드가 클러스터에 등록되지 않는다. kubeadm은
hostname/MAC/product_uuid로 노드를 식별하기 때문이다. UTM에서 **VM을 복제**하면 대개 겹치므로,
복제 대신 각각 설치하거나 복제 후 UUID를 새로 만든다.

**IP를 고정해두는 것을 권한다.** join 명령과 kubeconfig에 IP가 박히고, UTM은 DHCP라
재부팅 시 IP가 바뀔 수 있다. netplan으로 고정하거나 DHCP 예약을 건다.

```bash
hostname                                   # 두 VM이 서로 달라야 한다
ip -4 addr show                            # 예: 192.168.0.5 / 192.168.0.6
ping -c1 <상대 IP>                          # 양방향 통신
sudo cat /sys/class/dmi/id/product_uuid    # VM마다 고유해야 한다

ssh-copy-id ubuntu@192.168.0.5             # 호스트에서
ssh-copy-id ubuntu@192.168.0.6
```

---

## 1단계 — 공통 준비 (두 VM 모두)

`scripts/00-common.sh`. 컨트롤 플레인이든 워커든 **똑같이** 한 번 실행한다.

```bash
sudo ./00-common.sh
# 버전을 바꾸려면
sudo K8S_MINOR=v1.37 CONTAINERD_VERSION=v2.3.5 ./00-common.sh
```

### 이 단계가 하는 일과 이유

**(1) 커널 모듈 — `overlay`, `br_netfilter`**

- `overlay`: containerd가 이미지 레이어를 overlayfs로 합친다. Ubuntu는 보통 기본 로드되어 있지만
  명시적으로 보장한다.
- `br_netfilter`: **없으면 조용히 깨진다.** Pod 사이 트래픽이 veth → bridge를 지나가는데,
  `br_netfilter`가 없으면 그 패킷이 iptables를 거치지 않는다.
  결과적으로 **Service ClusterIP가 반응하지 않는다.** `kube-proxy`가 넣은 DNAT 규칙이 적용되지 않기 때문이다.
  로드 상태는 `lsmod | grep br_netfilter`, 확인은 `ls /proc/sys/net/bridge/`.

**(2) sysctl — `ip_forward=1`, `bridge-nf-call-iptables=1`**

- `ip_forward`: 기본값이 0(라우터로 동작 안 함)이다. Pod CIDR로 향하는 패킷을 노드가 포워딩해야 한다.
- `bridge-nf-call-iptables`: bridge를 건너는 IPv4 패킷을 iptables가 보게 한다.
  `kube-proxy`의 iptables 모드가 이걸 전제로 동작한다.

**(3) swap 비활성화**

kubelet은 기본값(`failSwapOn: true`)으로 **swap이 감지되면 시작 자체를 거부**한다.
이유: swap이 있으면 Pod의 메모리 limit을 커널이 제대로 강제하지 못하고,
스케줄러가 계산한 메모리 가용량이 실제와 어긋난다.

```bash
sudo swapoff -a                                   # 즉시
sudo sed -i 's/^\(.*swap.*\)$/# \1/' /etc/fstab   # 재부팅 후에도
```

`swap.target`을 mask해두면 systemd가 다시 켜지 못한다.

> k8s 1.28+ 부터 kubelet 설정으로 swap을 **허용**할 수 있다(`failSwapOn: false`, `swapBehavior`).
> 학습 단계에서는 끄는 것이 표준이고, 시험에서도 그 전제로 문제가 나온다.

**(4) containerd 2.x + runc**

- 배포판 패키지 대신 **공식 tarball**을 쓴다. Ubuntu 24.04의 `containerd.io` 패키지 버전은
  배포판/시점마다 달라 재현이 안 된다. tarball은 버전이 고정된다.
- **tarball에 runc가 포함되지 않는다.** 별도로 설치해야 하며, 빠뜨리면 Pod가
  `failed to create task: ... runc: executable file not found`로 실패한다.
- **배포판 `containerd` 패키지가 함께 깔려 있으면 충돌한다.** 두 버전이 각자의 systemd 유닛과
  소켓을 두고 경합해 "containerd는 active인데 노드는 NotReady" 같은 애매한 증상이 나온다.
  그래서 스크립트는 `/usr/bin/containerd`를 제거하고 `/usr/local/bin/containerd`만 쓰게 한 뒤,
  기동 후 실행 중인 프로세스의 실제 바이너리를 확인한다.
- containerd 1.x로 만들어진 `config.toml`이 남아 있으면 2.x가 플러그인 키를 인식하지 못한다.
  `version = 2` 이하의 설정은 백업하고 `containerd config default`로 재생성한다.
- containerd 2.x의 설정 키가 1.x와 다르다. 문서·예제가 1.x 기준이면 그대로 안 먹는다.

| | 1.x | 2.x |
|---|---|---|
| CRI 런타임 플러그인 | `plugins."io.containerd.grpc.v1.cri"` | `plugins.'io.containerd.cri.v1.runtime'` |
| 이미지 플러그인 | (동일) | `plugins.'io.containerd.cri.v1.images'` |
| sandbox 이미지 키 | `sandbox_image` | `sandbox_image` (위치가 images 플러그인으로 이동) |

**(5) cgroup driver = systemd**

Ubuntu 24.04는 기본이 **cgroup v2**이고, cgroup v2에서는 systemd 드라이버가 사실상 필수다.
cgroupfs를 쓰면 systemd와 커널이 cgroup을 **두 개의 다른 관리자**가 관리하게 되어
리소스 압박 상황에서 노드가 불안정해진다.
kubelet과 containerd **양쪽 다** systemd여야 한다.

```bash
# containerd
grep -n SystemdCgroup /etc/containerd/config.toml
# kubelet (kubeadm init 이후 생성된다)
grep -n cgroupDriver /var/lib/kubelet/config.yaml
```

> k8s 1.37에서는 `KubeletCgroupDriverFromCRI` 기능 게이트로 kubelet이 런타임에서 자동 감지한다.
> **단 containerd 1.y 이하는 이 조회에 제대로 응답하지 않아** kubelet 설정값으로 폴백한다.
> 1.38부터 이 폴백이 제거되므로 **containerd 2.x를 쓰는 것이 안전하다.**

**(6) sandbox(pause) 이미지**

Pod 하나마다 네트워크 namespace를 보유하는 `pause` 컨테이너가 먼저 뜬다.
containerd 기본값과 kubeadm이 기대하는 값이 다르면 Pod가 영원히 `ContainerCreating`에 머문다.

```bash
grep sandbox_image /etc/containerd/config.toml
# k8s 1.37 기준: registry.k8s.io/pause:3.10.2
```

**(7) CNI 플러그인 + crictl**

- CNI 플러그인 바이너리는 `/opt/cni/bin`에 둔다. Calico 같은 CNI가 자기 DaemonSet으로
  대부분 설치하지만, 미리 넣어두면 CNI 설치 전에도 `crictl`로 노드를 디버깅할 수 있다.
- `crictl`은 kubelet이 아니라 **런타임과 직접** 대화한다. kubelet이 죽었을 때도 쓸 수 있어서
  "컨트롤 플레인이 안 뜰 때" 가장 먼저 꺼내는 도구다.
- `/etc/crictl.yaml`에 소켓을 적어두면 `--runtime-endpoint`를 매번 안 붙여도 된다.

**(8) kubelet / kubeadm / kubectl**

- 저장소는 **`pkgs.k8s.io`** 다. 옛 `apt.kubernetes.io`는 2023-09부터 동결됐다.
- **마이너 버전마다 저장소가 분리**되어 있다(`/core:/stable:/v1.37/`).
  그래서 `k8s_minor`를 정하는 것만으로 버전이 고정된다.
- 세 패키지는 같은 마이너여야 한다. skew는 kubelet이 컨트롤 플레인보다 **낮은 것만** 허용된다.
- `apt-mark hold`로 자동 업그레이드를 막는다. k8s 업그레이드는 `kubeadm upgrade`라는
  전용 절차가 있어서, `apt upgrade`가 임의로 버전을 올리면 클러스터가 깨진다.
- 설치 직후 **kubelet을 켜면 crashloop에 빠진다.** kubeadm이 지시를 주기 전까지는 정상이며,
  로그에 `failed to load kubelet config file`이 반복된다. 겁먹지 않아도 된다.

---

## 2단계 — 컨트롤 플레인 (CP VM에서만)

`scripts/01-control-plane.sh`.

```bash
sudo ./01-control-plane.sh
```

### 플래그 나열 대신 YAML을 쓰는 이유

kubeadm은 `--flag` 나열 방식과 `--config` YAML 방식을 모두 지원한다.
학습 단계에서는 **YAML**을 권한다.

- 클러스터 정의가 파일로 남아 재현·리뷰가 된다 (`/root/kubeadm-config.yaml`)
- 나중에 HA 확장·업그레이드에서 같은 파일을 다시 쓴다
- `kubeadm upgrade plan`도 이 설정 파일을 읽는다

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.0.5     # --apiserver-advertise-address
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
controlPlaneEndpoint: 192.168.0.5:6443   # --control-plane-endpoint
networking:
  podSubnet: 10.244.0.0/16               # --pod-network-cidr
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

> `apiVersion`은 kubeadm 버전에 따라 `v1beta3` → **`v1beta4`** 로 올라갔다.
> 1.37은 `v1beta4`를 쓴다. 예전 예제를 복사하면 여기서 막힌다.

### `--control-plane-endpoint`의 함정

이 주소는 **apiserver 인증서의 SAN에 박힌다.** 나중에 바꾸면 인증서 재발급 + 컴포넌트 재시작이 필요하다.
그리고 kubeadm은 **단일 CP로 만든 클러스터를 HA로 전환하는 것을 지원하지 않는다.**

→ HA로 갈 가능성이 조금이라도 있으면 **처음부터** 로드밸런서/DNS 주소를 넣는다.
   (단일 CP에서도 `--control-plane-endpoint`를 지정해두는 것은 가능하다.)

### `kubeadm init`이 실제로 하는 일

00단계에서 kind를 뜯어보며 본 구조가 그대로 반복된다.

1. **사전 점검(preflight)** — swap, 커널 모듈, 포트, 컨테이너 런타임, `/etc/hosts` 등
2. **PKI 생성** — `/etc/kubernetes/pki/`: CA, apiserver, apiserver-kubelet-client, front-proxy, etcd, sa
3. **kubeconfig 생성** — `admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf`
   그리고 `super-admin.conf`(`system:masters`, RBAC 우회용 break-glass)
4. **static pod manifest 배치** — `/etc/kubernetes/manifests/{etcd,kube-apiserver,kube-scheduler,kube-controller-manager}.yaml`
   → **kubelet이 API 서버 없이 이 파일을 읽어 컨트롤 플레인을 띄운다.** "닭과 달걀" 문제의 해법
5. **부트스트랩 토큰 발급** — 워커가 CA를 신뢰하고 kubelet 인증서를 받아갈 수 있게
6. **애드온 설치** — CoreDNS, kube-proxy (CNI가 없으면 CoreDNS는 Pending)

확인:

```bash
sudo ls /etc/kubernetes/manifests/
sudo crictl ps                                  # 컨트롤 플레인 컨테이너가 런타임에 보인다
kubectl get pods -n kube-system -o wide
```

### `admin.conf` 취급

`admin.conf`는 `O = kubeadm:cluster-admins`(→ `cluster-admin` ClusterRole) 자격이다.
**사실상 root 키다.** 노드 밖으로 복사하지 않고, Git에 넣지 않는다(`.gitignore`에 `kubeconfig` 계열이 등록되어 있다).
다른 사용자에게 권한을 줄 때는 `kubeadm kubeconfig user --client-name <CN>`으로 개별 자격을 만든다.

### CNI(Calico) 설치

CNI가 없으면 **노드가 `NotReady`이고 CoreDNS도 뜨지 않는다.**
"노드는 보이는데 Pod가 Pending" 상태의 90%가 여기다.

Calico 설치 순서 — **CRD → operator → Installation CR**:

```bash
kubectl apply -f .../v1_crd_projectcalico_org.yaml
kubectl apply -f .../tigera-operator.yaml
kubectl apply -f custom-resources.yaml   # Installation CR
watch kubectl get tigerastatus
```

> operator가 CRD보다 먼저 뜨면 `Installation` CR을 인식하지 못한다.

**⚠️ CIDR 충돌 주의**

Calico 기본 매니페스트의 IPPool CIDR은 **`192.168.0.0/16`** 이다.
UTM/Multipass VM이 `192.168.0.0/24` 대역을 쓰면 **Pod 네트워크가 호스트 네트워크와 겹친다.**
겹치면 `kube-proxy` 규칙과 라우팅이 엉켜 통신이 조용히 깨진다(에러 없이 timeout).

→ `kubeadm`의 `podSubnet`과 **Calico IPPool CIDR을 같게** 맞추고, 둘 다 호스트 대역을 피한다.
   스크립트는 기본값을 `10.244.0.0/16`으로 잡고 IPPool에 그대로 주입한다.

```bash
kubectl get ippool -o yaml | grep cidr     # 실제 적용 확인
```

---

## 3단계 — 워커 join (워커 VM에서만)

공통 준비를 마친 워커에서:

```bash
sudo ./02-worker.sh "kubeadm join 192.168.0.5:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
```

### join이 실제로 하는 일

1. 컨트롤 플레인에서 **CA 인증서를 받아** 신뢰 (`--discovery-token-ca-cert-hash`로 검증)
2. 부트스트랩 토큰으로 인증해 **kubelet 클라이언트 인증서를 발급**받는다 (TLS bootstrap)
3. `/var/lib/kubelet/config.yaml`과 `/etc/kubernetes/kubelet.conf` 배치
4. kubelet이 API 서버에 노드를 **등록**

### 토큰

- `--token`은 기본 **24시간** 유효하다. 며칠에 걸쳐 노드를 추가하면 만료된다.
  → 컨트롤 플레인에서 `kubeadm token create --print-join-command`로 재발급
- `--discovery-token-ca-cert-hash`는 **CA 공개키의 sha256**이다.
  이것이 없으면 MITM에 취약해진다. 다른 클러스터의 명령을 복사하면 이 해시가 달라 join이 거부된다.

```bash
# 해시를 직접 계산해 검증할 때
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
  | openssl rsa -pubin -outform der 2>/dev/null \
  | openssl dgst -sha256 -hex
```

### join 직후 `NotReady`는 정상이다

노드 등록과 **Pod 네트워크 준비는 별개**다.
Calico의 `calico-node` DaemonSet이 새 노드에 뜬 뒤에 Ready가 된다. 몇십 초 걸린다.

```bash
kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=k8s-w1
kubectl describe node k8s-w1 | sed -n '/Conditions/,/Addresses/p'
```

---

## 4단계 — 검증

`scripts/03-verify.sh`. "노드가 Ready다"로 끝내지 않고 **Pod 간 통신까지** 확인한다.

```bash
./03-verify.sh
```

테스트 Pod 2개(agnhost)를 띄워 확인하는 것:

| 검사 | 무엇을 증명하나 |
|---|---|
| `netcheck-a` → `netcheck-b` **Pod IP** | CNI 데이터플레인 (VXLAN/라우팅) |
| `netcheck-a` → `kubernetes.default.svc:443` | CoreDNS + kube-proxy + Service ClusterIP |

두 번째가 실패하고 첫 번째가 성공하면 **CNI는 정상이고 Service 경로가 깨진 것**이다
→ `br_netfilter`, `bridge-nf-call-iptables`, `kube-proxy`를 본다. 이 구분이 진단의 핵심이다.

---

## 5단계 — 반복 훈련 (해체 → 재구축)

04단계 완료 기준은 **"문서 없이 40분 내 구축"** 이다. 손에 익으려면 반복해야 한다.

Ansible로 자동화해둔다 ([`clusters/kubeadm/ansible/`](../../clusters/kubeadm/ansible/)).

```bash
cd clusters/kubeadm/ansible
cp inventory/hosts.ini.example inventory/hosts.ini && $EDITOR inventory/hosts.ini

ansible-playbook -i inventory/hosts.ini playbooks/01-prepare-nodes.yml
ansible-playbook -i inventory/hosts.ini playbooks/02-install-common.yml
ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml
ansible-playbook -i inventory/hosts.ini playbooks/verify.yml

# 해체
ansible-playbook -i inventory/hosts.ini playbooks/reset-cluster.yml
```

### kubeadm과 Ansible의 역할 분담

| | 하는 일 |
|---|---|
| **Ansible** | 노드 상태(커널·swap·패키지)를 선언적으로 맞추고 **여러 노드에 동시 적용** |
| **kubeadm** | 클러스터 수명주기(init/join/upgrade/reset). **인증서와 static pod는 kubeadm만 안다** |

→ 클러스터 자체를 Ansible로 "만들지" 않는다. **Ansible은 kubeadm을 호출하는 오케스트레이터**다.
`kubespray`는 이 둘을 합친 것이지만, 학습 단계에서는 분리해서 보는 편이 낫다.

---

## 트러블슈팅 (증상 → 원인)

**Pod가 이상하면 `describe` → `logs` → static pod manifest 순서.** 이건 00단계에서 정한 규칙이고 여기서도 같다.

| 증상 | 원인 후보 | 확인 |
|---|---|---|
| 노드 `NotReady` | CNI 미설치 | `kubectl get pods -n kube-system` 에 calico-node |
| 노드 `NotReady` | `ip_forward=0` | `sysctl net.ipv4.ip_forward` |
| 모든 Pod `Pending` | CNI 없음 / IPPool CIDR 불일치 | `kubectl get tigerastatus`, `kubectl get ippool -o yaml` |
| kubelet 시작 실패 | swap 활성 | `swapon --show`, `journalctl -u kubelet -n 50` |
| Pod가 `ContainerCreating` 고정 | sandbox 이미지 pull 실패 | `sudo crictl images \| grep pause` |
| containerd는 active인데 `NotReady` | 배포판/공식 containerd 충돌 | `readlink -f /proc/$(pgrep -x containerd)/exe` |
| Pod 간 통신 timeout (에러 없음) | CIDR 충돌 / `br_netfilter` | `sysctl net.bridge.bridge-nf-call-iptables`, `kubectl get ippool` |
| Service만 안 됨 (Pod IP는 됨) | kube-proxy / iptables | `kubectl get pods -n kube-system \| grep kube-proxy`, `sudo iptables -t nat -L KUBE-SERVICES` |
| apiserver 무한 재시작 | 인증서 SAN ≠ 실제 접속 IP | `sudo crictl logs $(sudo crictl ps --name kube-apiserver -q)` |
| `kubectl` 접속 거부 | kubeconfig 미설정 | `kubectl config get-contexts`, `kubectl cluster-info` |
| join 토큰 오류 | 24시간 만료 | `kubeadm token create --print-join-command` |
| CA 해시 불일치 | 다른 클러스터 명령 사용 | 위 `openssl` 명령으로 직접 계산 |
| 두 번째 노드가 등록 안 됨 | `product_uuid`/hostname 중복 | `sudo cat /sys/class/dmi/id/product_uuid` (양쪽 비교) |

**k8s가 안 될 때는 런타임을 직접 본다.** kubelet을 거치지 않으므로 더 원시적인 정보가 나온다.

```bash
sudo crictl ps -a
sudo crictl logs <container-id>
sudo crictl images
sudo journalctl -u containerd -n 100
```

---

## 되돌리기

```bash
# 워커
kubectl drain <node> --delete-emptydir-data --force --ignore-daemonsets   # CP에서
sudo kubeadm reset -f
kubectl delete node <node>                                                # CP에서

# CP
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /var/lib/etcd /etc/kubernetes
```

`kubeadm reset`은 **iptables/IPVS 규칙을 정리하지 않는다.** 같은 IP로 재구축할 때
잔여 규칙이 남아 Service가 이상 동작할 수 있다.

```bash
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo ipvsadm -C
```

---

## 설치 중 막힌 지점 (기록)

실제로 겪은 문제를 여기에 덧붙인다. VM을 다시 만들 때 그대로 재사용한다.

<!-- 예: 2026-08-13 UTM / 두 번째 VM 복제 후 join 실패 → product_uuid 중복. VM 새로 생성 -->

---

## 참고

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Calico self-managed on-premises](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)
- CIDR 충돌: [kubeadm troubleshooting — pod network CIDR overlap](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/#pod-network)
