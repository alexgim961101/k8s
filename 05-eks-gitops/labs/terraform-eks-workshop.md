# Terraform으로 EKS를 한 단계씩 구축하기

> 목표: Terraform 파일과 AWS 명령을 **한 블록씩 직접 입력**하여 EKS의 구성 요소를 확인한다.
>
> 범위: 전용 VPC → private subnet/NAT → EKS control plane → Managed Node Group → access entry → 기본 add-on → `kubectl` 검증 → 삭제. ALB·Pod Identity·Argo CD는 이 클러스터를 재현한 다음 단계다.

## 실습 규칙

- 이 프로젝트의 `05-eks-gitops/labs/terraform-eks/`에 실습 Terraform 코드를 남긴다. 운영 IaC와 state는 재사용하지 않고, 전용 key `k8s-learning/eks-lab/terraform.tfstate`를 사용한다.
- AWS 콘솔은 Terraform 결과를 **관찰**하는 용도다. 리소스를 콘솔에서 만들거나 지우지 않는다.
- 코드 한 블록을 입력하면 `terraform fmt` → `terraform validate` → `terraform plan` 순으로 확인한다. plan의 대상과 비용을 설명할 수 있을 때만 `apply`한다.
- 끝나면 반드시 `terraform destroy` 한다. EKS control plane, NAT Gateway, EC2 node, public IPv4, log는 과금된다.

## 0. 계정과 도구를 확인한다

이 저장소의 루트에서 아래 명령을 **각각** 실행한다.

```bash
cd /home/lotto/src/k8s
```

```bash
terraform version
```

```bash
aws --version
```

```bash
kubectl version --client
```

```bash
aws sts get-caller-identity
```

마지막 출력의 Account가 학습용 계정인지 확인한다. ARN이 `assumed-role/...`이면 그 STS session ARN은 access entry에 넣지 않는다. 세션을 발급한 IAM role ARN(또는 IAM user ARN)을 사용한다. AWS Budgets의 월 예산 알림도 실습 전에 설정한다.

## 1. 전용 Terraform 환경을 만든다

다음 구조를 직접 만든다. 이 경로 밖의 운영 Terraform 환경을 복사하거나 수정하지 않는다.

```text
05-eks-gitops/labs/terraform-eks/
├── backend.hcl.example       # Git 추적
├── terraform.tfvars.example  # Git 추적
├── main.tf
├── variables.tf
├── outputs.tf
├── modules/network/main.tf
├── modules/eks/main.tf
└── .gitignore
```

먼저 저장소 루트에서 실습 root를 만들고 이동한다.

```bash
mkdir -p 05-eks-gitops/labs/terraform-eks
```

```bash
cd 05-eks-gitops/labs/terraform-eks
```

`backend.hcl.example` — 이 예시는 Git에 남기고, 본인 계정에서만 `backend.hcl`로 복사해 값을 입력한다.

```hcl
bucket         = "<your-terraform-state-bucket>"
key            = "k8s-learning/eks-lab/terraform.tfstate"
region         = "<state-bucket-region>"
dynamodb_table = "<terraform-lock-table>"
encrypt        = true
```

`main.tf` — 아직 리소스는 만들지 않는다.

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Environment = "lab"
    ManagedBy   = "Terraform"
    Purpose     = "eks-learning"
  }
}
```

실습 후에도 예시를 재사용할 수 있게 `backend.hcl.example`을 Git에 남긴 뒤, 로컬 파일을 만든다.

```bash
cp backend.hcl.example backend.hcl
```

`variables.tf` — access entry 대상은 하드코딩하지 않는다.

```hcl
variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}
variable "cluster_admin_principal_arn" { type = string }
variable "api_server_public_access_cidrs" { type = list(string) }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "kubernetes_version" { type = string }
```

`terraform.tfvars.example`은 Git에 남기는 예시다. 이를 `terraform.tfvars`로 복사한 뒤 개인 값을 넣으며, 실제 파일은 `.gitignore`로 제외한다.

```hcl
cluster_admin_principal_arn    = "arn:aws:iam::<account-id>:role/<your-admin-role>"
api_server_public_access_cidrs = ["<your-public-ip>/32"]
kubernetes_version             = "<AWS가 현재 지원하는 버전>"

