# 유형 C. 노드 장애 진단

> [← 유형 B. static pod와 컨트롤 플레인](02-static-pods.md) · [▶ 유형 D. 클러스터 컴포넌트 장애](04-control-plane-troubleshooting.md) · [목록](README.md)

> 트러블슈팅 도메인 **30%**. 00-setup의 "만들기 → 고장 내기 → 진단하기" 규칙이 그대로 시험이다.

## C-1. NotReady 노드 — 5가지 원인을 구분하라

**문제**
워커 노드 `study-worker`가 `NotReady`가 되는 원인을 **최소 4가지** 만들고, 각각을 **구분해서** 진단하라. 그리고 모든 경우에 대해 1분 안에 복구하라.

<details><summary>풀이 — 진단 순서</summary>

**먼저 이 4개를 본다. 대부분 여기서 원인이 나온다.**

```bash
kubectl get nodes -o wide
kubectl describe node study-worker | sed -n '/Conditions/,/Addresses/p'
kubectl describe node study-worker | grep -A20 'Events:'
```

```bash
# 2) 노드 안으로 들어가서 본다
docker exec study-worker bash

# (노드 내부에서)
systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager
crictl ps
crictl info | head -30       # CRI 소켓이 응답하는지
```

**Conditions가 알려주는 것**

| Condition | True의 의미 | 원인 |
|---|---|---|
| `Ready` | 정상 | False면 아래를 본다 |
| `MemoryPressure` | 메모리 부족 | 파드 축출 발생 |
| `DiskPressure` | 디스크 부족 | 이미지 GC, 축출 |
| `PIDPressure` | 프로세스 한계 | fork 폭탄 |
| `NetworkUnavailable` | CNI 미준비 | **가장 흔하다** |

---

### 원인 ① kubelet 정지 (가장 흔한 시험 문제)

```bash
# 고장 내기
docker exec study-worker systemctl stop kubelet

# 진단
kubectl get node study-worker          # NotReady (수십 초 후)
docker exec study-worker systemctl status kubelet   # inactive (dead)
docker exec study-worker journalctl -u kubelet -n 20 --no-pager
# "Stopped kubelet" 로그

# 복구
docker exec study-worker systemctl start kubelet
kubectl get node study-worker -w       # Ready
```

**시험 포인트**: `describe node`의 마지막 heartbeat 시간을 본다. `kubelet`이 죽으면
**Condition이 갱신되지 않아** `Unknown`/`NotReady`로 굳는다. `LastHeartbeatTime`이 오래됐으면 kubelet 자체를 의심한다.

---

### 원인 ② CNI 제거

**kind의 CNI는 kindnet이다** (Calico가 아니다). DaemonSet 이름이 `kindnet`이고 namespace는 `kube-system`이다.

```bash
# 고장 내기 — kind 는 kindnet 을 클러스터 생성 시에만 넣는다
kubectl delete daemonset -n kube-system kindnet

# 진단
kubectl get pods -n kube-system | grep -i kindnet
kubectl describe node study-worker | grep -i NetworkUnavailable
# 노드 내부 /etc/cni/net.d 가 비어 있다
docker exec study-worker ls -la /etc/cni/net.d/
```

**복구**: kindnet DaemonSet은 kind가 클러스터 생성 시 넣는다. **지우면 재생성이 안 되므로** 가장 빠른 복구는 클러스터 재생성이다.

```bash
kind delete cluster --name study
kind create cluster --config clusters/kind/study-cluster.yaml
```

**시험 포인트**: 시험장에서는 CNI 매니페스트를 다시 `kubectl apply -f`하는 방식으로 복구한다
(Flannel/Calico YAML). **"노드는 등록됐는데 NotReady + NetworkUnavailable=True + CNI Pod 없음"** 이 3종 세트면 CNI다.

---

### 원인 ③ kubelet 설정 오류 (cgroup driver 불일치)

```bash
# 진단
docker exec study-worker cat /var/lib/kubelet/config.yaml | grep -i cgroupDriver
docker exec study-worker cat /etc/containerd/config.toml | grep -i SystemdCgroup
docker exec study-worker journalctl -u kubelet -n 20 --no-pager
# "failed to run Kubelet: misconfiguration: kubelet cgroup driver: \"systemd\"
#  is different from docker cgroup driver: \"cgroupfs\""
```

