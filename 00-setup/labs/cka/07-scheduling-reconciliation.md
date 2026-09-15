# 유형 G. 스케줄링과 reconciliation

> [← 유형 F. kubeadm 클러스터 (VM)](06-kubeadm-cluster.md) · [▶ 유형 H. (미리보기) RBAC](08-rbac-preview.md) · [목록](README.md)

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
