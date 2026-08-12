# Kubernetes 학습 커리큘럼 (로컬 → 온프렘 → EKS → SRE)

> 작성일: 2026-08-12
> 대상: 컨테이너/IaC 실무 경험은 있으나 Kubernetes는 입문 단계인 엔지니어
> 총 기간: 16주 (주 10시간 내외, 총 약 160시간)
> 최종 목표: 실무 운영 역량 확보 + CKA 취득

---

## 0. 커리큘럼 설계 전제

### 학습 환경 — 두 대의 머신을 오간다

| 항목 | 머신 A (확인됨) | 머신 B (미확인) |
|---|---|---|
| 위치 | 작업용 | 집 |
| OS / 아키텍처 | Ubuntu 24.04 LTS / **x86_64** | macOS / **arm64 (M4)** |
| 하드웨어 | 24 core / 31GB RAM | Mac mini M4 |
| 가상화 | KVM 가속 가능(`/dev/kvm` 확인) | Hypervisor.framework |
| 설치됨 | `docker`, `podman`, `kubectl` v1.36.1(kustomize v5.8.1 내장), `minikube` v1.33.1, `terraform`, `ansible`, `docker buildx` v0.35.0, `snap` | — |
| 미설치 | `kind`, `helm`, `k9s`, `stern`, `kubectx`, `multipass` | — |

**기존 자산 (머신 A)**: Terraform IaC (modules/environments 구조, S3+DynamoDB 백엔드), Ansible, Bitbucket Pipelines, docker-compose 기반 다수 서비스, nginx, MongoDB, 모니터링 스택

### 크로스 플랫폼 원칙

두 머신에서 **동일한 절차로 실습**할 수 있도록 도구를 선택했다.

- **W1~W10**: kind가 Docker 위에서 동작하고 `kindest/node` 는 arm64 멀티아키 이미지를 제공하므로 아키텍처를 신경 쓸 필요가 없다. 주요 에코시스템(Calico, Cilium, MetalLB, ingress-nginx, cert-manager, Argo CD, kube-prometheus-stack, Longhorn)도 모두 arm64를 지원한다.
- **W11~W12**: VM이 필요한 유일한 구간. **Multipass**를 쓴다 — Ubuntu(KVM)와 macOS(Apple Silicon 네이티브)를 모두 1급 지원하고 VM 생성 명령이 동일하다.
  - Vagrant + libvirt, VirtualBox는 Apple Silicon에서 사용 불가하므로 배제
  - LXD는 시스템 컨테이너라 kubeadm 구동에 우회 설정이 붙어 학습에 노이즈가 됨
- **컨테이너 런타임**: 머신 A는 Docker Engine, 머신 B는 OrbStack 또는 Colima 권장 (M4에서 Docker Desktop보다 가볍고 kind와 잘 맞음)
- **앱 이미지**: 두 머신이 이미지를 공유하려면 `docker buildx build --platform linux/amd64,linux/arm64` 로 멀티아키 빌드. 각 머신에서 로컬 빌드만 해도 무방
- **작업물 동기화**: 매니페스트/차트/노트는 Git으로 관리해 두 머신에서 이어서 작업한다

> ⚠️ 드물게 arm64 이미지를 제공하지 않는 서드파티 차트를 만날 수 있다. 그때는 대체 도구를 쓰거나 해당 실습만 머신 A에서 진행한다. (에뮬레이션은 느려서 권하지 않음)

### 설계 가정
- 컨테이너 이미지 빌드, 리눅스 운영, CI 파이프라인, AWS는 이미 익숙하다고 가정하고 **해당 내용은 복습 수준으로만** 다룬다.
- Kubernetes 오브젝트/네트워킹/스토리지는 **처음부터** 다룬다.
- 실습 환경은 로컬 단독으로 Phase 4까지 완결 가능하다. Phase 5(EKS)만 AWS 비용이 발생한다.

### 진행 원칙
1. **매주 반드시 손으로 만든다.** 읽기만 한 주차는 완료로 치지 않는다.
2. **일부러 고장 낸다.** 각 주차 체크포인트의 절반은 "장애를 재현하고 진단하기"다.
3. **관통 프로젝트 하나를 16주 내내 발전시킨다.** (§1 참조) 매주 새 예제를 만들지 않는다.
4. **주차 마지막 30분은 회고 기록.** `notes/WNN.md` 에 배운 것/막힌 것/미해결을 남긴다.
5. **공식 문서가 1순위 교재다.** kubernetes.io/docs 를 검색이 아니라 목차로 읽는 습관을 들인다.

