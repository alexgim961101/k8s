# 유형 D. 클러스터 컴포넌트 장애

> [← 유형 C. 노드 장애 진단](03-node-troubleshooting.md) · [▶ 유형 E. 서비스와 네트워크](05-service-dns-troubleshooting.md) · [목록](README.md)

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
