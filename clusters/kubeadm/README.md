# kubeadm 클러스터 구축

UTM VM 2대를 **kubeadm**으로 클러스터로 만든다. kind가 대신 해주던 일을 직접 하는 단계이고,
[04-onprem-cka](../../04-onprem-cka/) W11~W12의 기반이다.

여기 있는 스크립트는 **VM(Ubuntu 24.04) 안에서 실행**하는 것이고,
아래 Ansible은 **호스트에서** 실행한다. 직접 넣어보는 것이 목적이라 순서대로 따라가는 것을 기본으로 하고,
Ansible은 반복 훈련용으로 쓴다.

## 이 문서에서 한 번만 읽으면 되는 것

- 설치 순서: **공통 준비 → 컨트롤 플레인 init → 워커 join**
- 각 단계가 실제로 무엇을 하는지 (`00-common.sh` / `01-control-plane.sh` / `02-worker.sh`)
- 실패했을 때 어디를 보는지

## 디렉토리

```
clusters/kubeadm/
├── README.md                  ← 지금 이 문서
├── scripts/                   ← VM 안에서 실행 (수동 구축)
│   ├── 00-common.sh           # 모든 노드 공통: 커널·swap·containerd·kubelet
│   ├── 01-control-plane.sh    # 컨트롤 플레인 전용: kubeadm init + Calico
│   ├── 02-worker.sh           # 워커 전용: kubeadm join
│   └── 03-verify.sh           # 설치 검증
└── ansible/                   ← 호스트에서 실행 (자동화·반복 훈련)
    ├── ansible.cfg
    ├── inventory/hosts.ini.example
    ├── group_vars/all.yml
    └── playbooks/
        ├── 01-prepare-nodes.yml      # 커널·swap·패키지 (멱등)
        ├── 02-install-common.yml     # 00-common.sh
        ├── 03-init-control-plane.yml # 01-control-plane.sh
        ├── 04-join-workers.yml       # 02-worker.sh
        ├── verify.yml                # 03-verify.sh
        └── reset-cluster.yml         # 해체
```

## 설치 버전

2026-09 확인. 스크립트 상단의 환경변수로 언제든 바꿀 수 있다.

| 구성 요소 | 버전 | 비고 |
|---|---|---|
| Ubuntu | 24.04 LTS | cgroup v2 → containerd/systemd cgroup driver |
| Kubernetes | v1.37.0 | `k8s_minor=v1.37` (패키지 저장소가 마이너별로 분리) |
| containerd | v2.3.5 | 공식 tarball. 설정 키가 `io.containerd.cri.v1.runtime` |
| runc | v1.5.1 | tarball에 포함되지 않으므로 별도 설치 |
| CNI plugins | v1.9.1 | `/opt/cni/bin` |
| crictl | v1.37.0 | k8s와 버전 맞춤 |
| Calico | v3.32.2 | operator 방식 |
| pause 이미지 | 3.10.2 | k8s 1.37의 sandbox 이미지 |

> ⚠️ `kubelet`·`kubeadm`·`kubectl`은 **반드시 같은 마이너 버전**이어야 한다.
> `k8s_minor`가 곧 버전 고정 장치다.

---

## 0. VM 준비 (UTM)

VM 2대가 이미 있다고 가정한다. 다음만 맞춰준다.

| VM | 역할 | 최소 사양 |
|---|---|---|
| `k8s-cp` | control-plane | CPU 2, RAM 4G, Disk 20G |
| `k8s-w1` | worker | CPU 2, RAM 4G, Disk 20G |

**확인할 것**

```bash
# 각 VM 안에서
hostname           # 두 VM이 서로 달라야 한다
ip -4 addr show    # IP 확인 (예: <CP-IP> / <WORKER-IP>)
ping -c1 <상대 IP> # 양방향 통신
sudo cat /sys/class/dmi/id/product_uuid   # VM마다 고유해야 한다
```

`product_uuid`가 겹치면 노드 등록이 실패한다. UTM에서 VM을 **복제**했다면 십중팔구 겹친다 —
복제 대신 각각 새로 설치하거나, 복제 후 새 UUID를 생성한다.

**호스트에서 SSH 접속을 편하게**

```bash
ssh-copy-id ubuntu@<CP-IP>
ssh-copy-id ubuntu@<WORKER-IP>
```

