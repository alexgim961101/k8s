# Kubernetes 실전 운영 학습

로컬 클러스터에서 시작해 온프렘 자체 구축과 EKS 운영, SRE 업무까지 이어가는 학습 저장소.
각 단계마다 **이론 정리 + 직접 구축 + 장애 재현**을 병행한다.

목표 기간: 16주 (주 10시간 내외, 총 약 160시간) / 목표: 실무 운영 역량 + CKA 취득

## 학습 규칙

- 각 phase 디렉토리 구성: `README.md`(목표·이론·실습·완료 기준·셀프 체크) + `notes/`(이론 정리) + `labs/`(매니페스트·설정)
- 실습은 **만들기 → 고장 내기 → 진단하기**까지 해야 끝. 읽기만 한 단계는 완료로 치지 않는다
- 각 phase의 셀프 체크 질문에 스스로 답할 수 있으면 다음 단계로 진행
- 주제 딥다이브는 본문에 넣지 않고 [`reference/`](reference/)에 누적 (본문은 운영 흐름 유지)
- **관통 프로젝트 하나를 16주 내내 발전시킨다** → [`app/`](app/)
- 공식 문서가 1순위 교재다. kubernetes.io/docs를 검색이 아니라 목차로 읽는 습관을 들인다

## 전체 목차

| Phase | 주제 | 핵심 내용 | 주차 | 진행 |
|-------|------|-----------|------|------|
| [00-setup](00-setup/) | 준비와 첫 클러스터 | 컨테이너 복습, K8s 아키텍처, kind 멀티노드, kubectl 기본기 | W1 | ⬜ |
| [01-workloads](01-workloads/) | 핵심 오브젝트 | Pod 해부, 컨트롤러(Deployment/StatefulSet/Job), 스케줄링 | W2~4 | ⬜ |
| [02-networking-storage](02-networking-storage/) | 연결과 데이터 | Service, Ingress/Gateway API, NetworkPolicy, PV/PVC, ConfigMap·Secret | W5~7 | ⬜ |
| [03-operations](03-operations/) | 운영 기본 | Helm·Kustomize, 관측성, 트러블슈팅, RBAC·보안 | W8~10 | ⬜ |
| [04-onprem-cka](04-onprem-cka/) | 온프렘 자체 구축 | kubeadm 구축, etcd 백업·복구, 업그레이드, **CKA 응시** | W11~12 | ⬜ |
| [05-eks-gitops](05-eks-gitops/) | 클라우드와 자동 배포 | EKS, Terraform, IRSA, Argo CD GitOps | W13~14 | ⬜ |
| [06-sre-platform](06-sre-platform/) | SRE·플랫폼 | SLO, 오토스케일, 카오스, 오퍼레이터, 런북 | W15~16 | ⬜ |
| [app](app/) | 관통 프로젝트 | 16주 내내 발전시키는 미니 서비스 | 전 구간 | — |
| [clusters](clusters/) | 클러스터 구성 | kind 설정, kubeadm/Ansible 프로비저닝 | 전 구간 | — |
| [reference](reference/) | 주제별 딥다이브 | 학습 중 깊이 팔 주제를 수시 누적 | — | — |

진행 표시: 완료한 phase는 ⬜ → ✅ 로 변경.

## 학습 흐름

- **00 → 02**: 클러스터 위에 서비스를 올리는 여정 (첫 클러스터 → 워크로드 → 연결·데이터)
- **03**: 운영 품질 (패키징, 관측성, 진단, 보안)
- **04**: 밑바닥으로 내려가기 — 클러스터를 직접 만들고 복구한다. CKA 사정권
- **05 → 06**: 위로 올라가기 — 매니지드 운영, 자동 배포, 신뢰성 엔지니어링

**나선형 진행**: 00~03은 이미 동작하는 클러스터 위에서 오브젝트를 배우고, 04에서 그 클러스터를 직접 만들며 앞서 블랙박스였던 부분을 열어본다. kind의 노드가 kubeadm으로 구성된 컨테이너라 두 단계가 자연스럽게 이어진다.

## 실습 환경

