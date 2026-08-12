# 05. EKS & GitOps — 클라우드와 자동 배포

**주차**: W13~W14 / **시간**: 약 20시간

⚠️ **이 단계만 AWS 과금이 발생한다.** 실습 전 예산 알람을 설정하고, 매 실습은 `terraform destroy` 로 마무리한다.

## 목표

직접 만든 온프렘 클러스터와 매니지드 EKS를 비교하며, **무엇이 내 책임에서 사라지고 무엇이 새로
생기는지** 몸으로 안다. 그리고 `kubectl apply` 를 손으로 치지 않는 배포 체계를 만든다.

기존 [`../IaC`](../../IaC) 저장소의 `aws/modules`, `aws/environments` 구조를 그대로 따른다.

## 이론

### W13 — EKS와 AWS 통합

- [ ] 매니지드가 대신 해주는 것(컨트롤 플레인 HA·업그레이드·etcd)과 **여전히 내 책임인 것**(노드, 애드온, 워크로드, 비용)
- [ ] 노드 옵션: 관리형 노드 그룹 / 자체 관리 / Fargate / Karpenter — 각각의 트레이드오프
- [ ] VPC CNI: Pod가 VPC IP를 직접 받는 구조와 **IP 고갈 문제**, prefix delegation
- [ ] 권한 위임: IRSA와 EKS Pod Identity — OIDC 신뢰 관계가 실제로 어떻게 동작하는가
- [ ] AWS Load Balancer Controller(ALB/NLB), Ingress → ALB 매핑
- [ ] EBS / EFS CSI 드라이버, **볼륨의 AZ 종속성**
- [ ] 클러스터 접근 제어: `aws-auth` ConfigMap → access entries 방식 전환
- [ ] 오토스케일: Cluster Autoscaler vs Karpenter
- [ ] ECR과 이미지 수명주기 정책

### W14 — GitOps와 배포 파이프라인

- [ ] Push 방식 CD vs Pull 방식 GitOps — 클러스터 자격증명을 CI에 두지 않는 이점
- [ ] Argo CD: Application, 동기화 정책, self-heal, drift 감지, App of Apps
- [ ] 저장소 전략: 앱 코드 / 매니페스트 저장소 분리, 환경 승격(dev → stg → prod)
- [ ] 시크릿 관리 실전: External Secrets Operator + Secrets Manager/SSM, 또는 SOPS
- [ ] 배포 전략: 블루/그린, 카나리(Argo Rollouts), 자동 롤백 조건
- [ ] 이미지 태그 전략: `latest` 금지, 커밋 SHA 기반 불변 태그
- [ ] Bitbucket Pipelines 연동 (기존 CI 자산 활용)

## 실습 (labs/)

**W13**
- 기존 IaC 저장소 구조에 `eks` 모듈을 추가해 Terraform으로 클러스터 생성
- 관통 프로젝트를 EKS에 배포하고 ALB로 외부 노출 + HTTPS
- IRSA로 앱에 S3 접근 권한 부여 (액세스 키 없이)
- `terraform destroy` → `apply` 로 전체 재현

**W14**
- Argo CD 설치, 매니페스트 저장소 연결
- PR 머지 → 자동 배포 흐름 완성
- 클러스터에서 수동으로 리소스를 변경해 drift 자동 복구 확인
- 카나리 배포 1회 (메트릭 기반 자동 승격/롤백)

## 완료 기준

- [ ] Terraform 코드만으로 클러스터 + 앱을 처음부터 재현
- [ ] 앱이 ALB 도메인으로 서비스되고 HTTPS 적용
- [ ] 온프렘 대비 EKS에서 "사라진 작업"과 "새로 생긴 작업"을 표로 정리 (`notes/`)
- [ ] 수동 `kubectl apply` 없이 전 환경 배포
- [ ] Git 되돌리기만으로 배포 롤백
- [ ] 시크릿이 Git 저장소 어디에도 평문으로 없음
- [ ] **실습 종료 후 모든 리소스 destroy 확인** (비용 대시보드로 검증)

## 셀프 체크

1. EKS로 옮기면서 내 책임에서 사라진 일과 새로 생긴 일은 각각 무엇인가?
2. IRSA는 Pod에 AWS 액세스 키 없이 어떻게 권한을 주는가? 신뢰 관계의 흐름을 설명할 수 있는가?
3. VPC CNI에서 IP 고갈이 발생하는 이유는? 완화 방법 두 가지는?
4. Push CD 대신 Pull GitOps를 쓰면 보안·운영 측면에서 각각 무엇이 좋아지는가?
5. Argo CD가 drift를 감지했을 때 self-heal이 켜져 있으면 / 꺼져 있으면 각각 어떻게 되는가? 긴급 수동 조치가 필요한 상황에서는 어느 쪽이 맞는가?
