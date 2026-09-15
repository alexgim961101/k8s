# 시험장 명령 치트시트

> [← 속도 훈련 (Drill)](09-speed-drills.md) · [▶ 자가 채점표](11-scoring.md) · [목록](README.md)

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
