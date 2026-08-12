# 02. Networking & Storage — 연결과 데이터

**주차**: W5~W7 / **시간**: 약 30시간

## 목표

관통 프로젝트를 외부에 노출하고 데이터를 영속화한다. 트래픽이 외부에서 Pod까지 도달하는 전 경로와,
데이터가 Pod 수명과 무관하게 남는 구조를 설명할 수 있게 된다.

## 이론

### W5 — 서비스와 클러스터 네트워킹

- [ ] Kubernetes 네트워크 모델의 원칙: NAT 없이 모든 Pod가 서로 통신 가능
- [ ] CNI가 하는 일 (구현체 심화는 [04-onprem-cka](../04-onprem-cka/))
- [ ] Service 4종: ClusterIP / NodePort / LoadBalancer / ExternalName + Headless
- [ ] Service의 실제 동작: Endpoints / EndpointSlice, kube-proxy 모드(iptables / IPVS / nftables)
- [ ] CoreDNS와 서비스 디스커버리: `svc.ns.svc.cluster.local` 규칙, Pod DNS 정책
- [ ] 세션 어피니티, `externalTrafficPolicy` 와 소스 IP 보존

### W6 — 외부 노출과 네트워크 정책

- [ ] Ingress와 Ingress Controller의 분리 구조 — 리소스만 만들고 컨트롤러가 없으면?
- [ ] 호스트/경로 기반 라우팅, 리라이트, TLS 종료
- [ ] cert-manager로 인증서 자동 발급·갱신
- [ ] **Gateway API**: Ingress의 한계(애노테이션 난립, 역할 분리 불가)와 Gateway API의 역할 모델
- [ ] NetworkPolicy: 기본 허용 → 기본 차단 전환, ingress/egress 규칙
  - ⚠️ NetworkPolicy는 **CNI가 지원해야 동작한다**. kind 기본 CNI(kindnet)는 미지원 → Calico/Cilium 교체 필요

### W7 — 스토리지와 설정·시크릿

- [ ] Volume 종류와 수명: emptyDir / hostPath / projected / PVC
- [ ] PV / PVC / StorageClass, 정적 vs 동적 프로비저닝
- [ ] `accessModes`(RWO/ROX/RWX)의 실제 의미와 흔한 오해, `reclaimPolicy`(Retain/Delete)
- [ ] StatefulSet의 `volumeClaimTemplates`, 볼륨 확장, 스냅샷
- [ ] CSI 아키텍처 개요
- [ ] ConfigMap / Secret: 환경변수 주입 vs 파일 마운트 — **환경변수는 변경이 자동 반영되지 않는다**
- [ ] Secret은 암호화가 아니라 base64 인코딩 → etcd 저장 시 암호화, 외부 시크릿 관리(External Secrets, SOPS) 개요

## 실습 (labs/)

**W5**
- Service 타입별 트래픽 경로 추적 (`iptables-save` / `ipvsadm` 관찰)
- 다른 네임스페이스 서비스에 DNS로 접근
- 셀렉터 오타를 심어 "연결 안 됨" 장애를 만들고 진단

**W6**
- kind 클러스터를 Calico(또는 Cilium)로 재구성
- ingress-nginx 설치 후 호스트 기반 라우팅 + 자체서명 TLS
  ```bash
  kubectl label node study-control-plane ingress-ready=true
  ```
  (클러스터 설정에 포트 매핑 8080/8443이 이미 있다 → `clusters/kind/study-cluster.yaml`)
- "DB는 api Pod에서만 접근 가능" NetworkPolicy 작성 후 차단 검증
- 동일 라우팅을 Gateway API로 재작성해 비교

**W7**
- 로컬 StorageClass로 PVC 생성, MongoDB 데이터 영속성 확인 (Pod 삭제 후 데이터 유지)
- PVC를 일부러 Pending으로 만들고 원인 3가지 재현
- ConfigMap 변경 시 롤아웃을 트리거하는 체크섬 애노테이션 패턴 적용
- Secret을 파일로 마운트하고 권한(`defaultMode`) 확인

## 완료 기준

- [ ] "Service에 붙지 않는다" 상황을 **Endpoints → Pod 라벨 → targetPort → probe** 순서로 5분 내 진단
- [ ] 외부 → Ingress Controller → Service → Pod 전체 경로를 그림으로 설명
- [ ] NetworkPolicy 적용 전/후 접근 차단을 `kubectl exec` 로 실증
- [ ] PVC Pending의 원인 3가지 구분 (StorageClass 없음 / 용량 부족 / accessMode 불일치)
- [ ] 설정 변경이 앱에 반영되는 경로 3가지 설명 (재시작 / 파일 갱신 / 롤아웃)
- [ ] Ingress vs Gateway API 선택 기준을 3줄로 정리
- [ ] `notes/` 에 이론 정리 작성

## 셀프 체크

1. Service의 ClusterIP로 보낸 패킷은 실제로 어떤 경로를 거쳐 Pod에 도달하는가? ClusterIP는 어디에 존재하는 IP인가?
2. Ingress 리소스만 만들고 컨트롤러를 설치하지 않으면 무슨 일이 일어나는가? 왜 에러가 나지 않는가?
3. NetworkPolicy를 적용했는데 트래픽이 차단되지 않는다면 가장 먼저 무엇을 의심해야 하는가?
4. `accessMode: ReadWriteOnce` 볼륨을 서로 다른 노드의 두 Pod가 마운트하려 하면 어떻게 되는가?
5. ConfigMap을 수정했는데 앱에 반영되지 않는다. 어떤 주입 방식을 썼기 때문이며, 어떻게 해결하는가?