**복구**: 둘 중 하나로 맞춘다. 정답은 **containerd를 systemd로** 맞추는 것 (cgroup v2 기준).

```bash
docker exec study-worker sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
docker exec study-worker systemctl restart containerd kubelet
```

---

### 원인 ④ swap이 켜짐

```bash
# 고장 내기 (워커 노드 안에서)
docker exec study-worker bash -c 'fallocate -l 512M /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile'

# 진단
docker exec study-worker swapon --show
docker exec study-worker journalctl -u kubelet -n 20 --no-pager
# "failed to run Kubelet: running with swap on is not supported, please disable swap"

# 복구
docker exec study-worker swapoff -a
docker exec study-worker rm -f /swapfile
docker exec study-worker systemctl restart kubelet
```

**시험 포인트**: 에러 메시지가 **원인을 그대로 말해준다.** `journalctl -u kubelet`을 읽는 습관이 점수다.

---

### 원인 ⑤ kubelet 인증서/토큰 문제

```bash
# 진단
docker exec study-worker journalctl -u kubelet -n 30 --no-pager | grep -iE 'certificate|x509|unauthorized|forbidden'
```

**복구** (kubeadm 클러스터, 시험에서 자주 나온다):

```bash
# 워커에서 kubelet.conf 삭제 후 재join
rm -f /etc/kubernetes/kubelet.conf /var/lib/kubelet/pki/kubelet-client-current.pem
systemctl restart kubelet
# kubelet 이 CSR 을 새로 만든다 → 컨트롤 플레인에서 승인
kubectl get csr
kubectl certificate approve <csr-name>
```

**핵심 구분표**

| 증상 | 1순위 의심 |
|---|---|
| `NotReady` + CNI Pod 없음 + `NetworkUnavailable=True` | **CNI 미설치** |
| `NotReady` + `systemctl status kubelet` inactive | **kubelet 정지** |
| `NotReady` + kubelet이 재시작 반복 | **설정 오류(swap/cgroup/인증서)** — journalctl |
| `Ready` 인데 Pod가 안 뜸 | **노드가 아니라 다른 원인** (taint, 스케줄러, 이미지) |
| `Unknown` + heartbeat 만료 | **kubelet 또는 네트워크 단절** |

</details>

---

## C-2. 컴포넌트 로그로 원인 찾기

**문제**
`study-worker` 노드의 kubelet이 계속 재시작된다. **노드 안에 들어가지 않고** kubectl만으로 로그를 확보하라. 노드 안에 들어가는 방법과의 차이도 설명하라.

<details><summary>풀이</summary>

```bash
# 방법 1) 노드 안에서 직접 (가장 확실)
docker exec study-worker journalctl -u kubelet -n 100 --no-pager
docker exec study-worker journalctl -u kubelet -f          # 실시간
docker exec study-worker journalctl -u kubelet --since "10 min ago"

# 방법 2) kubectl 로 (API 서버를 거친다)
kubectl get --raw "/api/v1/nodes/study-worker/proxy/logs/?query=kubelet" | tail -50
# 또는
kubectl get --raw "/api/v1/nodes/study-worker/proxy/logs/journal" | tail -50
```

**차이**

| | 노드 직접 (`journalctl`) | `kubectl get --raw .../proxy/logs` |
|---|---|---|
| 전제 | SSH/exec 가능, kubelet의 systemd 관리 | **API 서버 + kubelet이 살아 있어야** 함 |
| 범위 | systemd 유닛 전체 | kubelet이 제공하는 로그 |
| 쓰는 때 | kubelet이 죽어서 API로 안 될 때 | kubelet은 살아있고 원격에서 볼 때 |

**시험 포인트**: kubelet이 완전히 죽으면 두 번째 방법이 안 된다. 이때는 노드에 SSH로 들어간다.
시험 환경은 보통 SSH 접속 정보를 준다. **"API 서버가 죽어서 kubectl이 안 되면 SSH로 들어가
static pod manifest와 `crictl`로 본다"** 가 최후의 수단이다.

**컨트롤 플레인 컴포넌트 로그** (static pod):

```bash
kubectl -n kube-system logs kube-apiserver-study-control-plane
kubectl -n kube-system logs etcd-study-control-plane
kubectl -n kube-system logs kube-scheduler-study-control-plane --tail=50

# API 서버가 죽어 kubectl 이 안 될 때는 컨테이너 런타임에서 직접
docker exec study-control-plane crictl ps
docker exec study-control-plane crictl logs <container-id>
```

