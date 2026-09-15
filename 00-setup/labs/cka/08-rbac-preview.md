# 유형 H. (미리보기) RBAC

> [← 유형 G. 스케줄링과 reconciliation](07-scheduling-reconciliation.md) · [▶ 속도 훈련 (Drill)](09-speed-drills.md) · [목록](README.md)

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
