# 학습 환경 구축 (두 머신 공통)

> W1에서 1회 수행. 이후 머신을 바꿀 때마다 이 문서만 따라가면 동일한 환경이 된다.
> 확인 시점: 2026-08-12 / kind 최신 릴리스 v0.32.0

## 설치 대상

| 도구 | 용도 | 필요 시점 |
|---|---|---|
| 컨테이너 런타임 | kind의 기반 | W1 |
| kubectl | 모든 조작 | W1 (머신 A는 v1.36.1 설치됨) |
| kind | 로컬 멀티노드 클러스터 | W1 |
| helm | 차트 배포 | W1 설치, W8부터 본격 사용 |
| k9s | 클러스터 TUI 탐색 | W1 |
| stern | 다중 Pod 로그 추적 | W1 |
| multipass | 온프렘 VM | **W11에 설치** (지금은 불필요) |

kustomize는 kubectl에 내장(`kubectl kustomize`)되어 별도 설치하지 않는다.

---

## 머신 A — Ubuntu 24.04 (x86_64)

컨테이너 런타임과 kubectl은 이미 설치되어 있다. 나머지만 설치한다.

```bash
# kind — 최신 릴리스를 조회해 설치
KIND_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
  | grep -Po '"tag_name": "\K[^"]*')
curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
sudo install -m 0755 /tmp/kind /usr/local/bin/kind

# helm — 공식 설치 스크립트 (내부에서 sudo 사용)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# k9s
K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
  | grep -Po '"tag_name": "\K[^"]*')
curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
  | tar xz -C /tmp k9s
sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s

# stern — go가 설치되어 있어 go install이 가장 간단 (~/go/bin이 PATH에 있어야 함)
go install github.com/stern/stern@latest
```

> `sudo` 가 필요한 명령은 위 4줄(`install`, helm 스크립트)뿐이다. 전역 설치를 피하고 싶다면
> `/usr/local/bin` 대신 `~/.local/bin` 에 넣고 PATH에 추가해도 된다.

## 머신 B — macOS (Apple Silicon / M4)

Homebrew로 전부 처리한다. **아키텍처를 지정할 필요가 없다** — brew가 arm64 빌드를 설치한다.

```bash
# 컨테이너 런타임 — 둘 중 하나 선택
brew install --cask orbstack     # 권장: M4에서 가볍고 빠름, kind와 잘 맞음
# brew install colima docker     # 대안: 완전 오픈소스. 설치 후 `colima start`

# 나머지 도구
brew install kubernetes-cli kind helm k9s stern
```

Colima를 선택했다면 kind를 쓰기 전에 VM을 먼저 띄운다. 메모리는 넉넉히 준다.

```bash
colima start --cpu 4 --memory 8 --disk 60
```

---

## 설치 검증

두 머신에서 동일하게 실행해 모두 버전이 출력되면 성공이다.

```bash
for c in docker kubectl kind helm k9s stern; do
  printf "%-8s: " "$c"
  command -v "$c" >/dev/null 2>&1 && "$c" version --short 2>/dev/null | head -1 || echo "확인 필요"
done
```

`version --short` 를 지원하지 않는 도구가 있으므로, 실패하면 `<도구> version` 으로 개별 확인한다.

---

## 아키텍처 차이 대응

두 머신은 x86_64 / arm64로 갈리지만 **kubectl·kind·helm 명령과 매니페스트는 완전히 동일**하다.
차이가 드러나는 지점은 이미지뿐이다.

- kind 노드 이미지(`kindest/node`)는 멀티아키라 자동으로 맞는 것이 받아진다
- **직접 빌드한 앱 이미지**는 빌드한 머신의 아키텍처를 따른다
  - 각 머신에서 로컬 빌드 → 신경 쓸 필요 없음 (기본 방식)
  - 레지스트리로 공유하려면 멀티아키 빌드:
    ```bash
    docker buildx build --platform linux/amd64,linux/arm64 -t <repo>:<tag> --push .
    ```
- arm64 이미지를 제공하지 않는 서드파티 차트를 만나면 대체 도구를 쓰거나 해당 실습만 머신 A에서 진행한다.
  `--platform linux/amd64` 강제는 에뮬레이션이라 매우 느리므로 권하지 않는다

## 문제 발생 시 기록

설치 중 막힌 지점과 해결 방법을 아래에 덧붙인다. 머신을 옮길 때 그대로 재사용한다.

<!-- 예: 2026-08-13 머신B / colima start 실패 → disk 부족, --disk 60으로 재생성 -->
