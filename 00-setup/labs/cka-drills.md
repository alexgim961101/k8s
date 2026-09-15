# CKA 실전 문제 — 00-setup 범위

> **출제 기준**: CNCF 공식 [CKA Curriculum v1.35](https://github.com/cncf/curriculum) (도메인 비중은 개정될 수 있으니 응시 전 최신 확인)
> **대상 범위**: 00-setup에서 다룬 것 — 클러스터 아키텍처 · kubeadm 구축 · 노드/컴포넌트 트러블슈팅
> **환경**: `clusters/kind/study-cluster.yaml`의 kind 클러스터 (3노드). 파괴적 실습은 **언제든 버릴 수 있는 클러스터에서** 한다.

## 사용법

1. 문제를 읽고 **먼저 스스로 푼다.** 답은 `<details>` 안에 접혀 있다.
2. 시간을 잰다. CKA는 **문제당 평균 6분**이다 (2시간 / 약 15~20문제).
3. 막히면 바로 답을 보지 말고 **① `kubectl explain` ② `kubectl describe` ③ `kubectl get events`** 순서로 시도한다.
4. 다 풀면 아래 **자가 채점표**로 약점을 기록한다.

**공통 준비**

```bash
cd /Users/alex/src/study/k8s
kind create cluster --config clusters/kind/study-cluster.yaml

alias k=kubectl
export do='--dry-run=client -o yaml'     # 시험장 필수 습관
```

---

## 0. 00-setup ↔ CKA 도메인 매핑

공식 커리큘럼의 도메인 중 **00-setup에서 이미 다룬 항목**만 표시했다.

| 도메인 (비중) | 00-setup에서 다룬 competency | 이 문서의 문제 |
|---|---|---|
| **Cluster Architecture, Installation & Configuration (25%)** | Prepare underlying infrastructure for installing a Kubernetes cluster | F-1, F-2 |
| | Create and manage Kubernetes clusters using kubeadm | F-1, F-2, F-3 |
| | Understand extension interfaces (CNI, CRI, CSI) | F-3, C-3 |
| | Manage the lifecycle of Kubernetes clusters | F-4 |
| **Troubleshooting (30%)** | Troubleshoot clusters and nodes | C-1, C-2, C-3 |
| | Troubleshoot cluster components | D-1, D-2, D-3 |
| | Manage and evaluate container output streams | D-2, A-2 |
| | Monitor cluster and application resource usage | C-4 |
| | Troubleshoot services and networking | E-1, E-2 |
| **Workloads & Scheduling (15%)** | Configure Pod admission and scheduling (limits, node affinity, etc.) | G-3 |
| | Understand the primitives used to create robust, self-healing deployments | G-1, G-2 |
| **Services & Networking (20%)** | Understand and use CoreDNS | E-2 |
| **Storage (10%)** | — | 02 범위 |
| (미리보기) RBAC | Manage role based access control | H-1 |

**00-setup의 셀프 체크 5문항 ↔ 문제 매핑**

| 셀프 체크 | 대응 문제 |
|---|---|
| 1. kind 노드는 무엇인가 | F-1 (VM과의 차이), B-1 |
| 2. API 서버 없이 컨트롤 플레인이 뜨는 이유 | B-1, C-3 |
| 3. 스케줄러를 멈추면 | D-1 |
| 4. kubeconfig 구조 | A-1, A-2, H-1 |
| 5. 선언적 상태 / reconciliation | G-1, G-2 |
| (보넘) 컴포넌트 표를 직접 채우기, 최소 2개 멈춰보기 | D-1, D-2, D-3 |

---

# 유형 A. kubeconfig와 context

> 셀프 체크 4. CKA는 **여러 클러스터와 kubeconfig를 오가며** 문제를 낸다. "주어진 컨텍스트에서 작업하라"는 지시가 반복해서 나온다.

## A-1. 컨텍스트 전환과 정보 추출

**문제**
현재 kubeconfig에서 ① 컨텍스트 목록과 현재 컨텍스트를 확인하고, ② 현재 컨텍스트가 사용하는 **클러스터 이름, 서버 주소, 사용자 이름, 네임스페이스**를 각각 출력하라. ③ 그리고 그 결과를 `/tmp/current-context.txt`에 저장하라.

<details><summary>풀이</summary>

```bash
# ① 목록과 현재 컨텍스트
kubectl config get-contexts
kubectl config current-context

# ② 값 추출 — --minify 는 "현재 컨텍스트만" 남긴다
kubectl config view --minify -o jsonpath='{.clusters[0].name}{"\n"}'
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl config view --minify -o jsonpath='{.users[0].name}{"\n"}'
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}{"\n"}'
```

③ 한 번에 저장:

```bash
{
  echo "context:   $(kubectl config current-context)"
  echo "cluster:   $(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
  echo "server:    $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  echo "user:      $(kubectl config view --minify -o jsonpath='{.users[0].name}')"
  echo "namespace: $(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}' || echo default)"
} > /tmp/current-context.txt
cat /tmp/current-context.txt
```

**kubeconfig의 3층 구조**

| 필드 | 가리키는 것 |
|---|---|
| `clusters[]` | **어디로** — API 서버 주소 + CA 인증서 |
| `users[]` | **누구로** — 클라이언트 인증서/토큰 |
| `contexts[]` | 그 둘의 **조합** + 기본 namespace |
| `current-context` | 지금 쓰는 context |

`--minify` 없이 `view`하면 전체가 나오고, 인증서는 `DATA+OMITTED`로 가려진다.
**자주 하는 실수**: `-o jsonpath`에서 `.clusters[0]`은 "첫 번째"지 "현재"가 아니다. `--minify`와 반드시 같이 쓴다.

**인증서 원문을 봐야 할 때** (시험에 가끔 나온다):

```bash
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -dates
```

</details>

---

## A-2. kubeconfig가 깨졌을 때 복구

**문제**
`~/.kube/config`의 `server` 주소가 잘못된 값(`https://127.0.0.1:9999`)으로 바뀌어 `kubectl get nodes`가 실패한다. **파일을 통째로 지우지 않고** 원복한 뒤 노드가 보이는 것을 확인하라. (kind는 컨트롤 플레인에서 kubeconfig를 다시 얻을 수 있다.)

<details><summary>풀이</summary>

```bash
# 0) 실패 재현
cp ~/.kube/config ~/.kube/config.bak
kubectl config set-cluster kind-study --server=https://127.0.0.1:9999
kubectl get nodes          # 연결 실패

# 1) 잘못된 필드만 되돌린다
kubectl config set-cluster kind-study --server=https://127.0.0.1:<올바른-포트>

# 포트를 모르면 kind 컨테이너에서 직접 확인한다
docker exec study-control-plane cat /etc/kubernetes/admin.conf | grep server

# 2) 확인
kubectl get nodes
```

**정석 복구 (파일이 완전히 깨졌거나 시험에서 새 kubeconfig를 줄 때)**

```bash
# 컨트롤 플레인 노드에서 그대로 복사 — admin.conf 는 cluster-admin 자격이다
docker cp study-control-plane:/etc/kubernetes/admin.conf /tmp/admin.conf
export KUBECONFIG=/tmp/admin.conf
kubectl get nodes
```

또는 `config set-*` 계열로 조립한다:

```bash
kubectl config set-cluster mycluster --server=https://... --certificate-authority=ca.crt
kubectl config set-credentials myuser --client-certificate=user.crt --client-key=user.key
kubectl config set-context myctx --cluster=mycluster --user=myuser --namespace=myns
kubectl config use-context myctx
```

**시험 포인트**
- `KUBECONFIG` 환경변수는 **콜론으로 여러 파일을 합칠 수 있다**: `KUBECONFIG=~/.kube/config:/tmp/extra.conf:...`
- 시험 문제에 "you have access to cluster X"라고 나오면 **`kubectl config use-context`를 먼저 실행**한다. 안 하면 다른 클러스터에서 작업해서 0점 처리된다.
- `admin.conf`는 superuser 자격이다. 시험에서는 새 사용자용 kubeconfig를 만들라고 한다 → **H-1**로 연결된다.

**재현/정리**

```bash
cp ~/.kube/config.bak ~/.kube/config    # 원복
```

</details>

---

# 유형 B. static pod와 컨트롤 플레인

> 셀프 체크 2. **"닭과 달걀"** 문제와 static pod는 CKA 단골이다. `--dry-run=client -o yaml | ... /etc/kubernetes/manifests/` 패턴이 핵심이다.

## B-1. static pod의 정체와 경로

**문제**
① 컨트롤 플레인 컴포넌트가 static pod로 뜨는 **디렉토리 경로**를 확인하고, ② `kube-apiserver` static pod가 어떤 방식으로 관리되는지(어떤 오브젝트에 대응되는지) 확인하라. ③ kubelet의 static pod 경로 설정이 어디에 있는지도 찾아라.

<details><summary>풀이</summary>

```bash
# ① 경로 — kind 노드는 컨테이너다
docker exec study-control-plane ls -1 /etc/kubernetes/manifests/
# kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml  etcd.yaml (kind는 etcd도 여기)

# ② API 서버 입장에서 static pod 는 mirror pod 로 보인다
kubectl get pods -n kube-system | grep -E 'apiserver|scheduler|controller-manager|etcd'
kubectl get pod -n kube-system kube-apiserver-study-control-plane -o yaml | sed -n '/annotations/,/^  [a-z]/p'
# → kubernetes.io/config.mirror: <해시> 가 있으면 mirror pod.
#    API 서버로 삭제할 수 없다. 파일을 지워야 사라진다.

# ③ kubelet 설정에서 staticPodPath 확인
docker exec study-control-plane cat /var/lib/kubelet/config.yaml | grep -i staticPodPath
```

**구조 정리**

```
kubelet 이 /etc/kubernetes/manifests/*.yaml 을 감시
   │ 파일이 추가되면 → 컨테이너 생성
   │ 파일이 수정되면 → 컨테이너 재생성
   │ 파일이 삭제되면 → 컨테이너 제거
   ↓
API 서버가 떠 있다면 mirror pod 도 함께 생성 (읽기 전용, kubectl delete 불가)
```

**"닭과 달걀"**: 컨트롤 플레인을 띄우려면 API 서버가 필요한데, API 서버를 만들려면 API 서버가 필요하다.
해법이 **kubelet이 파일을 직접 읽는 static pod**다. kubelet은 API 서버 없이도 동작한다.

**자주 하는 실수**
- `kubectl delete pod kube-scheduler-...` → 지워지지 않는다(mirror pod). **파일을 옮기거나 지워야 한다.**
- static pod를 수정할 때 `kubectl edit`을 쓰면 안 된다. 파일을 직접 고치고 저장한다(자동 반영).

</details>

---

## B-2. static pod로 컴포넌트 추가하기

**문제**
`/etc/kubernetes/manifests/`에 커스텀 static pod를 하나 만들어라.
- 이름: `static-web`
- 이미지: `nginx:1.27`
- 라벨: `app=static-web`
- 호스트 포트 8088 → 컨테이너 80 (노드 IP로 접속 가능해야 한다)

그리고 API 서버에서 이 Pod를 지우려 하면 어떤 일이 일어나는지 확인하라.

<details><summary>풀이</summary>

```bash
# 1) 매니페스트를 파일로 만든다. static pod 는 "Pod" 오브젝트다.
cat <<'EOF' | docker exec -i study-control-plane tee /etc/kubernetes/manifests/static-web.yaml >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  namespace: default
  labels:
    app: static-web
spec:
  containers:
    - name: web
      image: nginx:1.27
      ports:
        - containerPort: 80
          hostPort: 8088
EOF

# 2) kubelet 이 감지한다 (수 초~수십 초)
kubectl get pod static-web-study-control-plane
kubectl get pod static-web-study-control-plane -o wide
```

**이름에 노드명이 붙는다.** static pod는 `metadata.name`에 `<node-hostname>`이 자동으로 접미된다.
(`static-web` → `static-web-study-control-plane`)

```bash
# 3) mirror pod 는 삭제되지 않는다
kubectl delete pod static-web-study-control-plane
# → 삭제된 것처럼 보이지만 즉시 다시 뜬다. kubelet 이 계속 파일을 보고 있기 때문이다.

# 4) 실제로 없애려면 파일을 지운다
docker exec study-control-plane rm /etc/kubernetes/manifests/static-web.yaml
kubectl get pod static-web-study-control-plane     # NotFound
```

**시험 포인트**
- static pod 생성 문제는 **`/etc/kubernetes/manifests/`에 파일을 놓는 것**이 전부다. Deployment/ReplicaSet이 없다는 점이 일반 Pod와 다르다.
- `hostPort`는 kube-proxy를 거치지 않는다. 노드 IP:8088로 직접 붙는다.
- 실무에서는 etcd 백업용 사이드카나 노드 전용 에이전트를 이 방식으로 넣는다.

**정리**

```bash
docker exec study-control-plane rm -f /etc/kubernetes/manifests/static-web.yaml
```

</details>

---

# 유형 C. 노드 장애 진단

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

---

# 유형 D. 클러스터 컴포넌트 장애

> CKA 트러블슈팅의 절반은 **컨트롤 플레인 컴포넌트가 죽었을 때** 복구하는 것이다.
> `kubectl`이 안 되는 상황에서 **어떻게 들어가는가**가 실력이다.

## D-1. kube-scheduler 정지 → 기존 Pod는? 새 Pod는?

**문제 (셀프 체크 3)**
kube-scheduler를 멈추고 ① **기존 Pod**와 ② **새로 만든 Pod**에 각각 무슨 일이 일어나는지 관찰하라. ③ 그리고 스케줄러를 복구했을 때 새 Pod가 어떻게 되는지 확인하라.

<details><summary>풀이</summary>

```bash
# 기준 상태
kubectl get pods -o wide

# 스케줄러 정지 — mirror pod 는 delete 로 안 지워진다. 파일을 옮긴다.
docker exec study-control-plane mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/

# 확인: kube-system 에서 사라진다
kubectl get pods -n kube-system | grep scheduler     # 아무것도 없다

# ① 기존 Pod
kubectl get pods -o wide
# → 아무 변화 없다. 이미 노드에 배정(bind)되었고, kubelet 이 계속 돌보므로 정상 동작.
#    스케줄링은 "배치"일 뿐이고 "실행"은 kubelet 이 한다.

# ② 새 Pod
kubectl run newpod --image=nginx:1.27
kubectl get pod newpod -o wide
# → STATUS 가 Pending, NODE 가 <none>

kubectl describe pod newpod | tail -10
# → Events 가 비어 있거나 "no nodes available" 류. 
#    스케줄러가 없으니 아무 이벤트도 만들지 않는다. ← 이게 핵심 단서다!
```

**③ 복구**

```bash
docker exec study-control-plane mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/

kubectl get pods -n kube-system | grep scheduler     # 다시 뜬다
kubectl get pod newpod -o wide                        # 자동으로 노드에 배정된다
# Pending 이던 Pod 는 스케줄러가 돌아오면 큐에서 꺼내 처리한다.
```

**정리**

| | 스케줄러 정지 시 |
|---|---|
| 기존 Pod | **영향 없음** — 이미 노드에 배정됨, kubelet이 계속 관리 |
| 새 Pod | **Pending** — 배정할 주체가 없다 |
| Deployment가 새 ReplicaSet 생성 | Pod는 만들어지지만 **Pending** |
| Events | **아무 이벤트도 없다** (이벤트 생성자도 스케줄러다) |

**진단 포인트**: `Pending`인데 **`describe`의 Events가 비어 있으면 스케줄러를 의심**한다.
반대로 `0/3 nodes are available: 3 Insufficient cpu` 같은 메시지가 있으면 스케줄러는 살아있다
(자원/taint/affinity 문제다).

**정리**

```bash
kubectl delete pod newpod
kubectl get pods -n kube-system | grep scheduler   # 복구 확인
```

</details>

---

## D-2. 컨트롤 플레인 컴포넌트가 안 뜰 때 — 매니페스트 진단

**문제**
`kube-apiserver` static pod 매니페스트에 **없는 이미지 태그**를 넣어 고장 내라. 그리고 ① `kubectl`이 어떻게 되는지, ② API 서버가 죽은 상태에서 **어떻게 원인을 찾는지**, ③ 복구 방법을 확인하라.

<details><summary>풀이</summary>

```bash
# 고장 내기 — 매니페스트의 이미지 태그를 엉뚱하게 바꾼다
docker exec study-control-plane cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/apiserver.yaml.bak
docker exec study-control-plane sed -i 's|image: registry.k8s.io/kube-apiserver:.*|image: registry.k8s.io/kube-apiserver:v0.0.0|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# ① kubectl 이 죽는다
kubectl get nodes
# The connection to the server ... was refused
```

**② API 서버 없이 진단하는 순서**

```bash
# 1) 컨테이너 런타임에서 직접 본다 — API 서버를 거치지 않는다
docker exec study-control-plane crictl ps -a | grep apiserver
# CONTAINER ID  IMAGE                                  STATE      NAME
# xxx           registry.k8s.io/kube-apiserver:v0.0.0  Exited     kube-apiserver

docker exec study-control-plane crictl logs <container-id>
# "exec: ... no such file" 또는 image pull 실패 로그

# 2) kubelet 이 뭐라고 하는지 (static pod 를 관리하는 주체)
docker exec study-control-plane journalctl -u kubelet -n 50 --no-pager | grep -i apiserver

# 3) 매니페스트가 문법적으로 맞는지
docker exec study-control-plane cat /etc/kubernetes/manifests/kube-apiserver.yaml

# 4) mirror pod 는 API 서버가 없으면 볼 수 없다 → kubectl 로는 안 된다
```

**③ 복구**

```bash
docker exec study-control-plane cp /tmp/apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml

# kubelet 이 파일 변경을 감지해 재생성한다 (수십 초)
sleep 20
kubectl get nodes
kubectl get pods -n kube-system | grep apiserver
```

**핵심 정리 — "kubectl이 안 될 때의 사다리"**

```
kubectl 이 안 된다
   │
   ├─ 1. 컨테이너 런타임을 본다 (kubelet/API 서버 무관)
   │     docker exec <node> crictl ps -a
   │     docker exec <node> crictl logs <id>
   │
   ├─ 2. kubelet 을 본다 (static pod 관리자)
   │     docker exec <node> journalctl -u kubelet -n 100 --no-pager
   │
   ├─ 3. static pod 매니페스트를 본다
   │     docker exec <node> cat /etc/kubernetes/manifests/*.yaml
   │
   └─ 4. etcd 를 본다 (여기까지 왔는데도 안 되면 데이터 계층)
         docker exec <node> crictl ps -a | grep etcd
```

**시험 포인트**
- **API 서버를 고칠 때는 API 서버를 쓰지 못한다.** 이 사다리를 몸에 익혀야 한다.
- 매니페스트를 잘못 고쳤을 때를 대비해 **수정 전 백업**(`cp ... .bak`)이 시험에서 시간을 아낀다.
- `kubelet`이 파일 변경을 감지하는 데 **최대 1분** 걸릴 수 있다. 강제하려면 `systemctl restart kubelet`.

</details>

---

## D-3. etcd 상태 확인

**문제**
① etcd가 정상인지 확인하라. ② etcd 데이터 디렉토리 경로를 static pod 매니페스트에서 찾아라. ③ etcd에 저장된 객체 수를 세어라. (W12의 스냅샷 백업의 사전 지식이다.)

<details><summary>풀이</summary>

```bash
# ① etcd 프로세스/컨테이너 확인
kubectl get pods -n kube-system | grep etcd
docker exec study-control-plane crictl ps | grep etcd

# ② 매니페스트에서 데이터 경로 확인
docker exec study-control-plane grep -E 'data-dir|listen-|advertise-|--name' /etc/kubernetes/manifests/etcd.yaml
# --data-dir=/var/lib/etcd
# --advertise-client-urls=https://172.x.x.x:2379
# --listen-client-urls=https://127.0.0.1:2379,https://172.x.x.x:2379
```

**③ etcdctl로 상태 확인 — 정확한 엔드포인트와 인증서가 필요하다**

```bash
docker exec study-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list -w table
'
```

```bash
# 엔드포인트 헬스
docker exec study-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health -w table
'
```

**객체 수 세기** (시험 단골):

```bash
# 루트 키만 나열 (레지스트리 구조 확인)
docker exec study-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    get /registry/ --prefix --keys-only
' | grep -c .

# 특정 종류만 (예: Pod)
... get /registry/pods --prefix --keys-only | grep -c .
```

**중요한 관점**: etcd는 **k8s의 유일한 진실 원천**이다. static pod로 관리되고,
데이터 디렉토리(`/var/lib/etcd`)가 사라지면 **클러스터가 통째로 사라진다**.
이것이 W12에서 스냅샷 백업을 배우는 이유다.

```bash
# 참고: W12에서 할 백업 (지금은 실행하지 않아도 된다)
# docker exec study-control-plane sh -c 'ETCDCTL_API=3 etcdctl \
#   --endpoints=... --cacert=... --cert=... --key=... \
#   snapshot save /var/lib/etcd-backup.db'
# docker cp study-control-plane:/var/lib/etcd-backup.db ./etcd-backup.db
```

</details>

---

# 유형 E. 서비스와 네트워크 트러블슈팅

> 00-setup의 `br_netfilter` / Service 통신 문제가 그대로 시험에 나온다.

## E-1. Pod는 통신되는데 Service만 안 될 때

**문제**
`netcheck-a` → `netcheck-b` **Pod IP** 직접 통신은 성공하지만, Service ClusterIP를 경유하면 실패한다. 원인을 **3가지** 가정하고 각각 확인하라.

<details><summary>풀이</summary>

**준비**

```bash
kubectl run netcheck-a --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --restart=Never --command -- /agnhost netexec --http-port=8080
kubectl run netcheck-b --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --restart=Never --command -- /agnhost netexec --http-port=8080
kubectl wait --for=condition=Ready pod/netcheck-a pod/netcheck-b --timeout=120s

kubectl expose pod netcheck-b --name=netsvc --port=8080
```

**기준 확인 — 여기가 진단의 출발점**

```bash
# Pod IP 직접: 성공한다
B_IP=$(kubectl get pod netcheck-b -o jsonpath='{.status.podIP}')
kubectl exec netcheck-a -- /agnhost connect --timeout=5s --protocol=tcp "$B_IP:8080"
echo "pod-to-pod rc=$?"

# Service 경유: 실패한다
kubectl exec netcheck-a -- /agnhost connect --timeout=5s --protocol=tcp netsvc:8080
echo "svc rc=$?"
```

**① Service의 selector가 Pod 라벨과 불일치 (가장 흔함)**

```bash
kubectl get svc netsvc -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pod netcheck-b --show-labels

# EndpointSlice 의 엔드포인트가 비어 있으면 selector 불일치다
kubectl get endpointslice -l kubernetes.io/service-name=netsvc
kubectl get endpoints netsvc
# ENDPOINTS 가 <none> 이면 → selector 문제
```

```bash
# 고장 내기 / 확인
kubectl patch svc netsvc -p '{"spec":{"selector":{"app":"wrong"}}}'
kubectl get endpoints netsvc        # <none>
```

**복구**: selector를 맞춘다.

```bash
kubectl patch svc netsvc -p '{"spec":{"selector":{"run":"netcheck-b"}}}'
kubectl get endpoints netsvc        # 172.x.x.x:8080
```

**② 포트 정의 오류 — `targetPort` vs `port`**

```bash
kubectl get svc netsvc -o yaml | sed -n '/ports:/,/selector/p'
# port: 8080       ← Service 가 노출하는 포트
# targetPort: 80   ← 컨테이너가 실제로 듣는 포트
# agnhost 는 8080 을 듣는다. targetPort 가 틀리면 연결이 거부된다.
```

```bash
kubectl patch svc netsvc -p '{"spec":{"ports":[{"port":8080,"targetPort":8080}]}}'
```

증상 차이: `targetPort`가 틀리면 **timeout 또는 connection refused**,
selector가 틀리면 **endpoint가 아예 없어서** 즉시 거부된다.

**③ kube-proxy 문제**

```bash
kubectl get pods -n kube-system -o wide | grep kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50

# 노드 안에서 iptables 규칙 확인
docker exec study-worker iptables -t nat -L KUBE-SERVICES -n | grep -A3 netsvc
docker exec study-worker iptables -t nat -L KUBE-SVC-<해시> -n

# kube-proxy 가 죽으면 새 Service 규칙이 반영되지 않는다 (기존 규칙은 남는다)
kubectl -n kube-system delete pod -l k8s-app=kube-proxy    # DaemonSet 이 재생성
```

> **00-setup과 연결**: 노드에서 `net.bridge.bridge-nf-call-iptables=0`이면
> bridge를 지나는 패킷이 iptables를 거치지 않아 **Pod→Service DNAT가 적용되지 않는다.**
> Pod→Pod는 성공하고 Service만 실패하는 **대표적 원인**이다.
> ```bash
> docker exec study-worker sysctl net.bridge.bridge-nf-call-iptables   # 1이어야 한다
> docker exec study-worker sysctl net.ipv4.ip_forward                  # 1이어야 한다
> ```

**④ CoreDNS 문제 (이름 해석 실패일 때)**

`netsvc:8080`처럼 **이름으로** 접속하는 경우, DNS가 원인이면 **Pod IP는 되고 Service만 안 되는** 동일 증상이 나온다.

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl exec netcheck-a -- cat /etc/resolv.conf      # nameserver 가 ClusterIP 인가

# Error 가 "DNS:" 로 시작하면 DNS 문제, "REFUSED"/"TIMEOUT" 이면 네트워크 문제
kubectl exec netcheck-a -- /agnhost connect --timeout=5s --protocol=tcp netsvc:8080
# DNS: ... / REFUSED / TIMEOUT  ← agnhost 가 원인을 분류해서 알려준다
```

**진단 요약표**

| 증상 | 원인 |
|---|---|
| `endpoints`가 `<none>` | selector 불일치, Pod가 Ready 아님 |
| endpoint는 있는데 거부 | `targetPort` 오류 |
| `DNS:` 에러 | CoreDNS |
| `TIMEOUT` + Pod→Pod 성공 | `br_netfilter`/`ip_forward`, kube-proxy iptables |
| 새 Service만 반영 안 됨 | kube-proxy 정지 |

**정리**

```bash
kubectl delete pod netcheck-a netcheck-b
kubectl delete svc netsvc
```

</details>

---

## E-2. DNS를 직접 확인하기

**문제**
클러스터 DNS가 동작하는지 **CoreDNS Pod 로그를 보지 않고** 검증하라. ① 짧은 이름, FQDN, ② Service, ③ 외부 도메인을 각각 확인하라.

<details><summary>풀이</summary>

```bash
# DNS 질의 도구가 있는 Pod 를 쓴다 (agnhost 에는 nslookup 이 없다)
kubectl run dnstest --image=registry.k8s.io/e2e-test-images/agnhost:2.66.1 \
  --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/dnstest --timeout=60s

# resolv.conf 확인 — 여기가 출발점
kubectl exec dnstest -- cat /etc/resolv.conf
# search default.svc.cluster.local svc.cluster.local cluster.local
# nameserver 10.96.0.10        ← CoreDNS Service ClusterIP
# options ndots:5

# dig 이 있는 이미지로 질의
kubectl run dnstest2 --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.7 \
  --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/dnstest2 --timeout=60s

# ① 짧은 이름 (같은 namespace — search 도메인이 붙는다)
kubectl exec dnstest2 -- nslookup netsvc
# ① FQDN
kubectl exec dnstest2 -- nslookup netsvc.default.svc.cluster.local
# ② kubernetes API Service
kubectl exec dnstest2 -- nslookup kubernetes.default.svc.cluster.local
# ③ 외부 (forwarding 확인)
kubectl exec dnstest2 -- nslookup github.com
```

**FQDN 규칙** — CKA에 이름 규칙 문제가 나온다:

```
<service>.<namespace>.svc.cluster.local
    │         │
    │         └─ 생략하면 현재 namespace
    └─ 생략하면 search 도메인 순서로 시도
```

| 접속 형태 | 실제 해석 |
|---|---|
| `netsvc` | `netsvc.<현재ns>.svc.cluster.local` |
| `netsvc.other` | `netsvc.other.svc.cluster.local` |
| `netsvc.other.svc` | `netsvc.other.svc.cluster.local` |
| `netsvc.other.svc.cluster.local.` | 그대로 (끝 점 = 절대 도메인) |

**정리**

```bash
kubectl delete pod dnstest dnstest2
```

</details>

---

# 유형 F. kubeadm 클러스터 (VM)

> 00-setup에서 만든 [`clusters/kubeadm`](../../clusters/kubeadm/) 자산이 그대로 시험 범위다.
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

---

# 유형 G. 스케줄링과 reconciliation

> 셀프 체크 5. CKA Workloads 도메인과 Troubleshooting의 교차점.

## G-1. 스케줄러가 결정하는 것 / kubelet이 결정하는 것

**문제**
Deployment `web`(replicas=2)을 만들고 다음을 관찰하라. ① Pod가 어디에 배치되는지 **누가** 결정하는가.
② Deployment를 `kubectl delete`하면 Pod는 왜 사라지는가.③ Pod만 `kubectl delete`하면 왜 다시 살아나는가.

<details><summary>풀이</summary>

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=2
kubectl get pods -o wide

# ① 스케줄러가 "노드 선택"을 담당한다 (Pod 를 만드는 건 아니다)
kubectl describe pod <pod> | grep -A5 'Events:'
#   Scheduled  → kube-scheduler 가 노드를 골라 API 서버에 binding 을 기록
#   Pulled / Created / Started → kubelet 이 그 노드에서 실제로 컨테이너를 만든다
```

```
사용자: replicas=2 를 원함
   ↓
kube-controller-manager (Deployment controller)
   → ReplicaSet 을 만들고, ReplicaSet controller 가 Pod 오브젝트를 생성 (nodeName 없음)
   ↓
kube-scheduler
   → 필터링(자원/taint/affinity) + 스코어링 → 노드 선택 → binding 기록
   ↓
kubelet (선택된 노드)
   → CRI 로 컨테이너 생성, 상태를 API 서버에 보고
```

**② Deployment 삭제 → Pod도 사라진다**

```bash
kubectl delete deployment web
kubectl get pods        # 없다
```

이유: **소유자 참조(ownerReferences)와 cascading deletion.**
Deployment → ReplicaSet → Pod의 소유 체인이 있고, 기본 삭제 정책(`propagationPolicy: Background`)이
자식까지 지운다.

```bash
# 삭제 정책 확인
kubectl get deployment web -o jsonpath='{.metadata.ownerReferences}'   # (삭제 후라면)
```

**③ Pod만 삭제 → 다시 살아난다**

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=2
kubectl get pods
kubectl delete pod <pod-1>
kubectl get pods -w
# 새 이름의 Pod 가 즉시 생성된다
```

이유: **ReplicaSet controller의 reconciliation loop.**
"원하는 replicas=2, 현재 1" → 차이를 감지하고 새 Pod 생성.
Pod는 ReplicaSet이 소유하므로 **ReplicaSet이 있는 한 개별 Pod 삭제는 복구된다.**

**정리 — reconciliation의 본질**

| 삭제 대상 | 결과 | 이유 |
|---|---|---|
| Pod 하나 | **다시 생긴다** | ReplicaSet이 2개를 원함 |
| ReplicaSet | Deployment가 다시 만든다 | Deployment가 RS를 원함 |
| Deployment | **사라진다** | "원함" 자체가 없어짐 |

→ **"지운다"가 아니라 "원하는 상태를 바꾼다"** 가 k8s의 사고방식이다.
`kubectl scale --replicas=0`은 "Pod를 지우는 명령"이 아니라 **"0개를 원한다"는 선언**이다.

**속도**: `kubectl delete pod`로 하나를 지울 때 `--wait=false`는 시험에서 시간을 아낀다.

</details>

---

## G-2. reconciliation 실패 진단

**문제**
Deployment `web`이 있어야 할 replicas 수만큼 뜨지 않는다. `kubectl get`만으로 부족할 때 **어느 순서로** 조사하는가?

<details><summary>풀이</summary>

**계층별로 내려간다. 각 계층에서 "원함 vs 현재"를 비교한다.**

```bash
# 0) 전체 상태
kubectl get deploy,rs,pod -o wide

# 1) Deployment 계층 — desired vs available
kubectl get deploy web
kubectl describe deploy web
#  Conditions / Events 에 ReplicaFailure 가 있으면 여기서 원인이 나온다
```

| Deployment 상태 | 의미 |
|---|---|
| `READY 1/3` | Pod는 3개인데 준비된 게 1개 → **Pod 문제(다음 계층)** |
| `READY 0/3` + `ReplicaFailure` | **Pod 생성 자체 실패** → quota, LimitRange, admission |

```bash
# 2) ReplicaSet 계층 — Pod 생성 실패 이유
kubectl get rs -l app=web
kubectl describe rs <rs-name>
#  Error creating: pods "web-xxx-" is forbidden: exceeded quota ...
#  Error creating: admission webhook denied ...
```

```bash
# 3) Pod 계층 — 왜 Ready 가 아닌가
kubectl get pods -l app=web
kubectl describe pod <pod>          # Conditions / Events
kubectl logs <pod>
kubectl logs <pod> --previous       # 재시작 직전 로그 ← 시험 핵심
```

```bash
# 4) 노드/스케줄러 계층 — Pending 이라면
kubectl get pods -o wide | grep Pending
kubectl describe pod <pending-pod> | tail -15
#  0/3 nodes are available: 3 Insufficient cpu.
#  0/3 nodes are available: 1 node(s) had untolerated taint {...}
#  0/3 nodes are available: 2 node(s) didn't match Pod's node affinity
```

```bash
# 5) 클러스터 차원 — 이벤트와 리소스
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe node <node> | sed -n '/Allocated resources/,/Events/p'
kubectl get resourcequota,limitrange -A         # 03 범위
```

**계층별 원인 요약**

| 계층 | 대표 원인 | 결정적 명령 |
|---|---|---|
| Deployment | 잘못된 selector/strategy, quota | `describe deploy` |
| ReplicaSet | admission 거부, quota | `describe rs` |
| Pod | 이미지, command, probe, 볼륨 | `describe pod`, `logs --previous` |
| 스케줄러 | 자원, taint, affinity | `describe pod`의 Events |
| 노드 | NotReady, DiskPressure | `describe node` Conditions |

**시험 포인트**: "**어디까지 정상인지**"를 먼저 특정한다.
- Pod가 아예 안 만들어짐 → Deployment/RS 계층
- Pod가 Pending → 스케줄러 계층
- Pod가 Running인데 Ready 아님 → **probe** 계층
- Pod가 CrashLoopBackOff → 애플리케이션 계층 (`--previous`)

각각 다른 명령이 필요하다. **이 구분만 익혀도 트러블슈팅 점수의 절반이다.**

</details>

---

## G-3. 자원 요청과 스케줄링

**문제**
노드의 가용 자원보다 큰 `requests`를 가진 Pod를 만들어라. ① 무슨 일이 일어나는지 관찰하고,
② `requests`만 낮춰서 스케줄되게 하라. ③ `requests`와 `limits`의 차이를 스케줄링 관점에서 설명하라.

<details><summary>풀이</summary>

```bash
# ① 노드 용량 확인
kubectl describe node study-worker | sed -n '/Capacity/,/Allocatable/p'
kubectl describe node study-worker | sed -n '/Allocated resources/,/Events/p'

# 터무니없이 큰 requests
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: toobig
spec:
  containers:
    - name: c
      image: nginx:1.27
      resources:
        requests:
          cpu: "64"
          memory: 128Gi
EOF

kubectl get pod toobig -o wide       # Pending, NODE <none>
kubectl describe pod toobig | tail -10
#  0/3 nodes are available: 3 Insufficient cpu, 3 Insufficient memory.
```

**② requests를 낮춰 재생성**

```bash
kubectl delete pod toobig
kubectl run ok --image=nginx:1.27 --overrides='
{"spec":{"containers":[{"name":"ok","image":"nginx:1.27",
 "resources":{"requests":{"cpu":"100m","memory":"64Mi"},
              "limits":{"cpu":"500m","memory":"128Mi"}}}]}}'
kubectl get pod ok -o wide           # 스케줄됨
```

**YAML로 제대로 쓰기 (시험에서는 이 방식을 쓴다)**

```bash
kubectl get pod ok -o yaml | sed -n '/resources:/,/^      [a-z]/p'
```

**③ requests vs limits — 스케줄링 관점**

| | requests | limits |
|---|---|---|
| 의미 | **보장받는 최소량** | **허용되는 최대량** |
| 스케줄러 | **이 값으로 노드를 고른다** | 스케줄링에 **쓰이지 않는다** |
| 초과 시 | (해당 없음) | CPU: throttle / Memory: **OOMKill** |
| QoS | requests==limits → Guaranteed | requests<limits → Burstable, 없으면 BestEffort |

**핵심**: 스케줄러는 `requests`의 **합계**만 본다. 노드에 실제로 64 CPU가 있어도
다른 Pod가 이미 requests를 예약했다면 `Allocated resources`가 꽉 차서 Pending이 된다.
**`limits`를 아무리 낮춰도 스케줄링 결과는 바뀌지 않는다.**

```bash
# 노드의 예약량 확인 — 스케줄러가 보는 값
kubectl describe node study-worker | grep -A8 'Allocated resources'
```

**시험 포인트**
- "노드에 자원 여유가 있는가" → `Allocated resources`(예약량)와 `Capacity`(실제)를 구분한다.
- `metrics-server`가 있으면 `kubectl top node`가 **실제 사용량**을 준다. 둘은 다른 값이다.
- QoS class는 축출(eviction) 순서에 영향을 준다: **BestEffort → Burstable → Guaranteed** 순으로 먼저 죽는다.

**정리**

```bash
kubectl delete pod toobig ok --ignore-not-found
```

</details>

---

# 유형 H. (미리보기) RBAC와 kubeconfig

> 00-setup에서 배운 **kubeconfig 구조(cluster/user/context)** 가 RBAC로 이어진다.
> 공식 도메인 "Cluster Architecture (25%)"에 포함되지만 자세한 내용은 **03-operations 범위**다.
> 여기서는 00-setup 지식만으로 풀 수 있는 연결 문제 하나만 둔다.

## H-1. 새 사용자용 kubeconfig 만들기

**문제**
사용자 `dev-kim`이 namespace `dev`에서만 Pod를 조회할 수 있게 하라.
① kubeconfig 파일을 `/tmp/dev-kim.kubeconfig`로 생성하고, ② 그 파일로 권한을 검증하라.

<details><summary>풀이 (개념 위주)</summary>

```bash
# 1) 네임스페이스와 Role/RoleBinding
kubectl create namespace dev

kubectl create role pod-reader -n dev \
  --verb=get,list,watch --resource=pods

kubectl create rolebinding dev-kim-pod-reader -n dev \
  --role=pod-reader --user=dev-kim

# 2) 인증서 발급 (kubeadm 환경)
sudo kubeadm kubeconfig user --client-name=dev-kim --org=dev-team \
  --config /root/kubeadm-config.yaml > /tmp/dev-kim.kubeconfig
# → 인증서가 함께 생성된다. 실제 사용은 `kubeadm kubeconfig user` 로 한다.
```

```bash
# 3) 검증 — "누구로" 무엇을 할 수 있는가
kubectl auth can-i list pods -n dev --as=dev-kim
# yes
kubectl auth can-i list pods -n default --as=dev-kim
# no
kubectl auth can-i --list -n dev --as=dev-kim

# 4) 그 kubeconfig 로 실제 요청
KUBECONFIG=/tmp/dev-kim.kubeconfig kubectl get pods -n dev
KUBECONFIG=/tmp/dev-kim.kubeconfig kubectl get pods -n default   # Forbidden
```

**kubeconfig 구조와의 연결**

```yaml
users:
  - name: dev-kim
    user:
      client-certificate: ...      # ← 인증서의 CN=dev-kim, O=dev-team
contexts:
  - name: dev-kim@kubernetes
    context:
      cluster: kubernetes          # ← "어디로"
      user: dev-kim                # ← "누구로"
      namespace: dev               # ← 기본 namespace
```

**인증(authentication) vs 인가(authorization)**

| 단계 | 질문 | 담당 |
|---|---|---|
| 인증 | **너는 누구인가** | 인증서의 CN/O, 토큰, ServiceAccount |
| 인가 | **무엇을 할 수 있는가** | RBAC (Role/RoleBinding/ClusterRole) |

`Role`+`RoleBinding` = namespace 범위, `ClusterRole`+`ClusterRoleBinding` = 클러스터 범위.
**이 구분이 03-operations와 CKA 보안 문제의 핵심이다.**

**정리**

```bash
kubectl delete rolebinding dev-kim-pod-reader -n dev
kubectl delete role pod-reader -n dev
kubectl delete namespace dev
rm -f /tmp/dev-kim.kubeconfig
```

</details>

---

# 속도 훈련 (Drill)

> CKA는 **지식보다 속도**에서 갈린다. 아래를 5분 안에 무작위로 처리할 수 있게 반복한다.

## Drill 1 — 즉시 답해야 하는 명령 (각 10초)

```bash
# 1. 현재 컨텍스트 이름
kubectl config current-context

# 2. 모든 namespace 의 Pod를 노드까지 보기
kubectl get pods -A -o wide

# 3. 재시작 직전 로그
kubectl logs <pod> --previous

# 4. Pod 를 만들지 않고 YAML 만 출력
kubectl run x --image=nginx:1.27 $do

# 5. Deployment 를 만들지 않고 YAML 만 출력
kubectl create deploy x --image=nginx:1.27 --replicas=3 $do

# 6. 필드 문서 보기 (검색하지 않는다)
kubectl explain pod.spec.containers.livenessProbe
kubectl explain deploy.spec.strategy --recursive

# 7. 모든 리소스 종류와 short name
kubectl api-resources | grep -iE 'pod|deploy|svc|ep'

# 8. 이벤트 최신순
kubectl get events -A --sort-by=.lastTimestamp | tail -20

# 9. 노드의 예약량
kubectl describe node <node> | sed -n '/Allocated resources/,/Events/p'

# 10. 내가(또는 특정 사용자가) 할 수 있는 것 전부
kubectl auth can-i --list
kubectl auth can-i get pods --as=dev-kim -n dev
```

## Drill 2 — YAML 없이 오브젝트 만들기 (2분)

```bash
kubectl create ns drill
kubectl -n drill create deploy web --image=nginx:1.27 --replicas=3
kubectl -n drill expose deploy web --port=80 --target-port=80 --type=ClusterIP
kubectl -n drill set image deploy/web nginx=nginx:1.28
kubectl -n drill rollout status deploy/web
kubectl -n drill rollout history deploy/web
kubectl -n drill rollout undo deploy/web
kubectl -n drill scale deploy/web --replicas=1
kubectl -n drill delete ns drill --wait=false
```

## Drill 3 — 고장 내고 5분 안에 복구

```bash
# 매번 클러스터를 초기화하고 시작한다
kind delete cluster --name study
kind create cluster --config clusters/kind/study-cluster.yaml

# 무작위로 하나를 골라 실행 (결과를 미리 보지 않는다)
docker exec study-control-plane mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/          # A
docker exec study-worker systemctl stop kubelet                                                # B
kubectl patch svc <svc> -p '{"spec":{"selector":{"app":"none"}}}'                              # C
kubectl create quota q --hard=requests.cpu=100m -n default && \
  kubectl create deploy big --image=nginx:1.27 --replicas=3 -n default                         # D
```

**자가 점검**: 각 경우에 ① 어떤 명령으로 진단했는가 ② 몇 분 걸렸는가.
B는 `kubectl`로 원인을 알 수 없고 **노드에 들어가야** 한다는 점이 핵심이다.

---

# 시험장 명령 치트시트 (00-setup 범위)

```bash
# ---- 환경 ----
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)      # 시험 셸은 보통 bash

