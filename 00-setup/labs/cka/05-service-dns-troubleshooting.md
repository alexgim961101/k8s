# 유형 E. 서비스와 네트워크

> [← 유형 D. 클러스터 컴포넌트 장애](04-control-plane-troubleshooting.md) · [▶ 유형 F. kubeadm 클러스터 (VM)](06-kubeadm-cluster.md) · [목록](README.md)

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