---

## 1. 관통 프로젝트: 미니 서비스 플랫폼

16주 동안 하나의 서비스를 계속 진화시킨다. 기존에 다루던 스택과 최대한 비슷하게 잡아 실무 전이를 극대화한다.

**구성**
```
[외부] → Ingress/Gateway → api (Node/NestJS, stateless, 2+ replicas)
                              ├→ cache (Redis, 단일)
                              └→ db    (MongoDB, StatefulSet + PVC)
         + worker (Job/CronJob으로 배치 처리)
```

**주차별 진화 경로**
| 시점 | 상태 |
|---|---|
| W1 | 로컬에서 컨테이너 이미지로 빌드만 된 상태 |
| W4 | 스케줄링 제약까지 반영해 멀티노드에 분산 배포 |
| W7 | 데이터 영속성 + 설정/시크릿 분리 완료 |
| W8 | Helm 차트로 패키징, dev/prod 오버레이 분리 |
| W10 | 최소 권한 RBAC + NetworkPolicy + 보안 컨텍스트 적용 |
| W12 | 자체 구축한 온프렘 kubeadm 클러스터에서 운영 |
| W14 | Argo CD GitOps로 EKS에 자동 배포 |
| W16 | SLO 정의 + 오토스케일 + 런북까지 갖춘 "운영 가능한" 서비스 |

> 기존 프로젝트(`nestjs_test`, `my-todo-list` 등) 중 하나를 골라 시작해도 되고, 새로 최소 API를 만들어도 된다. 중요한 건 **16주 내내 같은 것을 쓰는 것**이다.

---

## Phase 0 — 준비와 첫 클러스터 (W1 · 10h)

### W1. 왜 오케스트레이터인가 / 첫 클러스터
**배울 것**
- 컨테이너 복습: 이미지 레이어, `ENTRYPOINT` vs `CMD`, 네트워크/볼륨, 왜 컨테이너가 격리되는가(namespace/cgroup 개요)
- docker-compose의 한계: 다중 호스트, 자가 치유, 롤링 배포, 서비스 디스커버리
- Kubernetes 조감도: 컨트롤 플레인(API Server / etcd / Scheduler / Controller Manager)과 노드(kubelet / kube-proxy / 컨테이너 런타임)
- **핵심 사고 모델**: 선언적 상태 + reconciliation loop. "명령"이 아니라 "원하는 상태"를 기록하면 컨트롤러가 수렴시킨다
- 로컬 클러스터 도구 비교: kind / minikube / k3d — 왜 이 커리큘럼은 **kind를 주력**으로 쓰는가
  - 멀티노드 클러스터를 수십 초 만에 만들고 부순다 → 반복 학습에 유리
  - kind의 노드 = kubeadm으로 구성된 컨테이너 → W11의 온프렘 kubeadm 실습과 개념이 그대로 이어진다
  - minikube는 addon 체험용으로만 병행

**실습**
- `kind`, `helm`, `k9s`, `stern` 설치 (kustomize는 kubectl 내장 사용). 머신 B는 컨테이너 런타임(OrbStack/Colima)부터 설치
- **두 머신에 동일하게 설치하고, 설치 절차를 `notes/setup.md` 에 기록** — 이후 어느 쪽에서든 이어서 실습
- kind로 control-plane 1 + worker 2 멀티노드 클러스터 생성 → 삭제 → 재생성 (5회 반복)
- `kubectl` 기본기: `get / describe / logs / exec / apply / delete / explain`, `-o wide|yaml|json`
- kubeconfig 구조 해부: cluster / user / context, `kubectl config use-context`
- 관통 프로젝트 앱 컨테이너화 + `kind load docker-image` 로 클러스터에 이미지 주입

**체크포인트**
- [ ] 빈 상태에서 멀티노드 클러스터를 5분 안에 재구축하고 앱 Pod 1개에 접속
- [ ] 컨트롤 플레인 4개 컴포넌트의 역할을 한 문장씩으로 설명
- [ ] `kubectl explain pod.spec.containers` 로 필드를 찾아내는 습관 형성

---

## Phase 1 — 핵심 오브젝트 (W2~W4 · 30h)

