# 유형 B. static pod와 컨트롤 플레인

> [← 유형 A. kubeconfig와 context](01-kubeconfig-context.md) · [▶ 유형 C. 노드 장애 진단](03-node-troubleshooting.md) · [목록](README.md)

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
