# 04. On-Prem & CKA — 클러스터를 직접 만든다

**주차**: W11~W12 / **시간**: 약 20시간

## 목표

지금까지 kind가 대신 해주던 일을 직접 한다. VM 위에 kubeadm으로 클러스터를 세우고,
etcd를 백업·복구하고, 버전을 업그레이드한다. 앞 단계에서 블랙박스였던 부분이 여기서 열린다.
CKA 사정권에 들어오는 지점이기도 하다.

## 이론

### W11 — kubeadm으로 직접 구축

- [ ] 노드 사전 준비: swap 비활성화, 커널 모듈(`br_netfilter`, `overlay`), sysctl 설정이 **왜** 필요한가
- [ ] containerd 설치와 설정(`SystemdCgroup`), CRI가 표준화한 것
- [ ] `kubeadm init` / `join` 이 실제로 하는 일: 인증서 생성, static pod manifest 배치, 부트스트랩 토큰
- [ ] 컨트롤 플레인이 뜨는 방식: `/etc/kubernetes/manifests` 의 static pod — [00-setup](../00-setup/)에서 본 구조
- [ ] PKI 구조: CA, apiserver/etcd/kubelet 인증서, kubeconfig가 담고 있는 것
- [ ] CNI 설치(Calico 또는 Cilium)와 Pod CIDR
- [ ] HA 컨트롤 플레인: stacked etcd vs external etcd, 로드밸런서 요구사항
- [ ] 온프렘의 빈칸: MetalLB로 LoadBalancer 구현, 스토리지(local-path / Longhorn)

### W12 — 클러스터 수명주기

- [ ] etcd 백업·복구: `etcdctl snapshot save` / `restore`, 복구 시 컨트롤 플레인 정지 절차 — **실무·시험 최빈출**
- [ ] 클러스터 업그레이드: 컨트롤 플레인 → 워커 순서, `kubeadm upgrade plan/apply`, drain/uncordon, 한 번에 한 마이너 버전
- [ ] 인증서 갱신(`kubeadm certs renew`)과 만료 시 증상
- [ ] 노드 추가/제거, 토큰 재발급
- [ ] 백업 전략: etcd 스냅샷과 Velero(리소스·PV 백업)의 역할 구분
- [ ] API deprecation 대응: 업그레이드 전 매니페스트 호환성 점검

### CKA 대비

- [ ] 시험 형식(원격 감독, 브라우저 터미널, 공식 문서만 열람 가능), 시간 배분 전략
- [ ] 속도 도구: `alias k=kubectl`, `--dry-run=client -o yaml`, `kubectl explain`, JSONPath, `-o custom-columns`
- [ ] 도메인별 약점 진단 → 반복
- [ ] ⚠️ **CKA 도메인 비중과 범위는 CNCF가 주기적으로 개정한다.** 응시 전 [공식 커리큘럼](https://github.com/cncf/curriculum)에서 최신 버전 확인 필수

## 실습 (labs/)

**W11 — VM 준비**

두 머신에서 명령이 동일하다. 게스트 아키텍처만 x86_64 / arm64로 갈리고 kubeadm 절차는 완전히 같다.

```bash
multipass launch --name cp1   --cpus 2 --memory 4G --disk 20G 24.04
multipass launch --name node1 --cpus 2 --memory 4G --disk 20G 24.04
multipass launch --name node2 --cpus 2 --memory 4G --disk 20G 24.04
```

- **기존 Ansible 자산을 활용해 노드 사전 준비를 자동화** → [`clusters/`](../clusters/) 에 플레이북 작성
- kubeadm으로 3노드 클러스터 구축, CNI 설치
- MetalLB 설치 후 LoadBalancer 타입 Service 실제 동작 확인
- 관통 프로젝트를 이 클러스터로 이전
- HA 실습(cp 3 + worker 2)까지 하려면 워커 메모리를 2G로 낮춰 총 20GB 내로 맞춘다

**W12**
- etcd 스냅샷 저장 → 클러스터를 망가뜨림 → 복구
- n-1 → n 버전 업그레이드 (컨트롤 플레인 → 워커)
- 인증서 만료 상황 재현 후 갱신
- killer.sh 등 모의고사로 시간 압박 훈련

## 완료 기준

- [ ] 문서 없이 kubeadm 클러스터를 40분 내 구축
- [ ] 컨트롤 플레인 Pod들이 static pod로 뜨는 것을 파일 경로까지 확인
- [ ] 노드가 `NotReady` 인 이유가 CNI 미설치임을 스스로 진단
- [ ] etcd 스냅샷으로 클러스터를 실제로 복구
- [ ] n-1 → n 업그레이드를 서비스 무중단으로 완료
- [ ] 모의고사 80% 이상 (미달 시 다음 단계를 미루고 보강)
- [ ] **CKA 응시** (또는 응시일 확정)

## 셀프 체크

1. `kubeadm init` 이 수행하는 일을 단계별로 설명할 수 있는가?
2. 컨트롤 플레인을 static pod로 띄우는 구조는 어떤 "닭과 달걀" 문제를 해결하는가?
3. etcd 스냅샷을 복구할 때 API 서버를 먼저 멈춰야 하는 이유는?
4. 클러스터 업그레이드에서 컨트롤 플레인을 워커보다 먼저 올리는 이유는? 반대로 하면 무슨 일이 생기는가?
5. 노드를 join했는데 `NotReady` 다. CNI 미설치 말고 또 어떤 원인이 있으며 각각 어떻게 구분하는가?