### W2. Pod의 해부
**배울 것**
- Pod가 최소 배포 단위인 이유(공유 네트워크 네임스페이스, 공유 볼륨), pause 컨테이너
- 멀티 컨테이너 패턴: 사이드카 / 앰배서더 / 어댑터, initContainer, 네이티브 사이드카(`initContainers` + `restartPolicy: Always`, 사용 전 클러스터 버전 확인)
- 리소스 모델: `requests` vs `limits`, CPU throttling과 메모리 OOMKill의 차이, QoS 클래스(Guaranteed/Burstable/BestEffort)
- 헬스체크 3종: liveness / readiness / startup — **각각을 잘못 쓰면 어떤 장애가 나는가**
- 라벨 / 셀렉터 / 애노테이션, 네임스페이스로 자원 구분
- 명령형(`kubectl run/create`) vs 선언형(`apply`) — 실무는 선언형, 시험은 명령형 속도

**실습**
- 앱을 Pod 단독 → Deployment로 승격
- probe 3종 부착 후 각각 실패시켜 동작 차이 관찰
- `limits.memory`를 낮게 잡아 OOMKill 재현, CPU limit으로 throttling 재현
- initContainer로 DB 준비 대기 구현

**체크포인트**
- [ ] `CrashLoopBackOff` / `OOMKilled` / liveness 실패 / `ImagePullBackOff` 를 각각 의도적으로 재현
- [ ] 위 4개를 `kubectl describe` + `logs --previous` 만으로 원인 지목
- [ ] readiness probe가 없을 때 롤링 업데이트 중 에러가 나는 것을 직접 관찰

### W3. 워크로드 컨트롤러
**배울 것**
- ReplicaSet과 Deployment의 관계, 리비전 히스토리
- 배포 전략: `RollingUpdate` (`maxSurge` / `maxUnavailable`), `Recreate`, `rollout status/undo/pause/resume`
- DaemonSet: 노드마다 하나(로그 수집기, 노드 익스포터)
- StatefulSet: 안정적 네트워크 ID, 순차 생성/삭제, `volumeClaimTemplates`, Headless Service — **Deployment로 DB를 돌리면 안 되는 이유**
- Job / CronJob: 완료 보장, 병렬성, `backoffLimit`, 실패 처리, 동시성 정책

**실습**
- 부하를 주며 롤링 업데이트를 수행하고 에러율 관찰
- 고장난 이미지로 배포 → `rollout undo` 로 복구
- MongoDB를 StatefulSet으로 전환, Pod 이름/DNS가 고정되는 것 확인
- 배치 작업을 CronJob으로 전환, 실패 시 재시도 동작 확인

**체크포인트**
- [ ] 롤링 업데이트 중 실패 요청 0건 달성 (readiness + graceful shutdown 조합)
- [ ] StatefulSet Pod를 삭제해도 같은 이름/같은 볼륨으로 복귀하는 것 확인
- [ ] Deployment / StatefulSet / DaemonSet / Job 을 각각 언제 쓰는지 표로 정리

### W4. 스케줄링과 배치 제어
**배울 것**
- 스케줄러 동작 2단계: 필터링(Predicates) → 스코어링(Priorities)
- `nodeSelector`, `nodeAffinity`(required/preferred), `podAffinity` / `podAntiAffinity`
- `taints` / `tolerations` — 노드를 격리하고 특정 워크로드만 허용
- `topologySpreadConstraints` 로 AZ/노드 균등 분산
- `PriorityClass` 와 preemption, 노드 압박 시 eviction 순서
- 노드 관리: `cordon` / `drain` / `uncordon`
- 정적 Pod(static pod)와 컨트롤 플레인이 뜨는 방식 (W11 복선)

**실습**
- 노드에 라벨을 붙여 특정 워크로드 고정
- anti-affinity로 api replica를 서로 다른 노드에 강제 분산
- taint를 걸어 "DB 전용 노드" 구성
- 노드 1개 `drain` 후 워크로드 이동 관찰

**체크포인트**
- [ ] 노드 1대를 drain 해도 서비스 무중단 (PDB는 W15에서 완성)
- [ ] Pending 상태 Pod의 원인을 `describe` 이벤트만으로 3종 이상 구분 (리소스 부족 / 셀렉터 불일치 / taint)

---

## Phase 2 — 네트워킹 · 스토리지 · 설정 (W5~W7 · 30h)

### W5. 서비스와 클러스터 네트워킹
**배울 것**
- Kubernetes 네트워크 모델의 3원칙 (NAT 없이 모든 Pod가 서로 통신 가능)
- CNI가 하는 일 (구현체 심화는 W11)
- Service 4종: ClusterIP / NodePort / LoadBalancer / ExternalName + Headless
- Service가 실제로 동작하는 원리: Endpoints / EndpointSlice, kube-proxy 모드(iptables / IPVS / nftables)
- CoreDNS와 서비스 디스커버리: `svc.ns.svc.cluster.local` 규칙, Pod DNS 정책
- 세션 어피니티, `externalTrafficPolicy` 와 소스 IP 보존