</details>

---

## C-3. `ContainerCreating`에 멈춘 Pod 진단

**문제**
`crictl pull`이 실패하는 이미지를 쓰는 Pod가 있다. Pod가 어느 단계에서 멈추는지 확인하고, 원인을 `kubectl describe`와 `crictl` **양쪽**에서 확인하라.

<details><summary>풀이</summary>

```bash
kubectl run broken --image=registry.k8s.io/does-not-exist:v1

kubectl get pod broken -w
# NAME     READY   STATUS              ...
# broken   0/1     ContainerCreating
```

```bash
# 1) describe 의 Events 가 1순위
kubectl describe pod broken | tail -20
# Warning  Failed  kubelet  Failed to pull image "registry.k8s.io/does-not-exist:v1":
#          failed to resolve reference ... : not found
```

```bash
# 2) 런타임에서 직접 본다 (kubelet을 거치지 않는 정보)
docker exec study-worker crictl ps -a
docker exec study-worker crictl logs <container-id>       # 컨테이너가 떴다면
docker exec study-worker crictl inspect <container-id> | head -50
docker exec study-worker crictl events                     # 런타임 이벤트
```

**"Pod가 ContainerCreating" 계열 4가지 원인**

| 원인 | 확인 |
|---|---|
| 이미지 pull 실패 (이름/태그/레지스트리 인증) | `describe` Events |
| **sandbox(pause) 이미지 pull 실패** | `crictl images \| grep pause` |
| **CNI 미준비** (IP를 못 받음) | `NetworkUnavailable`, `/etc/cni/net.d` |
| 볼륨 mount 실패 (PVC, ConfigMap, Secret) | `describe` Events — **02 범위** |

**pause 이미지 문제**는 00-setup에서 배운 kubeadm 트러블슈팅과 같은 뿌리다.

```bash
docker exec study-worker crictl images | grep pause
docker exec study-worker crictl pull registry.k8s.io/pause:3.10.2   # 수동 pull 로 비교
```

**정리**

```bash
kubectl delete pod broken
```

</details>

---

## C-4. 리소스 사용량 모니터링

**문제**
① 클러스터의 노드/Pod 리소스 사용량을 확인하라. ② 만약 명령이 실패한다면 **왜 실패했는지** 진단하고, metrics-server를 설치해 해결하라. ③ 실패할 때 **대신 쓸 수 있는 방법**을 2가지 찾으라.

<details><summary>풀이</summary>

```bash
kubectl top nodes
kubectl top pods -A
```

kind에는 metrics-server가 없다 → 실패한다.

```bash
error: Metrics API not available
```

**진단 순서**

```bash
# 1) APIService 상태 — metrics-server 는 APIService 를 등록한다
kubectl get apiservice | grep metrics
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml | sed -n '/conditions/,+8p'

# 2) 파드 상태
kubectl get pods -n kube-system | grep metrics
kubectl logs -n kube-system deploy/metrics-server

# 3) 흔한 원인: kubelet 인증서 검증 실패 (자체 서명 인증서)
#    "x509: cannot validate certificate for 172.x.x.x because it doesn't contain any IP SANs"
```

**해결 (kind/자체 서명 환경)**

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 자체 서명 인증서 환경에서는 kubelet CA 검증을 우회해야 한다
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout status deploy/metrics-server
kubectl top nodes
```

**③ 대안** (metrics-server 없이 리소스를 판단하는 법)

```bash
# 방법 A) 노드의 Allocatable / Requests / Limits — "예약량" 기준
kubectl describe node study-worker | sed -n '/Allocated resources/,/Events/p'

# 방법 B) 실행 중인 컨테이너의 실측값 (노드 안에서)
docker exec study-worker crictl stats
docker exec study-worker crictl stats -a        # 전체
```

**시험 포인트**
- `kubectl top`이 안 나오면 **"metrics-server가 없거나 APIService가 Unavailable"** 로 바로 가야 한다.
- `describe node`의 `Allocated resources`는 **실제 사용량이 아니라 requests/limits 합계**다.
  이 구분을 물어보는 문제가 나온다("이 노드에 얼마나 여유가 있는가").

**정리**

```bash
kubectl -n kube-system delete deploy metrics-server --ignore-not-found
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found
```

</details>
