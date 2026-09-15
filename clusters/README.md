# Clusters — 클러스터 구성

여러 단계가 공유하는 클러스터 구성을 모아둔다. 단계별 일회성 매니페스트는 각 단계의 `labs/` 에 둔다.

```
clusters/
├── kind/
│   └── study-cluster.yaml    # 3노드 로컬 클러스터 (00단계부터 계속 사용)
└── kubeadm/                  # 04단계의 기반 — UTM VM 위 kubeadm 클러스터
    ├── README.md             # 구축 절차와 트러블슈팅
    ├── scripts/              # VM 안에서 실행하는 설치 스크립트 (공통/CP/워커/검증)
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

UTM 또는 Multipass로 VM을 띄우고, 스크립트(`scripts/`) 또는 Ansible(`ansible/`)로 kubeadm 클러스터를 구축한다.
자세한 절차는 [`kubeadm/README.md`](kubeadm/README.md) 참조.

VM 생성 명령은 두 머신(Ubuntu / macOS)에서 동일하다.

```bash
multipass launch --name cp1   --cpus 2 --memory 4G --disk 20G 24.04
multipass launch --name node1 --cpus 2 --memory 4G --disk 20G 24.04
multipass launch --name node2 --cpus 2 --memory 4G --disk 20G 24.04
```

> UTM을 쓴다면 네트워크 모드를 **Bridged**로 두어야 VM끼리 IP로 통신하고 호스트에서 SSH로 접속할 수 있다.
> VM과 클러스터는 각 머신에서 새로 만든다. Git으로는 **재현 가능한 코드와 문서만** 동기화한다.
