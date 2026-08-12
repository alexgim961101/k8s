# 00. Setup — 준비와 첫 클러스터

**주차**: W1 / **시간**: 약 10시간 (2시간 × 5세션)

## 목표

멀티노드 로컬 클러스터를 언제든 5분 안에 만들고 부술 수 있게 되고, Kubernetes가 "명령"이 아니라
"원하는 상태"로 동작한다는 사고 모델을 잡는다. 이후 모든 단계의 실습 기반이 된다.

## 이론

- [ ] 컨테이너 복습: 이미지 레이어, `ENTRYPOINT` vs `CMD`, 네트워크/볼륨, namespace/cgroup으로 격리되는 원리
- [ ] docker-compose의 한계: 다중 호스트, 자가 치유, 롤링 배포, 서비스 디스커버리
- [ ] 컨트롤 플레인 구성: API Server, etcd, Scheduler, Controller Manager — 각각이 죽으면 무엇이 멈추는가
- [ ] 노드 구성: kubelet, kube-proxy, 컨테이너 런타임(containerd)
- [ ] **핵심 사고 모델**: 선언적 상태 + reconciliation loop. 컨트롤러가 현재 상태를 원하는 상태로 수렴시킨다
- [ ] 로컬 클러스터 도구 비교: kind / minikube / k3d — 이 저장소가 kind를 주력으로 쓰는 이유
- [ ] kubeconfig 구조: cluster(어디로) / user(누구로) / context(그 둘의 조합)

## 실습 (labs/)

### 세션 1 — 환경 구축과 첫 클러스터

[`notes/setup.md`](notes/setup.md) 를 따라 도구를 설치한 뒤:

```bash
kind create cluster --config ../clusters/kind/study-cluster.yaml
kubectl get nodes -o wide
```

노드 3개가 `Ready` 가 되면 성공. **여기서 멈추고 확인할 것** — kind가 무엇을 만들었나?

```bash
docker ps                                        # 노드가 사실은 컨테이너다
docker exec -it study-control-plane crictl ps    # 그 안에서 컨테이너가 또 돌고 있다
```

kind의 노드는 **kubeadm으로 구성된 컨테이너**다. [04-onprem-cka](../04-onprem-cka/)에서 VM 위에
직접 kubeadm으로 클러스터를 세울 때 지금 본 구조가 그대로 반복된다.

### 세션 2 — 클러스터 해부

```bash
kubectl get pods -n kube-system -o wide
docker exec study-control-plane ls /etc/kubernetes/manifests/
```

`/etc/kubernetes/manifests/` 의 YAML이 **static pod** 다. kubelet이 API 서버 없이도 이 파일들을
읽어 컨트롤 플레인을 띄운다 — "닭과 달걀" 문제의 해법이다.

컴포넌트를 하나씩 멈춰보며 아래 표를 직접 채운다.

| 컴포넌트 | 역할 | 죽으면? |
|---|---|---|
| kube-apiserver | | |
| etcd | | |
| kube-scheduler | | |
| kube-controller-manager | | |
| kubelet | | |
| kube-proxy | | |

### 세션 3 — kubectl 기본기

속도가 나중에 CKA 점수가 된다.

```bash
kubectl get pods -A -o wide
kubectl describe node study-worker
kubectl logs <pod> -f
kubectl logs <pod> --previous       # 재시작 전 로그 — 장애 분석의 핵심
kubectl exec -it <pod> -- sh
kubectl api-resources               # 이 클러스터가 아는 리소스 전체
kubectl explain pod.spec.containers  # 문서를 검색하지 않고 필드를 찾는 법
kubectl config get-contexts
```

셸 설정 — 지금 해두면 16주 내내 이득이다.

```bash
echo 'alias k=kubectl' >> ~/.zshrc
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
echo 'complete -F __start_kubectl k' >> ~/.zshrc
```

`k9s` 도 띄워본다. 탐색은 k9s가 빠르지만 **시험과 자동화는 kubectl이므로 kubectl을 주로 쓴다**.

### 세션 4 — 관통 프로젝트 첫 배포

[`app/README.md`](../app/README.md) 에서 관통 프로젝트를 정하고 컨테이너화한다.

```bash
docker build -t study-api:0.1.0 .
kind load docker-image study-api:0.1.0 --name study   # kind는 호스트 이미지를 자동으로 보지 못한다
kubectl run api --image=study-api:0.1.0 --port=3000
kubectl port-forward pod/api 3000:3000
```

> **이미지 태그에 `latest` 를 쓰지 않는다.** `imagePullPolicy` 기본값이 태그에 따라 달라져
> 갱신이 안 되는 혼란을 겪는다. [03-operations](../03-operations/)에서 정책으로 아예 금지시킬 것이다.

### 세션 5 — 반복 훈련

**클러스터를 5회 부수고 다시 만든다.**

```bash
kind delete cluster --name study
kind create cluster --config ../clusters/kind/study-cluster.yaml
```

"부숴도 5분이면 돌아온다"는 확신이 있어야 이후 단계에서 과감하게 실험할 수 있다.

## 완료 기준

- [ ] 빈 상태에서 멀티노드 클러스터를 5분 안에 재구축하고 앱 Pod 1개에 접속
- [ ] 컨트롤 플레인 컴포넌트 표를 직접 채우고, 최소 2개는 실제로 멈춰서 확인
- [ ] `kubectl explain` 으로 필드를 찾아내는 습관 형성
- [ ] kind 노드가 컨테이너이고 그 안이 kubeadm 구성임을 직접 확인
- [ ] `notes/` 에 이론 정리 작성

## 셀프 체크

1. kind가 만든 "노드"는 실제로 무엇인가? VM 기반 클러스터와 무엇이 같고 무엇이 다른가?
2. API 서버가 아직 없는 상태에서 컨트롤 플레인 컴포넌트들은 어떻게 처음 뜨는가?
3. kube-scheduler를 멈추면 **기존 Pod**와 **새로 만든 Pod**에 각각 무슨 일이 일어나는가?
4. kubeconfig의 cluster / user / context는 각각 무엇을 가리키며 어떻게 묶이는가?
5. "선언적"이라는 말을 reconciliation loop를 써서 설명할 수 있는가? `kubectl delete` 로 지운 Deployment의 Pod는 왜 다시 살아나지 않고, `kubectl delete pod` 로 지운 Pod는 왜 다시 살아나는가?