두 대의 머신을 오가며 학습한다. **동일한 절차로 실습할 수 있도록** 도구를 선택했다.

| 항목 | 머신 A | 머신 B |
|---|---|---|
| OS / 아키텍처 | Ubuntu 24.04 / **x86_64** | macOS / **arm64 (M4)** |
| 가상화 | KVM | Hypervisor.framework |
| 컨테이너 런타임 | Docker Engine | OrbStack 또는 Colima |
| 로컬 클러스터 | kind (공통) | kind (공통) |
| 온프렘 VM (04) | Multipass (공통) | Multipass (공통) |

설치 절차는 [`00-setup/notes/setup.md`](00-setup/notes/setup.md) 참조.

**아키텍처 차이 대응**
- Kubernetes 공식 컴포넌트와 `kindest/node`, 주요 에코시스템(Calico, Cilium, MetalLB, ingress-nginx, cert-manager, Argo CD, kube-prometheus-stack)은 모두 arm64를 지원하므로 명령과 매니페스트가 동일하다
- 직접 빌드한 앱 이미지만 아키텍처를 탄다. 각 머신에서 로컬 빌드하거나 `docker buildx --platform linux/amd64,linux/arm64` 로 멀티아키 빌드
- 드물게 arm64 이미지가 없는 서드파티를 만나면 대체 도구를 쓰거나 해당 실습만 머신 A에서 진행 (에뮬레이션은 느려서 비권장)
- VM·클러스터는 각 머신에서 새로 만들고, **재현 가능한 코드와 문서만** Git으로 동기화한다

⚠️ **비용**: 05-eks-gitops만 AWS 과금이 발생한다. 실습 전 예산 알람을 설정하고, 매 실습은 `terraform destroy` 로 마무리한다.

## 도구 스택

| 영역 | 도구 | 도입 |
|---|---|---|
| 컨테이너 런타임 | Docker Engine / OrbStack·Colima | 00 |
| 로컬 클러스터 | kind (주력), minikube (비교) | 00 |
| CLI 보조 | k9s, stern, kubectx/kubens | 00 |
| CNI | kindnet → Calico/Cilium | 02 |
| 외부 노출 | ingress-nginx, cert-manager, Gateway API | 02 |
| 패키징 | Helm, Kustomize(kubectl 내장) | 03 |
| 관측성 | kube-prometheus-stack, Grafana, Loki | 03 |
| 보안·정책 | Kyverno, Trivy | 03 |
| 온프렘 구축 | Multipass, kubeadm, containerd, MetalLB, Ansible | 04 |
| 백업 | etcdctl, Velero | 04 |
| 클라우드 | EKS, Terraform, Karpenter, AWS Load Balancer Controller | 05 |
| GitOps | Argo CD, External Secrets, Argo Rollouts | 05 |
| 부하·카오스 | k6 | 06 |
| 확장 | kubebuilder | 06 |

## 참고 자료

**1순위**
- [공식 문서](https://kubernetes.io/docs/) — 항상 여기부터
- 릴리스 노트 — 버전별 변경점 추적

**시험**
- [CKA 공식 커리큘럼](https://github.com/cncf/curriculum) — ⚠️ 도메인 비중과 범위는 주기적으로 개정되므로 응시 전 최신 버전 확인 필수
- killer.sh 모의고사 (시험 등록 시 2회 제공)

**심화**
- `kubernetes/kubernetes` 소스
- CNCF 랜드스케이프 — 도구 선택 시 성숙도 확인
- Google SRE Book / Workbook — 06 이론 보강

## 진행 관리

**단계 완료 기준**: README의 완료 기준 전 항목 통과 + 셀프 체크 질문에 답변 가능 + `notes/` 에 정리 작성.
하나라도 미달이면 다음 단계로 넘어가지 않고 보강한다.

**중간 점검**
- 01 종료: 핵심 오브젝트를 백지에 그려 설명
- 03 종료: 실무 투입 최소 역량 도달 판단
- 04 종료: CKA 응시 여부 결정
- 06 종료: 약점 3가지 선정 후 다음 학습 사이클 설계