---

## 1. 공통 준비 (두 VM 모두)

`00-common.sh` 하나로 끝난다. 두 VM에서 각각 실행한다.

```bash
scp -r clusters/kubeadm/scripts ubuntu@<CP-IP>:~/
ssh ubuntu@<CP-IP>
sudo ~/scripts/00-common.sh
```

이 스크립트가 하는 일:

| 단계 | 내용 | 왜 필요한가 |
|---|---|---|
| 커널 모듈 | `overlay`, `br_netfilter` | overlayfs(컨테이너), bridge 트래픽의 iptables 통과 |
| sysctl | `ip_forward=1`, `bridge-nf-call-iptables=1` | Pod 간 라우팅, Service ClusterIP |
| swap | `swapoff` + fstab 주석 + `swap.target` mask | kubelet은 swap이 있으면 시작을 거부한다 |
| containerd | v2.3.5 tarball | CRI 런타임. 패키지 버전이 배포판마다 달라 tarball로 고정 |
| cgroup driver | `SystemdCgroup = true` | Ubuntu 24.04는 cgroup v2. kubelet과 런타임이 같은 드라이버를 써야 한다 |
| sandbox 이미지 | `pause:3.10.2` | k8s 1.37과 containerd 기본값이 어긋나면 Pod가 뜨지 않는다 |
| runc | v1.5.1 | tarball에 없다 |
| CNI plugins | `/opt/cni/bin` | CNI 설치 전에도 `crictl`로 디버깅 가능 |
| kubelet/kubeadm/kubectl | pkgs.k8s.io v1.37 | `apt-mark hold`로 자동 업그레이드 차단 |
| kubelet | **중지 상태로 둠** | kubeadm이 지시를 줄 때까지 crashloop이 정상이다 |

확인:

```bash
swapon --show                       # 아무것도 없어야 한다
sysctl net.ipv4.ip_forward          # 1
sysctl net.bridge.bridge-nf-call-iptables   # 1
systemctl is-active containerd      # active
sudo crictl ps                      # 컨테이너 런타임이 응답하는가
kubeadm version -o short            # v1.37.0
```

**재실행해도 안전하다.** 이미 클러스터에 참여한 노드(`/etc/kubernetes/kubelet.conf` 존재)에서는
containerd/kubelet을 **재시작하지 않는다.** 설정 때문에 재시작이 필요하면 수동으로 한다.

> `apt-get install`이 배포판의 `containerd` 패키지를 끌고 와 있는 경우가 있다.
> 그 상태에서는 공식 tarball과 충돌해 엉뚱한 버전이 소켓을 잡는다.
> 스크립트는 `/usr/bin/containerd`를 발견하면 제거하고 `/usr/local/bin/containerd`를 설치하며,
> 기동 후 `readlink -f /proc/<pid>/exe`로 **실제 실행 바이너리를 검증**한다.

---

## 2. 컨트롤 플레인 초기화 (`k8s-cp` 에서만)

```bash
sudo ~/scripts/01-control-plane.sh
```

옵션 (필요할 때만):

```bash
sudo ~/scripts/01-control-plane.sh \
  --pod-cidr 10.244.0.0/16 \
  --endpoint <CP-IP> \
  --skip-cni
```

이 스크립트가 하는 일:

1. 노드 IP 자동 감지 → `/root/kubeadm-config.yaml` 생성
   - 플래그를 나열하지 않고 YAML로 남긴다. 재현과 HA 확장이 쉬워진다.
2. `kubeadm init --config /root/kubeadm-config.yaml --upload-certs`
   - PKI 생성 → `/etc/kubernetes/manifests`에 static pod 배치 → 컨트롤 플레인 기동 → 토큰 발급
3. `admin.conf` → `~/.kube/config`
   - **`admin.conf`는 cluster-admin 권한의 superuser 자격이다. 노드 밖으로 복사하지 않는다.**
4. Calico v3.32.2 설치 (CRD → operator → `Installation` CR)
   - **Calico 기본 IPPool CIDR은 `192.168.0.0/16`** — UTM/Multipass 기본 대역과 겹친다.
     스크립트는 `--pod-cidr`(기본 `10.244.0.0/16`)을 IPPool에 그대로 넣는다.
     `kubeadm`의 `podSubnet`과 Calico IPPool CIDR은 **반드시 같아야 한다.**