# ---- 컨텍스트 (가장 먼저!) ----
kubectl config get-contexts
kubectl config use-context <ctx>
kubectl config set-context --current --namespace=<ns>
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}'

# ---- 조회 ----
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe node <node> | sed -n '/Conditions/,/Addresses/p'
kubectl describe node <node> | sed -n '/Allocated resources/,/Events/p'

# ---- 컴포넌트 (static pod) ----
ls /etc/kubernetes/manifests/                      # 노드 안
crictl ps -a ; crictl logs <id>                    # 노드 안
journalctl -u kubelet -n 100 --no-pager            # 노드 안
systemctl status kubelet containerd                # 노드 안
crictl info                                        # CRI 상태
crictl images | grep pause                         # sandbox 이미지

# ---- 컨트롤 플레인 상태 (kubectl 이 살아있을 때) ----
kubectl get --raw /healthz
kubectl get --raw '/readyz?verbose'
kubectl -n kube-system logs kube-apiserver-<node>
kubectl get --raw "/api/v1/nodes/<node>/proxy/logs/?query=kubelet"

# ---- 로그 ----
kubectl logs <pod> -f
kubectl logs <pod> --previous
kubectl logs -l app=web --all-containers --tail=50
kubectl logs <pod> -c <container>

# ---- 필드 탐색 (검색 대신 이걸 쓴다) ----
kubectl explain pod.spec
kubectl explain deploy.spec.strategy --recursive
kubectl api-resources
kubectl api-versions

