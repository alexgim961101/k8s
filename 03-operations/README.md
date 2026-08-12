# 03. Operations — 운영 기본

**주차**: W8~W10 / **시간**: 약 30시간

## 목표

"배포할 수 있다"에서 "운영할 수 있다"로 넘어간다. 환경별 배포를 코드로 관리하고, 무슨 일이
일어나는지 관측하고, 문제가 생겼을 때 체계적으로 진단하고, 최소 권한으로 잠근다.
**이 단계를 마치면 실무 투입 최소 역량에 도달한다.**

## 이론

### W8 — 패키징과 배포

- [ ] Helm: 차트 구조, `values.yaml`, 템플릿 함수, `_helpers.tpl`, 릴리스/업그레이드/롤백, 의존 차트
- [ ] `helm template` 로 렌더 결과 검증하는 습관
- [ ] Helm의 함정: 템플릿 과잉 추상화, values 폭발, 업그레이드 시 immutable 필드 충돌
- [ ] Kustomize: base/overlay, strategic merge patch, JSON patch, `configMapGenerator` 의 해시 기반 자동 롤아웃
- [ ] **선택 기준**: 남에게 제공하는 패키지인가(Helm) vs 우리 환경별 변형인가(Kustomize), 그리고 둘의 조합
- [ ] 매니페스트 검증: `kubeconform`, `helm lint`, dry-run

### W9 — 관측성

- [ ] 로그: stdout/stderr 규약, 노드 로테이션, 중앙 수집 아키텍처(DaemonSet 수집기), 구조화 로깅
- [ ] 메트릭 출처의 차이: metrics-server(`kubectl top`) vs Prometheus(장기·알림), cAdvisor, kube-state-metrics
- [ ] Prometheus 데이터 모델, PromQL 기초, ServiceMonitor / PodMonitor
- [ ] 지표 설계: RED(요청 기반) / USE(자원 기반) — 대시보드 최상단에 무엇을 둘 것인가
- [ ] Grafana 대시보드 구성, Alertmanager 알림 라우팅과 **알림 피로 방지**
- [ ] 분산 추적과 OpenTelemetry 개요
- [ ] `kubectl events` 와 이벤트 보존 기간의 한계

### W10 — 트러블슈팅과 보안 기초

- [ ] 진단 순서 체계화: 이벤트 → 로그 → describe → 노드 → 컨트롤 플레인
- [ ] `kubectl debug` 와 ephemeral container (배포 이미지에 셸이 없을 때)
- [ ] 노드 레벨 문제: 디스크/PID/메모리 압박, eviction, `NotReady` 원인 추적, kubelet 로그
- [ ] 인증과 인가: ServiceAccount 토큰, RBAC(Role / ClusterRole / RoleBinding / ClusterRoleBinding), `kubectl auth can-i`
- [ ] Pod Security Admission (PSP는 제거됨), `securityContext`: non-root, `readOnlyRootFilesystem`, capabilities drop
- [ ] Admission Controller(Mutating/Validating)와 정책 엔진(Kyverno / OPA Gatekeeper), CEL 기반 Validating Admission Policy
- [ ] 이미지 보안: 취약점 스캔(Trivy), 태그 불변성, 레지스트리 신뢰

## 실습 (labs/)

**W8**
- 관통 프로젝트를 Helm 차트로 패키징 (api / worker / redis / mongo) → [`app/`](../app/)
- dev / prod 차이를 Kustomize overlay로 분리
- 기존 `bitbucket-pipelines.yml` 패턴을 참고해 빌드 → 이미지 푸시 → 배포 파이프라인 초안

**W9**
- `kube-prometheus-stack` 설치
- 앱에 `/metrics` 노출 + ServiceMonitor 등록
- "요청 수 / 에러율 / p95 지연 / 포화도" 4패널 대시보드 직접 작성
- Loki로 로그 수집, 대시보드에서 메트릭 → 로그 이동
- 알림 룰 1개 작성 후 실제로 발화시키기

**W10**
- **고장난 클러스터 시나리오 5개를 스스로 만들고 복구**
  (예: kubelet 정지, CoreDNS 삭제, 잘못된 RBAC, 노드 디스크 full, Service 셀렉터 오류)
- 앱 전용 ServiceAccount + 최소 권한 Role 부여
- 앱 컨테이너를 non-root + read-only 루트로 전환
- Kyverno로 "`:latest` 태그 금지" 정책 적용 후 차단 확인

## 완료 기준

- [ ] 동일 차트로 dev / prod 두 네임스페이스에 배포, `helm rollback` 성공
- [ ] "응답이 느려졌다"는 신고를 대시보드만으로 앱/DB/노드 중 어디인지 좁히기
- [ ] PromQL로 에러율과 p95 지연을 직접 작성
- [ ] 장애 시나리오 5개를 각각 10분 내 복구
- [ ] 앱이 root 없이, 쓰기 가능한 루트 없이 정상 동작
- [ ] **본인의 트러블슈팅 순서도를 1페이지로 작성** (`notes/` — 이후 계속 갱신)

## 셀프 체크

1. Helm과 Kustomize 중 무엇을 쓸지 어떤 기준으로 판단하는가? 둘을 함께 쓰는 구성은 어떤 모습인가?
2. 메트릭에 이상이 보이는데 원인을 모를 때, 로그와 트레이스는 각각 어떤 질문에 답해주는가?
3. Role과 ClusterRole의 차이는? ClusterRole을 RoleBinding으로 바인딩하면 권한 범위가 어떻게 되는가?
4. 컨테이너를 non-root로 전환할 때 흔히 깨지는 것들은 무엇이며 어떻게 대처하는가?
5. 노드가 `NotReady` 다. 무엇을 어떤 순서로 확인하는가?