vpc_cidr             = "10.250.0.0/16"
availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
public_subnet_cidrs  = ["10.250.0.0/24", "10.250.1.0/24"]
private_subnet_cidrs = ["10.250.10.0/24", "10.250.11.0/24"]
```

`terraform.tfvars.example`도 Git에 남긴 뒤 로컬 파일을 만든다.

```bash
cp terraform.tfvars.example terraform.tfvars
```

현재 지원되는 Kubernetes version은 실습 당일 AWS EKS 공식 문서 또는 콘솔에서 확인한다. `0.0.0.0/0`를 public API endpoint CIDR로 넣지 않는다. CIDR도 기존 VPC와 겹치지 않는지 확인한다.

```bash
terraform init -backend-config=backend.hcl
```

```bash
terraform fmt -recursive
```

```bash
terraform validate
```

```bash
terraform plan -var-file=terraform.tfvars
```

아직 `No changes`가 정상이다.

## 1-1. Git에 남길 실습 코드의 뼈대를 만든다

실습 코드의 기준 경로는 이 프로젝트의 `05-eks-gitops/labs/terraform-eks/`다. `.tf`, `.terraform.lock.hcl`, `backend.hcl.example`, `terraform.tfvars.example`는 Git에 남긴다. 계정별 `backend.hcl`, `terraform.tfvars`, state와 `.terraform/`만 Git에서 제외한다.

~~~bash
mkdir -p 05-eks-gitops/labs/terraform-eks/modules/network
~~~

~~~bash
mkdir -p 05-eks-gitops/labs/terraform-eks/modules/eks
~~~

`05-eks-gitops/labs/terraform-eks/.gitignore`을 직접 만든다.

~~~gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!terraform.tfvars.example
backend.hcl
crash.log
~~~

이제 `modules/network/main.tf`에 먼저 아래의 VPC 기본 구조를 입력한다. 다음 2단계에서 subnet 태그와 NAT/private route를 이 파일에 추가한다.

~~~hcl
variable "name" { type = string }
variable "cidr_block" { type = string }
variable "azs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "tags" { type = map(string) }

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge({ Name = var.name }, var.tags)
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge({ Name = "${var.name}-igw" }, var.tags)
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge({ Name = "${var.name}-public-${var.azs[count.index]}" }, var.tags)
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge({ Name = "${var.name}-private-${var.azs[count.index]}" }, var.tags)
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge({ Name = "${var.name}-public-rt" }, var.tags)
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id       = aws_subnet.public[count.index].id
  route_table_id  = aws_route_table.public.id
}

output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
~~~

## 2. private subnet의 outbound 경로를 만든다

방금 만든 `05-eks-gitops/labs/terraform-eks/modules/network/main.tf`의 기본 구조는 private subnet을 만들지만 private route/NAT Gateway는 아직 만들지 않는다. EKS node가 private subnet에서 ECR과 add-on image를 읽으려면 outbound 경로가 필요하다. 학습용은 NAT Gateway 1개(비용 절약, AZ 장애에는 취약)를 쓴다. 운영에서는 AZ별 NAT 또는 VPC endpoint를 따로 설계한다.

### 2-1. VPC module에 입력을 추가한다

`05-eks-gitops/labs/terraform-eks/modules/network/main.tf`의 variable 구역에 아래 세 블록을 입력한다.

```hcl
variable "enable_nat_gateway" {
  type    = bool
  default = false
}
variable "public_subnet_tags" {
  type    = map(string)
  default = {}
}
variable "private_subnet_tags" {
  type    = map(string)
  default = {}
}
```

기존 `aws_subnet.public`의 `tags = merge(...)`에 `var.public_subnet_tags`를, `aws_subnet.private`에는 `var.private_subnet_tags`를 마지막 인자로 추가한다. `Name`과 공통 `var.tags`는 지우지 않는다.

### 2-2. NAT와 private route를 추가한다

`05-eks-gitops/labs/terraform-eks/modules/network/main.tf`에서 private subnet resource 아래에 아래 리소스를 차례대로 넣는다.

```hcl
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge({ Name = "${var.name}-nat-eip" }, var.tags)
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.this]
  tags          = merge({ Name = "${var.name}-nat" }, var.tags)
}

resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge({ Name = "${var.name}-private-rt" }, var.tags)
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count         = var.enable_nat_gateway ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
```

`count = 0`일 때 NAT 리소스가 생기지 않는다는 것을 plan으로 먼저 이해한다.

### 2-3. lab에서 VPC를 호출한다

lab `main.tf`에 VPC module 호출을 추가한다. 아직 EKS module은 추가하지 않는다.

```hcl
module "vpc" {
  source = "./modules/network"

  name                 = "eks-lab"
  cidr_block           = var.vpc_cidr
  azs                  = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  tags = local.common_tags
}
```

```bash
terraform fmt -recursive
```

```bash
terraform validate
```

```bash
terraform plan -var-file=terraform.tfvars
```

plan에 VPC, IGW, 2 public/2 private subnet, EIP, NAT, route table가 있고 EKS는 없는지 읽는다. NAT 비용을 이해한 뒤에만 적용한다.

```bash
terraform apply -var-file=terraform.tfvars
```

AWS route table에서 private subnet의 기본 경로가 NAT로, public subnet의 기본 경로가 IGW로 향하는지 관찰한다.

## 3. EKS module을 구성 요소별로 작성한다

`05-eks-gitops/labs/terraform-eks/modules/eks/main.tf`와 `05-eks-gitops/labs/terraform-eks/modules/eks/outputs.tf`를 만든다. 첫 실습은 공개 EKS module을 호출하지 않는다. cluster role, node role, control plane, node group을 직접 선언해 책임을 구분한다.

### 3-1. module의 입력과 control plane role

`main.tf` 상단:

```hcl
variable "name" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "admin_principal_arn" { type = string }
variable "api_server_public_access_cidrs" { type = list(string) }
variable "tags" { type = map(string) }

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
```

### 3-2. control plane과 access entry

`aws-auth` ConfigMap 대신 EKS API access entry를 선택한다.

```hcl
resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode = "API"
  }
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_server_public_access_cidrs
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  depends_on                = [aws_iam_role_policy_attachment.cluster]
  tags                      = var.tags
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
```

public endpoint는 실습 편의를 위한 선택이고 CIDR으로 제한한다. 운영 설계에서는 private endpoint와 VPN/bastion/SSM 접속 경로를 따로 결정한다.

### 3-3. node role과 managed node group

node가 Kubernetes에 join하고 VPC CNI를 사용하며 ECR image를 읽도록 IAM policy 3개를 붙인다.

```hcl
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]
  ami_type        = "AL2023_x86_64_STANDARD"
  scaling_config {
    min_size     = 1
    desired_size = 2
    max_size     = 3
  }
  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = var.tags
}
```

### 3-4. add-on과 output

```hcl
resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}
```

`05-eks-gitops/labs/terraform-eks/modules/eks/outputs.tf`:

```hcl
output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_certificate_authority_data" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}
```

## 4. lab 환경에 EKS module을 연결하고 적용한다

lab `main.tf`에 아래를 추가한다.

```hcl
module "eks" {
  source = "./modules/eks"

