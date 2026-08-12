# 01. Workloads — 핵심 오브젝트

**주차**: W2~W4 / **시간**: 약 30시간

## 목표

관통 프로젝트를 실제로 클러스터에 올리면서 Pod·컨트롤러·스케줄링을 익힌다.
동시에 **의도적으로 고장 내고 진단하는 훈련**을 시작한다 — 이후 모든 단계의 기본기가 된다.

## 이론

### W2 — Pod의 해부

- [ ] Pod가 최소 배포 단위인 이유: 공유 네트워크 네임스페이스, 공유 볼륨, pause 컨테이너
- [ ] 멀티 컨테이너 패턴: 사이드카 / 앰배서더 / 어댑터, initContainer
- [ ] 네이티브 사이드카(`initContainers` + `restartPolicy: Always`) — 사용 전 클러스터 버전 확인
- [ ] 리소스 모델: `requests`(스케줄링) vs `limits`(런타임), CPU throttling과 메모리 OOMKill의 차이
- [ ] QoS 클래스: Guaranteed / Burstable / BestEffort — eviction 순서를 결정한다
- [ ] 헬스체크 3종: liveness / readiness / startup — **각각을 잘못 쓰면 어떤 장애가 나는가**
- [ ] 라벨 / 셀렉터 / 애노테이션, 네임스페이스
- [ ] 명령형(`kubectl run/create`) vs 선언형(`apply`) — 실무는 선언형, 시험은 명령형 속도

### W3 — 워크로드 컨트롤러

- [ ] ReplicaSet과 Deployment의 관계, 리비전 히스토리
- [ ] 배포 전략: `RollingUpdate`(`maxSurge`/`maxUnavailable`), `Recreate`, `rollout status/undo/pause`
- [ ] DaemonSet: 노드마다 하나 (로그 수집기, 노드 익스포터)
- [ ] StatefulSet: 안정적 네트워크 ID, 순차 생성/삭제, `volumeClaimTemplates` — **Deployment로 DB를 돌리면 안 되는 이유**
- [ ] Job / CronJob: 완료 보장, 병렬성, `backoffLimit`, 동시성 정책

### W4 — 스케줄링과 배치 제어

- [ ] 스케줄러 2단계: 필터링 → 스코어링
- [ ] `nodeSelector`, `nodeAffinity`(required/preferred), `podAffinity` / `podAntiAffinity`
- [ ] `taints` / `tolerations` — 노드를 격리하고 특정 워크로드만 허용
- [ ] `topologySpreadConstraints` 로 노드/AZ 균등 분산
- [ ] `PriorityClass` 와 preemption, 노드 압박 시 eviction 순서
- [ ] 노드 관리: `cordon` / `drain` / `uncordon`
- [ ] 정적 Pod(static pod) — [04-onprem-cka](../04-onprem-cka/) 복선

## 실습 (labs/)

**W2**
- 앱을 Pod 단독 → Deployment로 승격
- probe 3종을 붙이고 각각 실패시켜 동작 차이 관찰
- `limits.memory` 를 낮게 잡아 OOMKill 재현, CPU limit으로 throttling 재현
- initContainer로 DB 준비 대기 구현

**W3**
- 부하를 주며 롤링 업데이트 수행 → 에러율 관찰
- 고장난 이미지로 배포 후 `rollout undo` 로 복구
- MongoDB를 StatefulSet으로 전환 → Pod 이름/DNS가 고정되는 것 확인
- 배치 작업을 CronJob으로 전환, 실패 시 재시도 동작 확인

**W4**
- 노드 라벨링으로 특정 워크로드 고정
- anti-affinity로 api replica를 서로 다른 노드에 강제 분산
- taint를 걸어 "DB 전용 노드" 구성
- 노드 1개 `drain` 후 워크로드 이동 관찰

## 완료 기준

- [ ] `CrashLoopBackOff` / `OOMKilled` / liveness 실패 / `ImagePullBackOff` 를 각각 의도적으로 재현
- [ ] 위 4개를 `kubectl describe` + `logs --previous` 만으로 원인 지목
- [ ] 롤링 업데이트 중 실패 요청 0건 달성 (readiness + graceful shutdown)
- [ ] StatefulSet Pod를 삭제해도 같은 이름/같은 볼륨으로 복귀하는 것 확인
- [ ] 노드 1대를 drain 해도 서비스 무중단 (PDB는 [06-sre-platform](../06-sre-platform/)에서 완성)
- [ ] Pending 상태 Pod의 원인 3종 구분 (리소스 부족 / 셀렉터 불일치 / taint)
- [ ] `notes/` 에 이론 정리 작성

## 셀프 체크

1. Pod가 최소 배포 단위인 이유는? 컨테이너 하나를 직접 스케줄링하지 않는 까닭을 설명할 수 있는가?
2. `requests` 와 `limits` 는 각각 언제(스케줄링 시점 / 런타임) 어떻게 작용하는가? 둘을 같게 두면 무엇이 달라지는가?
3. liveness와 readiness를 서로 바꿔 설정하면 각각 어떤 장애가 나는가?
4. Deployment로 DB를 운영하면 안 되는 이유를 StatefulSet이 보장하는 것들로 설명할 수 있는가?
5. Pod가 `Pending` 인 원인 세 가지를 대고, 각각을 어떤 명령으로 구분하는가?