5. 노드 Ready 대기 후 상태 출력

성공하면:

```
NAME       STATUS   ROLES           AGE   VERSION
k8s-cp     Ready    control-plane   2m    v1.37.0
```

**join 명령을 기록해 둔다.** 스크립트가 마지막에 출력하는 명령을 그대로 쓰거나:

```bash
sudo kubeadm token create --print-join-command   # 토큰 기본 유효기간 24시간
```

> 참고: `--pod-cidr` 기본값이 Calico 기본값과 다른 이유는 충돌 회피 때문이다.
> VM 네트워크가 `192.168.0.0/16` 밖이면 Calico 기본값을 그대로 써도 된다.
> 어느 쪽이든 **호스트/Pod 대역이 겹치면 라우팅이 조용히 깨진다.**

---

## 3. 워커 join (`k8s-w1` 에서만)

공통 준비(`00-common.sh`)를 먼저 마친 뒤:

```bash
sudo ~/scripts/02-worker.sh "kubeadm join <CP-IP>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>"
```

또는 인자를 나눠서:

```bash
sudo ~/scripts/02-worker.sh --endpoint <CP-IP> --token <token> --hash sha256:<hash>
```

스크립트가 `--cri-socket`을 자동으로 붙인다. 런타임이 여러 개거나 자동 감지가 실패하면 join이 중단된다.

컨트롤 플레인에서 확인:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

새 노드는 **CNI Pod(calico-node)가 뜬 뒤에** Ready가 된다. 몇십 초 걸린다.

---

## 4. 검증

컨트롤 플레인에서:

```bash
~/scripts/03-verify.sh
```

| 확인 항목 | 무엇을 검사하나 |
|---|---|
| 노드 상태 | 모든 노드 `Ready` |
| kube-system Pod | apiserver/scheduler/controller-manager/etcd/CoreDNS `Running` |
| static pod | `/etc/kubernetes/manifests` 파일 존재 |
| cgroup driver | kubelet(`config.yaml`)과 containerd(`SystemdCgroup`) 일치 |
| 노드 포트 | `6443`(apiserver), `10250`(kubelet) |
| Pod 통신 | Pod IP 직접 통신 + `kubernetes.default.svc:443` (DNS/kube-proxy 경유) |

---

## 5. Ansible로 반복하기

수동 절차를 익힌 뒤에는 Ansible로 **해체 → 재구축을 반복**한다.
호스트(맥/리눅스)에 `ansible`이 필요하다: `brew install ansible` 또는 `pip install ansible`.

```bash
cd clusters/kubeadm/ansible
cp inventory/hosts.ini.example inventory/hosts.ini
$EDITOR inventory/hosts.ini        # multipass list 또는 UTM에서 확인한 IP 입력

ansible -i inventory/hosts.ini all -m ping        # 연결 확인

ansible-playbook -i inventory/hosts.ini playbooks/01-prepare-nodes.yml
ansible-playbook -i inventory/hosts.ini playbooks/02-install-common.yml
ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml
ansible-playbook -i inventory/hosts.ini playbooks/verify.yml
```

**해체 후 재구축** — 04단계 완료 기준인 "문서 없이 40분 내 구축"을 위한 훈련:

```bash
ansible-playbook -i inventory/hosts.ini playbooks/reset-cluster.yml
# 위 4개 플레이북 재실행
```

건너뛰기 규칙: `02`는 `kubeadm`이 있으면, `03`은 `/etc/kubernetes/admin.conf`가 있으면,
`04`는 `/etc/kubernetes/kubelet.conf`가 있으면 건너뛴다.
강제 재실행은 `-e k8s_force_reinstall=true`.

### kubeadm과 Ansible의 역할 분담

| | 하는 일 |
|---|---|
| **Ansible** | 노드 상태(커널·swap·패키지)를 선언적으로 맞추고 여러 노드에 동시 적용 |
| **kubeadm** | 클러스터 수명주기(init/join/upgrade/reset). 인증서와 static pod는 kubeadm만 안다 |

→ 클러스터 자체를 Ansible로 "만들지" 않는다. Ansible은 kubeadm을 호출하는 오케스트레이터다.
`kubespray`가 이 둘을 합친 것이지만, 학습 단계에서는 각각을 분리해서 보는 편이 낫다.

