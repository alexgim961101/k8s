# 유형 A. kubeconfig와 context

> [▶ 유형 B. static pod와 컨트롤 플레인](02-static-pods.md) · [목록](README.md)

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
