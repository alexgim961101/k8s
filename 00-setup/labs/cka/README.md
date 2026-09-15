# CKA 실전 문제 — 00-setup 범위

**문제 풀이집** · [00-setup으로 돌아가기](../../README.md)

> **출제 기준**: CNCF 공식 [CKA Curriculum v1.35](https://github.com/cncf/curriculum) — 도메인 비중은 개정되니 응시 전 최신 확인
> **대상 범위**: 00-setup에서 다룬 것 — 클러스터 아키텍처 · static pod · 컨테이너 런타임 · kubeadm 구축 · 노드/컴포넌트 트러블슈팅
> **환경**: [`clusters/kind/study-cluster.yaml`](../../../clusters/kind/study-cluster.yaml)의 kind 클러스터(3노드). 파괴적 실습은 언제든 버릴 수 있는 클러스터에서 한다.

## 사용법

1. 문제를 읽고 **먼저 스스로 푼다.** 답은 `<details>` 안에 접혀 있다.
2. 시간을 잰다. CKA는 **문제당 평균 6분**이다 (2시간 / 약 15~20문제).
3. 막히면 답을 보기 전에 **① `kubectl explain` ② `kubectl describe` ③ `kubectl get events`** 순서로 시도한다.
4. 다 풀면 [자가 채점표](11-scoring.md)에 약점을 기록한다.

**공통 준비**

```bash
cd /Users/alex/src/study/k8s
kind create cluster --config clusters/kind/study-cluster.yaml

alias k=kubectl
export do='--dry-run=client -o yaml'     # 시험장 필수 습관
```

## 문제 목록

| 파일 | 내용 | 문제 |
|---|---|---|
| [01. kubeconfig와 context](01-kubeconfig-context.md) | 컨텍스트 전환, 값 추출, kubeconfig 복구 | A-1 ~ A-2 |
| [02. static pod](02-static-pods.md) | mirror pod, staticPodPath, 매니페스트로 직접 생성 | B-1 ~ B-2 |
| [03. 노드 장애 진단](03-node-troubleshooting.md) | NotReady 원인 5종 구분, 컴포넌트 로그, ContainerCreating, 리소스 모니터링 | C-1 ~ C-4 |
| [04. 컴포넌트 장애](04-control-plane-troubleshooting.md) | 스케줄러 정지, **kubectl 없는 진단**, etcd | D-1 ~ D-3 |
| [05. 서비스와 네트워크](05-service-dns-troubleshooting.md) | endpoints → targetPort → kube-proxy → CoreDNS, FQDN 규칙 | E-1 ~ E-2 |
| [06. kubeadm 클러스터](06-kubeadm-cluster.md) | 노드 사전 준비 5조건, 40분 구축, CRI/CNI/CSI, 업그레이드 | F-1 ~ F-4 |
| [07. 스케줄링과 reconciliation](07-scheduling-reconciliation.md) | 스케줄러 vs kubelet, 계층별 진단, requests vs limits | G-1 ~ G-3 |
| [08. RBAC 미리보기](08-rbac-preview.md) | 새 사용자 kubeconfig (03 범위 연결) | H-1 |
| [09. 속도 훈련](09-speed-drills.md) | 즉시 답하기, YAML 없이 생성, 고장→5분 복구 | Drill 1~3 |
| [10. 시험장 치트시트](10-cheatsheet.md) | 명령 모음, 시간 배분 | — |
| [11. 자가 채점표](11-scoring.md) | 2회차 기록, 다음 단계 예고, 참고 링크 | — |

## 도메인 매핑

공식 커리큘럼 도메인 중 **00-setup에서 이미 다룬 competency**만 표시했다.

| 도메인 (비중) | 00-setup에서 다룬 competency | 문제 |
|---|---|---|
| **Cluster Architecture, Installation & Configuration (25%)** | Prepare underlying infrastructure for installing a Kubernetes cluster | F-1, F-2 |
| | Create and manage Kubernetes clusters using kubeadm | F-1 ~ F-3 |
| | Understand extension interfaces (CNI, CRI, CSI) | F-3, C-3 |
| | Manage the lifecycle of Kubernetes clusters | F-4 |
| **Troubleshooting (30%)** | Troubleshoot clusters and nodes | C-1 ~ C-3 |
| | Troubleshoot cluster components | D-1 ~ D-3 |
| | Manage and evaluate container output streams | C-2, D-2 |
| | Monitor cluster and application resource usage | C-4 |
| | Troubleshoot services and networking | E-1, E-2 |
| **Workloads & Scheduling (15%)** | Configure Pod admission and scheduling (limits, node affinity, etc.) | G-3 |
| | Primitives for robust, self-healing deployments | G-1, G-2 |
| **Services & Networking (20%)** | Understand and use CoreDNS | E-2 |
| **Storage (10%)** | — | 02 범위 |
| (미리보기) | Manage role based access control (RBAC) | H-1 |

## 00-setup 셀프 체크 ↔ 문제

[00-setup README](../../README.md#셀프-체크)의 5문항을 풀 수 있는지 스스로 확인한다.

| 셀프 체크 | 대응 문제 |
|---|---|
| 1. kind 노드는 무엇인가? VM 기반과 무엇이 다른가? | F-1 (VM과의 차이), B-1 |
| 2. API 서버 없이 컨트롤 플레인이 뜨는 이유 | B-1, C-3 |
| 3. 스케줄러를 멈추면 기존/신규 Pod는? | D-1 |
| 4. kubeconfig의 cluster / user / context | A-1, A-2, H-1 |
| 5. 선언적 상태와 reconciliation | G-1, G-2 |
| 컴포넌트 표를 채우고 최소 2개를 실제로 멈춰보기 | D-1 ~ D-3 |

---

> 이 문제집은 [clusters/kubeadm](../../../clusters/kubeadm/)의 구축 절차와
> [notes/kubeadm-setup.md](../../notes/kubeadm-setup.md)의 개념 정리를 전제로 한다.