**실습**
- Service 타입별로 트래픽 경로를 직접 추적 (`iptables-save` / `ipvsadm` 관찰)
- 다른 네임스페이스 서비스에 DNS로 접근
- 셀렉터 오타를 심어 "연결 안 됨" 장애를 만들고 진단

**체크포인트**
- [ ] "Service에 붙지 않는다" 상황을 **Endpoints → Pod 라벨 → targetPort → probe** 순서로 5분 내 진단
- [ ] 클라이언트 → Service → Pod 경로를 그림으로 설명

### W6. 외부 노출과 네트워크 정책
**배울 것**
- Ingress와 Ingress Controller의 분리 구조, ingress-nginx 설치와 동작
- 호스트/경로 기반 라우팅, 리라이트, TLS 종료
- cert-manager로 인증서 자동 발급/갱신
- **Gateway API**: Ingress의 한계(애노테이션 난립, 역할 분리 불가)와 Gateway API의 역할 모델(GatewayClass / Gateway / HTTPRoute). 신규 구축 시 어느 쪽을 고를지 판단 기준
- NetworkPolicy: 기본 허용 정책을 기본 차단으로 전환, ingress/egress 규칙, 네임스페이스/Pod 셀렉터
  - 주의: NetworkPolicy는 **CNI가 지원해야 동작한다** (kind 기본 CNI는 미지원 → Calico/Cilium 교체 필요)

**실습**
- ingress-nginx 설치 후 `api.local` / `admin.local` 라우팅 + 자체서명 TLS
- kind 클러스터를 Calico(또는 Cilium)로 재구성
- "DB는 api Pod에서만 접근 가능" NetworkPolicy 작성 후 차단 검증
- 동일 라우팅을 Gateway API로 재작성해 비교

**체크포인트**
- [ ] 외부 → Ingress Controller → Service → Pod 전체 경로 설명
- [ ] NetworkPolicy 적용 전/후 접근 차단을 `kubectl exec` 로 실증
- [ ] Ingress vs Gateway API 선택 기준을 3줄로 정리

### W7. 스토리지와 설정·시크릿
**배울 것**
- Volume 종류: emptyDir / hostPath / projected / PVC — 각각의 수명
- PV / PVC / StorageClass, 정적 vs 동적 프로비저닝
- `accessModes`(RWO/ROX/RWX)의 실제 의미와 흔한 오해, `reclaimPolicy`(Retain/Delete)
- StatefulSet의 `volumeClaimTemplates`, 볼륨 확장, 스냅샷
- CSI 아키텍처 개요 (드라이버가 무엇을 대신 해주는가)
- ConfigMap / Secret: 환경변수 주입 vs 파일 마운트, **환경변수는 변경이 자동 반영되지 않는다**
- Secret은 암호화가 아니라 base64 인코딩일 뿐 → etcd 저장 시 암호화, 외부 시크릿 관리(External Secrets Operator, SOPS) 개요

**실습**
- 로컬 StorageClass(local-path)로 PVC 생성, MongoDB 데이터 영속성 확인(Pod 삭제 후 데이터 유지)
- PVC를 일부러 Pending으로 만들고 원인 3가지 재현
- ConfigMap 변경 시 롤아웃을 트리거하는 체크섬 애노테이션 패턴 적용
- Secret을 파일로 마운트하고 권한(`defaultMode`) 확인

**체크포인트**
- [ ] PVC Pending의 원인 3가지(StorageClass 없음 / 용량 부족 / accessMode 불일치)를 구분
- [ ] 설정 변경이 앱에 반영되는 경로 3가지(재시작 / 파일 갱신 / 롤아웃)를 설명
- [ ] "Secret을 Git에 어떻게 넣을 것인가"에 대한 본인 답을 정리 (W14에서 구현)

---

## Phase 3 — 운영 기본 (W8~W10 · 30h)

### W8. 패키징과 배포 — Helm / Kustomize
**배울 것**
- Helm: 차트 구조, `values.yaml`, 템플릿 함수, `_helpers.tpl`, 릴리스/업그레이드/롤백, 의존 차트, `helm template` 로 렌더 결과 검증
- Helm의 함정: 템플릿 과잉 추상화, values 폭발, 업그레이드 시 immutable 필드 충돌
- Kustomize: base/overlay, strategic merge patch, JSON patch, `configMapGenerator` 와 해시 기반 자동 롤아웃
- **선택 기준**: 배포 대상이 남에게 제공되는 패키지인가(Helm) vs 우리 환경별 변형인가(Kustomize). 둘의 조합 패턴
- 매니페스트 검증: `kubeconform`, `helm lint`, dry-run