  name                           = "eks-lab"
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = module.vpc.vpc_id
  private_subnet_ids             = module.vpc.private_subnet_ids
  admin_principal_arn            = var.cluster_admin_principal_arn
  api_server_public_access_cidrs = var.api_server_public_access_cidrs
  tags                           = local.common_tags
}
```

lab `outputs.tf`에 추가한다.

```hcl
output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
```

명령을 하나씩 실행한다. plan에서 기존 VPC 리소스가 replace되지 않는지, access entry ARN이 의도한 IAM principal인지 확인한다.

```bash
terraform init
```


```bash
terraform fmt -recursive
```

```bash
terraform validate
```

```bash
terraform plan -var-file=terraform.tfvars
```

```bash
terraform apply -var-file=terraform.tfvars
```

EKS는 수 분 걸린다. `CREATING → ACTIVE`와 node group 상태를 콘솔에서 관찰한다. control plane이 `ACTIVE`여도 node group은 별도로 기다려야 한다.

## 5. Kubernetes 관점으로 검증한다

```bash
terraform output cluster_name
```

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name eks-lab
```

```bash
kubectl config current-context
```

```bash
kubectl get nodes -o wide
```

```bash
kubectl get pods -n kube-system -o wide
```

```bash
kubectl auth can-i '*' '*' --all-namespaces
```

```bash
aws eks list-access-entries --cluster-name eks-lab --region ap-northeast-2
```

node가 `Ready`가 아니면 앱을 배포하지 않는다. EKS node group health와 `kubectl get events -A --sort-by=.lastTimestamp`를 읽는다. 우선 확인할 대상은 private route/NAT, node IAM policy, API endpoint CIDR, AZ capacity다.

정상일 때만 smoke test를 한다.

```bash
kubectl create deployment hello --image=nginx:stable
```

```bash
kubectl rollout status deployment/hello --timeout=5m
```

```bash
kubectl get deployment,pods -l app=hello -o wide
```

```bash
kubectl delete deployment hello
```

## 6. 변경을 읽고, 완전히 정리한다

`aws_eks_node_group.default.scaling_config.desired_size`만 2에서 1로 바꾼다. `plan`의 in-place update와 replace의 차이를 읽은 뒤 apply하고, `kubectl get nodes -w`로 변화를 관찰한다. node role에 앱의 S3 권한을 붙이지 않는다. 다음 실습에서 전용 service account + Pod Identity(또는 IRSA)로 분리한다.

삭제 전 현재 경로와 workspace를 꼭 확인한다.

```bash
pwd
```

```bash
terraform workspace show
```

```bash
terraform plan -destroy -var-file=terraform.tfvars
```

destroy plan에 EKS cluster, managed node group, NAT Gateway, EIP, VPC가 모두 보일 때만 실행한다.

```bash
terraform destroy -var-file=terraform.tfvars
```

```bash
terraform state list
```

```bash
aws eks list-clusters --region ap-northeast-2
```

```bash
aws ec2 describe-nat-gateways --region ap-northeast-2 --filter Name=tag:Purpose,Values=eks-learning
```

state에 남은 항목이나 NAT/EIP가 있으면 콘솔에서 먼저 지우지 않는다. `terraform plan -destroy`와 state를 대조해 원인을 찾는다. 콘솔에서 수동 생성한 리소스만 Terraform 밖에서 별도 정리한다.

## 다음 실습

1. **EKS Pod Identity** — `aws-pod-identity-agent`, 전용 IAM role, service account로 S3 read-only Pod를 만든다.
2. **AWS Load Balancer Controller** — Pod 권한과 subnet tag를 바탕으로 Ingress가 ALB가 되는 흐름을 본다.
3. **GitOps** — Terraform은 AWS/EKS 기반까지만, 앱 desired state는 Argo CD가 Git에서 읽도록 책임을 분리한다.

## 참고 기준

- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [EKS managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Terraform AWS EKS module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) — 직접 만든 뒤 비교할 공개 module