# ---- 클러스터 수명주기 ----
kubeadm token create --print-join-command
kubeadm token list
kubeadm certs check-expiration
kubeadm upgrade plan
kubeadm reset -f
kubectl drain <node> --delete-emptydir-data --force --ignore-daemonsets
kubectl uncordon <node>
```

**시간 배분 (2시간 / 약 15~20문제)**

| 단계 | 시간 |
|---|---|
| 모든 문제 지문을 한 번 훑고 쉬운 것부터 | 5분 |
| 문제당 평균 | **6분** |
| 어려운 문제는 표시하고 넘어감 | — |
| 마지막 검증 (context·namespace·파일 경로 재확인) | 10분 |

---

# 자가 채점표

풀고 나서 기록한다. **2회차에 걸린 시간이 줄었는지**가 실력이다.

| 문제 | 1회차 | 2회차 | 약점 메모 |
|---|---|---|---|
| A-1 컨텍스트 정보 추출 | | | `--minify` 습관 |
| A-2 kubeconfig 복구 | | | |
| B-1 static pod 경로 | | | mirror pod 삭제 불가 |
| B-2 static pod 추가 | | | 파일 기반 생성 |
| C-1 NotReady 5원인 | | | 원인 구분 |
| C-2 컴포넌트 로그 | | | |
| C-3 ContainerCreating | | | |
| C-4 리소스 모니터링 | | | |
| D-1 스케줄러 정지 | | | |
| D-2 API 서버 복구 | | | kubectl 없는 진단 |
| D-3 etcd 확인 | | | |
| E-1 Service 장애 | | | endpoints |
| E-2 DNS 확인 | | | FQDN 규칙 |
| F-1 노드 사전 준비 | | | |
| F-2 kubeadm 구축 | | | 40분 목표 |
| F-3 CRI/CNI/CSI | | | |
| F-4 업그레이드 순서 | | | |
| G-1 reconciliation | | | |
| G-2 계층별 진단 | | | |
| G-3 requests/limits | | | |
| H-1 RBAC/kubeconfig | | | 03 범위 |

**다음 단계 예고**

| 아직 못 푸는 것 | 어디서 배우나 |
|---|---|
| PVC/PV, StorageClass, CSI | 02-networking-storage |
| Ingress, NetworkPolicy, Gateway API | 02-networking-storage |
| Helm, Kustomize, 오퍼레이터 | 03-operations |
| RBAC 심화, ServiceAccount, 보안 | 03-operations |
| etcd 스냅샷 복구, 업그레이드 실행 | 04-onprem-cka W12 |
| HA 컨트롤 플레인, 인증서 갱신 | 04-onprem-cka W12 |

---

## 참고

- [CKA Curriculum (CNCF)](https://github.com/cncf/curriculum) — 비중은 개정되므로 응시 전 확인
- [Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [Cluster Troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Verify node health / Node status](https://kubernetes.io/docs/reference/node/node-status/)
- 노드 사전 준비 근거: [`notes/kubeadm-setup.md`](../notes/kubeadm-setup.md)
