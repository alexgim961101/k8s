# 자가 채점표

> [← 시험장 명령 치트시트](10-cheatsheet.md) · [목록](README.md)

풀고 나서 기록한다. **2회차에 걸린 시간이 줄었는지**가 실력이다.

| 문제 | 1회차 | 2회차 | 약점 메모 |
|---|---|---|---|
| A-1 컨텍스트 정보 추출 | | | `--minify` 습관 |
| A-2 kubeconfig 복구 | | | |
| B-1 static pod 경로 | | | mirror pod 삭제 불가 |
| B-2 static pod 추가 | | | 파일 기반 생성 |
| C-1 NotReady 5원인 | | | 원인 구분 |
| C-2 컴포넌트 로그 | | | |
| C-3 ContainerCreating | | | |
| C-4 리소스 모니터링 | | | |
| D-1 스케줄러 정지 | | | |
| D-2 API 서버 복구 | | | kubectl 없는 진단 |
| D-3 etcd 확인 | | | |
| E-1 Service 장애 | | | endpoints |
| E-2 DNS 확인 | | | FQDN 규칙 |
| F-1 노드 사전 준비 | | | |
| F-2 kubeadm 구축 | | | 40분 목표 |
| F-3 CRI/CNI/CSI | | | |
| F-4 업그레이드 순서 | | | |
| G-1 reconciliation | | | |
| G-2 계층별 진단 | | | |
| G-3 requests/limits | | | |
| H-1 RBAC/kubeconfig | | | 03 범위 |

**다음 단계 예고**

| 아직 못 푸는 것 | 어디서 배우나 |
|---|---|
| PVC/PV, StorageClass, CSI | 02-networking-storage |
| Ingress, NetworkPolicy, Gateway API | 02-networking-storage |
| Helm, Kustomize, 오퍼레이터 | 03-operations |
| RBAC 심화, ServiceAccount, 보안 | 03-operations |
| etcd 스냅샷 복구, 업그레이드 실행 | 04-onprem-cka W12 |
| HA 컨트롤 플레인, 인증서 갱신 | 04-onprem-cka W12 |

---

## 참고

- [CKA Curriculum (CNCF)](https://github.com/cncf/curriculum) — 비중은 개정되므로 응시 전 확인
- [Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [Cluster Troubleshooting](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Verify node health / Node status](https://kubernetes.io/docs/reference/node/node-status/)
- 노드 사전 준비 근거: [`notes/kubeadm-setup.md`](../../notes/kubeadm-setup.md)