**실습**
- 관통 프로젝트를 Helm 차트로 패키징 (api / worker / redis / mongo)
- dev / prod 차이를 Kustomize overlay로 분리
- 기존 `bitbucket-pipelines.yml` 패턴을 참고해 빌드 → 이미지 푸시 → 배포 파이프라인 초안 작성

**체크포인트**
- [ ] 동일 차트로 dev / prod 두 네임스페이스에 배포
- [ ] `helm rollback` 으로 직전 버전 복귀 성공
- [ ] `helm template` 결과를 리뷰해 의도한 매니페스트가 나오는지 확인

### W9. 관측성
**배울 것**
- 로그: stdout/stderr 규약, 노드 로테이션, 중앙 수집 아키텍처(DaemonSet 수집기), 구조화 로깅
- 메트릭: metrics-server(kubectl top용) vs Prometheus(장기/알림용), cAdvisor, kube-state-metrics의 역할 차이
- Prometheus 데이터 모델, PromQL 기초, ServiceMonitor / PodMonitor
- 지표 설계: RED(요청 기반) / USE(자원 기반), 어떤 것을 대시보드 최상단에 둘 것인가
- Grafana 대시보드 구성, Alertmanager 알림 라우팅과 알림 피로 방지
- 분산 추적과 OpenTelemetry 개요
- `kubectl events`, 이벤트의 보존 기간 한계

**실습**
- `kube-prometheus-stack` 설치
- 앱에 `/metrics` 노출 + ServiceMonitor 등록
- "요청 수 / 에러율 / p95 지연 / 포화도" 4패널 대시보드 직접 작성
- Loki로 로그 수집, 대시보드에서 메트릭 → 로그 이동
- 알림 룰 1개 작성 후 실제로 발화시키기

**체크포인트**
- [ ] "응답이 느려졌다"는 신고를 대시보드만으로 앱/DB/노드 중 어디인지 좁히기
- [ ] PromQL로 에러율과 p95 지연을 직접 작성
- [ ] 알림이 울린 뒤 무엇을 볼지 순서를 문서화

### W10. 트러블슈팅과 보안 기초
**배울 것**
- 진단 체계화: 이벤트 → 로그 → describe → 노드 → 컨트롤 플레인 순서
- `kubectl debug` 와 ephemeral container (배포 이미지에 셸이 없을 때)
- 노드 레벨 문제: 디스크/PID/메모리 압박, eviction, `NotReady` 원인 추적, kubelet 로그
- 컨트롤 플레인 장애 진단: API Server / etcd / scheduler 가 죽으면 각각 무엇이 멈추는가
- 인증과 인가: ServiceAccount 토큰, RBAC(Role / ClusterRole / RoleBinding / ClusterRoleBinding), `kubectl auth can-i`
- Pod Security Admission (PSP는 제거됨), `securityContext`: non-root, `readOnlyRootFilesystem`, capabilities drop
- Admission Controller 개념(Mutating/Validating)과 정책 엔진(Kyverno / OPA Gatekeeper), CEL 기반 Validating Admission Policy
- 이미지 보안: 취약점 스캔(Trivy), 이미지 태그 불변성, 레지스트리 신뢰

**실습**
- **고장난 클러스터 시나리오 5개를 스스로 만들고 복구** (예: kubelet 정지, CoreDNS 삭제, 잘못된 RBAC, 노드 디스크 full, Service 셀렉터 오류)
- 앱 전용 ServiceAccount + 최소 권한 Role 부여
- 앱 컨테이너를 non-root + read-only 루트로 전환
- Kyverno로 "`:latest` 태그 금지" 정책 적용 후 차단 확인

**체크포인트**
- [ ] 장애 시나리오 5개를 각각 10분 내 복구
- [ ] 앱이 root 없이, 쓰기 가능한 루트 없이 정상 동작
- [ ] 본인의 트러블슈팅 순서도를 1페이지로 작성 (이후 계속 갱신)

---

## Phase 4 — 온프렘 자체 구축 + CKA (W11~W12 · 20h)

