# Clusters — 클러스터 구성

여러 단계가 공유하는 클러스터 구성을 모아둔다. 단계별 일회성 매니페스트는 각 단계의 `labs/` 에 둔다.

```
clusters/
├── kind/
│   └── study-cluster.yaml    # 3노드 로컬 클러스터 (00단계부터 계속 사용)
└── kubeadm/                  # 04단계의 기반 — Multipass VM 위 kubeadm 클러스터
    ├── README.md             # 구축 절차와 트러블슈팅 (실측 검증됨)
    ├── scripts/              # 00-create-vms.sh(호스트) + 00~03 (노드 안)
    └── ansible/              # 호스트에서 실행하는 반복 훈련용 플레이북
```

> kubeadm 설치의 **이유와 개념**은 [`00-setup/notes/kubeadm-setup.md`](../00-setup/notes/kubeadm-setup.md),
> **실행 방법**은 [`kubeadm/README.md`](kubeadm/README.md) 에 있다.

## kind

```bash
kind create cluster --config clusters/kind/study-cluster.yaml
kind delete cluster --name study
```

호스트 포트 8080/8443이 컨트롤 플레인 노드로 매핑되어 있다. **포트 매핑은 클러스터 생성 시에만
지정할 수 있어**, 02단계의 Ingress 실습을 위해 미리 넣어두었다.

02단계에서 ingress-nginx를 설치할 때 컨트롤러를 이 노드에 고정하려면 라벨이 필요하다.
`kubeadmConfigPatches` 로도 넣을 수 있으나 kubeadm API 버전에 따라 형식이 달라지므로,
버전에 의존하지 않는 방식으로 그때 직접 붙인다:

```bash
kubectl label node study-control-plane ingress-ready=true
```

## kubeadm (04단계)

**Multipass**로 VM을 띄우고, 스크립트(`scripts/`) 또는 Ansible(`ansible/`)로 kubeadm 클러스터를 구축한다.
자세한 절차는 [`kubeadm/README.md`](kubeadm/README.md) 참조 (macOS M4에서 실제 구축·검증했다).

```bash
cd clusters/kubeadm/scripts
./00-create-vms.sh          # VM 생성 + 네트워크/CIDR 검증 (호스트에서)
# 이후 00~03 을 노드에서 실행 — kubeadm/README.md 참조
```

> **Multipass 기본 NAT 모드로 충분하다.** 노드 간 통신과 크로스노드 Pod 통신(Calico VXLAN)이
> 모두 동작하고, MAC이 고정되어 재부팅해도 IP가 유지된다 — 실측 확인했다.
> UTM은 `utmctl`에 `create`가 없어 VM 생성 자동화가 불가능하므로 이 리포는 Multipass를 쓴다.
> VM과 클러스터는 각 머신에서 새로 만든다. Git으로는 **재현 가능한 코드와 문서만** 동기화한다.