---

## 6. HA로 확장 (선택)

`--control-plane-endpoint`가 인증서 SAN에 박히므로 **처음부터** 넣어야 한다.
단일 CP로 만든 뒤에는 HA로 전환할 수 없다(kubeadm 제약).

```bash
# 처음 init 할 때
sudo ~/scripts/01-control-plane.sh --endpoint <LB-IP>   # LB 또는 DNS 이름

# 두 번째 컨트롤 플레인 추가
sudo kubeadm token create --print-join-command --ttl 2h
sudo kubeadm init phase upload-certs --upload-certs
sudo ~/scripts/02-worker.sh "kubeadm join <LB-IP>:6443 \
  --control-plane --certificate-key <key> --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>"
```

HA는 컨트롤 플레인이 홀수(3대)여야 etcd 쿼럼이 유지된다. VM 3대 + 워커 2대면 RAM 2G로 낮춰 총 20GB 내로 맞춘다.

---

## 7. 트러블슈팅

01단계에서 배운 진단 습관을 그대로 쓴다. **Pod가 이상하면 `describe` → `logs` → static pod manifest 순서.**

| 증상 | 원인 후보 | 확인 |
|---|---|---|
| 노드 `NotReady` | CNI 미설치 | `kubectl get pods -n kube-system` 에 calico-node 있는가 |
| 노드 `NotReady` | `ip_forward=0` | `sysctl net.ipv4.ip_forward` |
| 모든 Pod `Pending` | CNI 미설치 또는 IPPool CIDR 불일치 | `kubectl get tigerastatus`, `kubectl get ippool -o yaml` |
| kubelet 시작 실패 | swap 활성 | `swapon --show`, `journalctl -u kubelet -n 50` |
| Pod가 `ContainerCreating`에서 멈춤 | sandbox 이미지 pull 실패 | `crictl images \| grep pause`, `crictl pull registry.k8s.io/pause:3.10.2` |
| apiserver 무한 재시작 | 인증서 SAN에 넣은 IP와 실제 접속 IP 불일치 | `kubectl logs -n kube-system kube-apiserver-<node>` |
| `kubectl` 접속 거부 | `admin.conf` 미복사 또는 context 문제 | `kubectl config get-contexts`, `kubectl cluster-info` |
| join 토큰 오류 | 토큰 만료(24h) | 컨트롤 플레인에서 `kubeadm token create --print-join-command` |
| CA 해시 불일치 | 다른 클러스터의 명령을 사용 | `openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \| openssl rsa -pubin -outform der 2>/dev/null \| openssl dgst -sha256 -hex` |
| Pod 간 통신 안 됨 | `bridge-nf-call-iptables=0` | `sysctl net.bridge.bridge-nf-call-iptables` |

**자주 쓰는 명령**

```bash
# kubelet 로그
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -n 100

# 컨테이너 런타임 직접 보기 (k8s가 안 될 때)
sudo crictl ps -a
sudo crictl images
sudo crictl logs <container-id>

# 컨트롤 플레인 static pod 로그
sudo crictl logs $(sudo crictl ps --name kube-apiserver -q)

# kubeadm 사전 점검만 다시
sudo kubeadm init phase preflight --config /root/kubeadm-config.yaml

# 초기화 로그
sudo journalctl -u kubelet --since "10 min ago" | grep -i kubeadm
```

---

## 8. 되돌리기

```bash
# 워커에서
kubectl drain <node> --delete-emptydir-data --force --ignore-daemonsets   # 컨트롤 플레인에서
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet
kubectl delete node <node>                                                # 컨트롤 플레인에서

# 컨트롤 플레인에서
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /var/lib/etcd /etc/kubernetes
```

`kubeadm reset`은 iptables/IPVS 규칙을 정리하지 않는다. 필요하면:

```bash
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo ipvsadm -C
```

Ansible을 쓴다면 `playbooks/reset-cluster.yml`이 위 과정을 대신한다.

---

## 다음 단계

- [04-onprem-cka](../../04-onprem-cka/) W12: etcd 스냅샷 백업·복구, n-1 → n 업그레이드, 인증서 갱신
- MetalLB 설치 후 LoadBalancer Service 실습
- 관통 프로젝트([app/](../../app/))를 이 클러스터로 이전