### W11. kubeadm으로 직접 구축
**배울 것**
- 노드 사전 준비: swap 비활성화, 커널 모듈(`br_netfilter`, `overlay`), sysctl 설정이 **왜** 필요한가
- containerd 설치와 설정(`SystemdCgroup`), CRI가 무엇을 표준화했는가
- `kubeadm init` / `kubeadm join` 이 실제로 하는 일: 인증서 생성, static pod manifest 배치, 부트스트랩 토큰
- 컨트롤 플레인이 뜨는 방식: `/etc/kubernetes/manifests` 의 static pod, kubelet이 API Server 없이도 이들을 띄우는 구조
- PKI 구조: CA, apiserver/etcd/kubelet 인증서, kubeconfig가 담고 있는 것
- CNI 설치(Calico 또는 Cilium)와 Pod CIDR
- HA 컨트롤 플레인: stacked etcd vs external etcd, 로드밸런서 요구사항
- 온프렘의 빈칸 채우기: MetalLB로 LoadBalancer 구현, 스토리지(local-path / Longhorn)

**실습**
- **Multipass로 VM 3대 준비** → kubeadm으로 클러스터 구축
  ```bash
  multipass launch --name cp1    --cpus 2 --memory 4G --disk 20G 24.04
  multipass launch --name node1  --cpus 2 --memory 4G --disk 20G 24.04
  multipass launch --name node2  --cpus 2 --memory 4G --disk 20G 24.04
  ```
  두 머신에서 명령이 동일하다. 게스트 아키텍처만 x86_64 / arm64로 갈리고, kubeadm 절차는 완전히 같다
- **기존 Ansible 자산을 활용해 노드 사전 준비를 자동화** (플레이북 작성) — VM 생성 후 인벤토리만 갈아끼우면 양쪽에서 재사용
- HA 실습(cp 3 + worker 2)까지 하려면 워커 메모리를 2G로 낮춰 총 20GB 내로 맞춘다
- MetalLB 설치 후 LoadBalancer 타입 Service 실제 동작 확인
- 관통 프로젝트를 이 클러스터로 이전

**체크포인트**
- [ ] 문서 없이 kubeadm 클러스터를 40분 내 구축
- [ ] 컨트롤 플레인 Pod들이 static pod로 뜨는 것을 파일 경로까지 확인
- [ ] 노드가 `NotReady` 인 이유가 CNI 미설치임을 스스로 진단

### W12. 클러스터 수명주기 + CKA 대비
**배울 것**
- etcd 백업/복구: `etcdctl snapshot save` / `restore`, 복구 시 컨트롤 플레인 정지 절차 — **가장 자주 나오는 실무·시험 주제**
- 클러스터 업그레이드: 컨트롤 플레인 → 워커 순서, `kubeadm upgrade plan/apply`, drain/uncordon, 한 번에 한 마이너 버전
- 인증서 갱신(`kubeadm certs renew`), 만료 시 증상
- 노드 추가/제거, 토큰 재발급
- 백업 전략: etcd 스냅샷 + Velero(리소스/PV 백업)의 역할 구분
- API deprecation 대응: `kubectl convert`, 업그레이드 전 매니페스트 호환성 점검

**CKA 대비**
- 시험 형식(원격 감독, 브라우저 터미널, 공식 문서만 열람 가능), 시간 배분 전략
- 속도 도구: `alias k=kubectl`, `--dry-run=client -o yaml`, `kubectl explain`, JSONPath, `-o custom-columns`
- 도메인별 약점 진단 → 반복
- 모의고사(killer.sh 등)로 시간 압박 훈련
- ⚠️ **CKA 도메인 비중과 범위는 CNCF가 주기적으로 개정한다.** 응시 전 반드시 공식 커리큘럼(`github.com/cncf/curriculum`)에서 최신 버전을 확인할 것

**체크포인트**
- [ ] etcd 스냅샷으로 클러스터를 실제로 복구
- [ ] n-1 → n 버전 업그레이드를 서비스 무중단으로 완료
- [ ] 모의고사 80% 이상 (미달 시 W13을 미루고 보강)
- [ ] **CKA 응시** (또는 응시일 확정)

---

## Phase 5 — 클라우드/EKS + GitOps (W13~W14 · 20h)

