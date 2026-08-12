# 관통 프로젝트 — 미니 서비스 플랫폼

16주 동안 **하나의 서비스를 계속 발전시킨다.** 매주 새 예제를 만들면 축적이 되지 않는다.
기존에 다루던 스택과 최대한 비슷하게 잡아 실무 전이를 극대화한다.

## 구성

```
[외부] → Ingress/Gateway → api (Node/NestJS, stateless, 2+ replicas)
                              ├→ cache (Redis, 단일)
                              └→ db    (MongoDB, StatefulSet + PVC)
         + worker (Job/CronJob으로 배치 처리)
```

## 무엇으로 시작할까

기존 프로젝트(`nestjs_test`, `my-todo-list` 등) 중 하나를 가져와도 되고, 최소 API를 새로 만들어도 된다.
**조건은 하나 — 16주 내내 같은 것을 쓴다.**

최소 요건:
- HTTP 엔드포인트 하나 이상 (헬스체크용 `/healthz`, `/readyz` 포함)
- DB 연결 (연결 실패 시 readiness가 실패하도록)
- `/metrics` 노출 가능 (03단계에서 사용)
- SIGTERM 처리 (06단계에서 graceful shutdown 검증)

## 단계별 진화

| 단계 | 상태 |
|---|---|
| [00-setup](../00-setup/) | 컨테이너 이미지로 빌드, Pod 하나로 첫 배포 |
| [01-workloads](../01-workloads/) | Deployment/StatefulSet으로 전환, 스케줄링 제약까지 반영해 멀티노드 분산 |
| [02-networking-storage](../02-networking-storage/) | Ingress로 외부 노출, 데이터 영속성 + 설정/시크릿 분리 |
| [03-operations](../03-operations/) | Helm 차트로 패키징, dev/prod 분리, 메트릭 노출, 최소 권한 RBAC + NetworkPolicy |
| [04-onprem-cka](../04-onprem-cka/) | 자체 구축한 kubeadm 클러스터로 이전 |
| [05-eks-gitops](../05-eks-gitops/) | Argo CD GitOps로 EKS에 자동 배포 |
| [06-sre-platform](../06-sre-platform/) | SLO 정의 + 오토스케일 + 런북까지 갖춘 "운영 가능한" 서비스 |

## 디렉토리 구성

이 디렉토리에는 **16주 내내 이어지는 것**만 둔다. 단계별 일회성 실습 매니페스트는 각 단계의 `labs/` 로.

```
app/
├── src/          # 앱 소스 (또는 기존 저장소 참조)
├── chart/        # Helm 차트 (03단계부터)
└── overlays/     # Kustomize dev/prod (03단계부터)
```

## 규칙

- **이미지 태그에 `latest` 를 쓰지 않는다.** 커밋 SHA 또는 semver를 쓴다
- 설정은 이미지에 굽지 않는다 — ConfigMap/Secret으로 주입
- 앱이 상태를 로컬 디스크에 두지 않는다 (DB/캐시로 분리)
- 두 머신을 오갈 때는 각 머신에서 로컬 빌드하거나 멀티아키로 빌드한다:
  ```bash
  docker buildx build --platform linux/amd64,linux/arm64 -t <repo>:<tag> --push .
  ```
