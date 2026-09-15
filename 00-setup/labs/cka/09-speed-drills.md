# 속도 훈련 (Drill)

> [← 유형 H. (미리보기) RBAC](08-rbac-preview.md) · [▶ 시험장 명령 치트시트](10-cheatsheet.md) · [목록](README.md)

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