### W13. EKS와 AWS 통합
**배울 것**
- 매니지드가 대신 해주는 것(컨트롤 플레인 HA/업그레이드/etcd)과 **여전히 내 책임인 것**(노드, 애드온, 워크로드, 비용)
- 노드 옵션: 관리형 노드 그룹 / 자체 관리 / Fargate / Karpenter, 각각의 트레이드오프
- VPC CNI: Pod가 VPC IP를 직접 받는 구조와 **IP 고갈 문제**, prefix delegation
- 권한 위임: IRSA와 EKS Pod Identity — OIDC 신뢰 관계가 실제로 어떻게 동작하는가
- AWS Load Balancer Controller(ALB/NLB), Ingress → ALB 매핑
- EBS / EFS CSI 드라이버, 볼륨의 AZ 종속성
- 클러스터 접근 제어(`aws-auth` ConfigMap → access entries 방식 전환)
- 오토스케일: Cluster Autoscaler vs Karpenter 비교
- ECR과 이미지 수명주기 정책

**실습**
- **기존 IaC 저장소 구조(`aws/modules`, `aws/environments`)에 `eks` 모듈을 추가**해 Terraform으로 클러스터 생성
- 관통 프로젝트를 EKS에 배포하고 ALB로 외부 노출
- IRSA로 앱에 S3 접근 권한 부여 (액세스 키 없이)
- `terraform destroy` → `apply` 로 전체 재현
- 💰 실습 후 반드시 destroy. 비용 알람 먼저 설정할 것

**체크포인트**
- [ ] Terraform 코드만으로 클러스터 + 앱을 처음부터 재현
- [ ] 앱이 ALB 도메인으로 서비스되고 HTTPS 적용
- [ ] 온프렘 대비 EKS에서 "사라진 작업"과 "새로 생긴 작업"을 표로 정리

### W14. GitOps와 배포 파이프라인
**배울 것**
- Push 방식 CD vs Pull 방식 GitOps, 클러스터 자격증명을 CI에 두지 않는 이점
- Argo CD: Application, 동기화 정책, self-heal, drift 감지, App of Apps
- 저장소 전략: 앱 코드 저장소 / 매니페스트 저장소 분리, 환경 승격(dev → stg → prod)
- 시크릿 관리 실전: External Secrets Operator + AWS Secrets Manager/SSM, 또는 SOPS
- 배포 전략: 블루/그린, 카나리(Argo Rollouts), 자동 롤백 조건
- 이미지 태그 전략: `latest` 금지, 커밋 SHA 기반 불변 태그
- Bitbucket Pipelines 연동 (기존 CI 자산 활용)

**실습**
- Argo CD 설치, 매니페스트 저장소 연결
- PR 머지 → 자동 배포 흐름 완성
- 클러스터에서 수동으로 리소스를 변경해 drift 자동 복구 확인
- 카나리 배포 1회 수행 (메트릭 기반 자동 승격/롤백)

**체크포인트**
- [ ] 수동 `kubectl apply` 없이 전 환경 배포
- [ ] Git 되돌리기만으로 배포 롤백
- [ ] 시크릿이 Git 저장소 어디에도 평문으로 없음

---

## Phase 6 — SRE / 플랫폼 엔지니어링 (W15~W16 · 20h)

### W15. 신뢰성 엔지니어링
**배울 것**
- SLI / SLO / 에러 버짓: 무엇을 측정할지 고르는 법, 에러 버짓 소진 시 정책
- 가용성 설계: PodDisruptionBudget, 다중 AZ 분산, `topologySpreadConstraints` 실전 적용
- 오토스케일링 3층: HPA(리소스/커스텀/외부 메트릭) / VPA / Cluster Autoscaler·Karpenter, 셋이 충돌하는 지점
- 안전한 종료: SIGTERM 처리, `preStop` 훅, `terminationGracePeriodSeconds`, 로드밸런서 등록 해제 타이밍
- 부하 테스트(k6)와 용량 계획, 리소스 적정화(request 과다 설정이 비용을 어떻게 태우는가)
- 카오스 엔지니어링: 가설 → 실험 → 관찰, 폭발 반경 제한
- 비용 최적화: 스팟 인스턴스, 리소스 낭비 가시화

**실습**
- 관통 프로젝트의 SLO 정의 + Grafana 에러 버짓 대시보드
- k6로 부하를 주며 HPA 스케일 아웃/인 관찰
- PDB 설정 후 노드 drain 안전성 재검증 (W4 체크포인트 완성)
- 카오스 실험: Pod 강제 삭제 / 노드 강제 종료 / 네트워크 지연 주입

**체크포인트**
- [ ] 노드 1대를 예고 없이 종료해도 SLO 위반 없음
- [ ] 부하 증가에 따라 자동 확장 후 자동 축소되는 전 과정 관찰
- [ ] 종료 중인 Pod로 트래픽이 가지 않음을 실증

### W16. 플랫폼 확장과 마무리
**배울 것**
- CRD와 오퍼레이터 패턴: 왜 필요한가, 컨트롤러가 reconcile 루프를 도는 방식(W1 사고 모델의 완성)
- 기성 오퍼레이터 활용과 도입 판단 기준(운영 부담 vs 이득)
- 멀티테넌시: 네임스페이스 격리, ResourceQuota / LimitRange, 팀별 RBAC
- 서비스 메시가 푸는 문제(mTLS, 세밀한 트래픽 제어, 관측성)와 그 비용 — **언제 도입하지 말아야 하는가**
- 운영 문화: 온콜 로테이션, 런북, 무비난 포스트모템, 변경 관리
- 업그레이드 정책: 지원 버전 주기, API deprecation 추적, 정기 업그레이드 루틴 설계

**실습**
- ResourceQuota / LimitRange로 테넌트 격리 구성
- kubebuilder로 간단한 CRD + 컨트롤러 작성 (예: 앱 배포를 한 리소스로 추상화)
- 관통 프로젝트 **런북 작성**: 배포 절차, 롤백 절차, 장애 시나리오별 대응, 대시보드 링크
- 그동안의 장애 실습 중 하나를 골라 **포스트모템 문서 1건** 작성

**체크포인트**
- [ ] 전체 스택을 처음부터 재구축하는 문서 완성 (타인이 따라할 수 있는 수준)
- [ ] 런북만 보고 배포/롤백/기본 장애 대응 가능
- [ ] 16주 회고: 아직 약한 영역 3가지 선정 → 이후 학습 계획

---

## 2. 도구 스택 요약

| 영역 | 사용 도구 | 도입 시점 |
|---|---|---|
| 컨테이너 런타임 | Docker Engine(Ubuntu) / OrbStack·Colima(macOS) | W1 |
| 로컬 클러스터 | kind (주력), minikube (비교) | W1 |
| CLI 보조 | k9s, kubectx/kubens, stern | W1~ |
| CNI | kindnet → Calico/Cilium | W6 |
| Ingress | ingress-nginx, cert-manager, Gateway API | W6 |
| 패키징 | Helm, Kustomize | W8 |
| 관측성 | kube-prometheus-stack, Grafana, Loki | W9 |
| 보안/정책 | Kyverno, Trivy | W10 |
| 온프렘 구축 | Multipass(VM), kubeadm, containerd, MetalLB, Ansible | W11 |
| 백업 | etcdctl, Velero | W12 |
| 클라우드 | EKS, Terraform, Karpenter, ALB Controller | W13 |
| GitOps | Argo CD, External Secrets, Argo Rollouts | W14 |
| 부하/카오스 | k6, 수동 카오스 실험 | W15 |
| 확장 | kubebuilder | W16 |

---

## 3. 참고 자료

**1순위 (항상 여기부터)**
- 공식 문서: https://kubernetes.io/docs/
- 공식 블로그의 릴리스 노트 — 버전별 변경점 추적

**시험**
- CKA 공식 커리큘럼: https://github.com/cncf/curriculum
- killer.sh 모의고사 (시험 등록 시 2회 제공)

**심화**
- Kubernetes 컴포넌트 소스: `kubernetes/kubernetes`
- CNCF 프로젝트 랜드스케이프 — 도구 선택 시 성숙도 확인
- SRE 도서(Google SRE Book / Workbook) — Phase 6 이론 보강

---

## 4. 진도 관리

```
k8s/
├── CURRICULUM.md          # 이 문서
├── notes/                 # setup.md(두 머신 환경 구축) + 주차별 회고 (W01.md ~ W16.md)
├── manifests/             # 주차별 실습 매니페스트
├── charts/                # 관통 프로젝트 Helm 차트
├── clusters/              # kind/kubeadm 클러스터 구성 파일
└── runbook/               # W16 산출물
```

이 디렉토리를 Git 저장소로 만들어 두 머신에서 이어서 작업한다. VM/클러스터는 각 머신에서 새로 만들고, **재현 가능한 코드와 문서만 동기화**한다.

**주차 완료 기준**: 체크포인트 전 항목 통과 + 회고 노트 작성. 하나라도 미달이면 다음 주차로 넘어가지 않고 보강한다.

**중간 점검 지점**
- W4 종료: Phase 1 전체 개념을 백지에 그려 설명
- W10 종료: 실무 투입 최소 역량 도달 판단
- W12 종료: CKA 응시 여부 결정
- W16 종료: 약점 3가지 선정 후 다음 학습 사이클 설계
