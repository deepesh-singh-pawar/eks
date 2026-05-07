# Architecture: Minimal, Cost-Aware AWS EKS (Terraform)

This repository models a **small but realistic** Kubernetes platform similar to how many teams start in AWS: Terraform owns the VPC and EKS “platform layer,” Helm installs AWS-specific controllers after the cluster exists, and plain manifests describe an application Ingress.

The design biases toward:

- **Cost control**: two managed nodes + **one NAT Gateway** (fewer gateways than subnets).
- **Beginner comprehension**: fewer files and fewer moving parts than a large enterprise scaffold.
- **Interview clarity**: everything maps to diagrams you can draw on a whiteboard in under five minutes.

---

## Bird’s-eye Diagram (What exists where)

Internet clients hit an **Application Load Balancer (ALB)** created by the AWS Load Balancer Controller. The ALB lives in **public subnets** because it fronts user traffic. Pods run on **managed worker nodes** in **private subnets** (no inbound from the Internet). Outbound pulls (ECR, AWS APIs, public charts) egress via **one NAT Gateway** placed in **the first Availability Zone**.

```mermaid
flowchart LR
  user[Internet user] --> alb[AWS ALB]
  alb -->|target groups| pod[Pods on nodes]
  pod --> svc[Kubernetes Service ClusterIP]
  subgraph PublicSubnets["Public subnets (2 AZs)"]
    igw[Internet Gateway]
    nat[NAT Gateway (single AZ)]
    alb
  end
  subgraph PrivateSubnets["Private subnets (2 AZs)"]
    pod
    eks[Managed nodes]
    cp[EKS Control Plane endpoints]
  end
  alb --> igw
  eks --> nat --> igw
  pod -. uses .-> eks
```

**Tradeoff interview line** (say this explicitly):

- **Single NAT Gateway** saves money versus one NAT per AZ but creates an **availability story**: if NAT’s AZ suffers an outage affecting that path, outbound traffic from subnets that route through NAT can be degraded. Many teams accept this in dev/low environments; prod often uses multiple NAT gateways or egress-only VPC endpoints depending on posture.

---

## Every Terraform File (What it owns and why)

All Terraform lives in `terraform/`.

### `versions.tf`

- Pins Terraform and provider versions (`aws`, `tls`) so collaborators (and CI) don’t silently drift capabilities.
- Declares **`backend "s3" {}`** for **remote state** (actual bucket/table are supplied via `terraform init -backend-config=backend.hcl`).

### `providers.tf`

- Defines the **`aws`** provider with **`default_tags`**, which merges your `common_tags` map (`Project`, `Environment`, `ManagedBy`, etc.) onto supported resources consistently.

### `variables.tf`

- Centralizes knobs you’re likely to tweak in demos: **`aws_region`**, **`cluster_name`**, **`kubernetes_version`**, node sizes/counts, and **API exposure** constraints.

### `terraform.tfvars.example`

- A copy/paste starter for **`terraform.tfvars`** (normally gitignored) so newcomers know what locals should look like without reading every variable definition.

### `backend.hcl.example`

- Backend parameters for **`terraform init -backend-config=backend.hcl`**: encrypted S3 state + DynamoDB pessimistic locking.

### `vpc.tf`

- **`aws_vpc`**: allocates an isolated IPv4 space (`vpc_cidr`).
- **Public subnets** + **Internet Gateway** + **`0.0.0.0/0` routes**: default path for ingress-capable subnets.
- **`aws_eip` + `aws_nat_gateway`**: a **single egress path** placed in **`public[0]`** — this is intentional cost trimming.
- **Private subnets**: route **`0.0.0.0/0`** to the NAT.
- Subnet tagging includes `kubernetes.io/cluster/<name>` and ELB-facing tags (`kubernetes.io/role/elb` / internal variant) — these help AWS tooling choose subnets for controllers that provision load balancers.

### `security_groups.tf`

Two explicit security groups for a crisp interview explanation:

1. **`cluster` SG attaches to `aws_eks_cluster`**: allows node-to-API-plane traffic semantics your lesson can reference.
2. **`node` SG attaches to EC2 worker instances via launch template**: allows node-to-node traffic and egress.

This avoids “everything is default SG” vagueness during interviews — you can articulate **who talks to whom** on which ports/tuples.

### `eks.tf`

- **IAM Roles + Trust Policies**: `AmazonEKSClusterPolicy` binds to the **cluster IAM role**; managed nodes attach **`AmazonEKSWorkerNodePolicy`**, **`AmazonEKS_CNI_Policy`**, and **`AmazonEC2ContainerRegistryReadOnly`**.
- **`aws_eks_cluster`**: chooses subnets spanning private + public (control plane attachments + flexibility), configures **private and public kube-apiserver access** knobs.
- **`aws_eks_node_group`**: launches **exactly two managed nodes by default**, `ON_DEMAND`, `AL2_x86_64`.
- **`aws_launch_template`**: pins **explicit node security group**, **gp3 disks**, **IMDSv2 required** (`http_tokens`) — inexpensive hardening baseline.

### `iam_alb_controller.tf`

Kubernetes pods should not inherit the union of **node IAM** permissions for unrelated AWS APIs — **IAM Roles for Service Accounts (IRSA)** fixes that pattern.

1. Registers an **`aws_iam_openid_connect_provider`** for the Kubernetes service-account issuer (**TLS thumbprint handshake** verifies trust).
2. Creates an **`aws_iam_role`** whose **`sts:AssumeRoleWithWebIdentity`** trust only matches the **`kube-system/aws-load-balancer-controller`** service account subject.
3. Attaches **`policies/alb_controller_iam_policy.json`**, the upstream-style policy set for provisioning ALBs + target groups + related EC2/elbv2 lifecycle calls.

Interview talking point:

- OIDC binds **digital signatures** emitted by Kubernetes to **AWS STS** principals; annotated service accounts mint **temporary creds**.

### `ecr.tf`

- **`aws_ecr_repository`** for the `./app/Dockerfile` story.
- A **lifecycle policy** keeps abandoned image layers from quietly growing storage bills.

### `outputs.tf`

- Convenience strings for kubectl config, Helm/IRSA annotations, VPC/subnet auditing, ECR pushes.

---

## Networking Flow (From laptop to Pods)

### Outbound-from-Pods / Nodes (NAT path)

Pods on nodes typically need:

- kube-apiserver access (mostly via private endpoint path when enabled),
- pulls from **ECR**,
- STS/IAM credential exchanges for IRSA,
- DNS and other SaaS integrations.

Except for traffic that stays inside the VPC, **east-west workload traffic** crosses the node networking stack managed by VPC CNI, while **general Internet egress for private subnets** follows:

`Pod → Node → NAT Gateway → Internet Gateway`

### Ingress from Clients (ALB path)

For this repo’s Ingress:

The **AWS Load Balancer Controller** reads your **Ingress resource** annotations and subnets tags, allocates an **internet-facing Application Load Balancer** in tagged public subnets, creates **listeners/target groups**, registers **healthy Pod IPs** (because `alb.ingress.kubernetes.io/target-type: ip`), and attaches security groups/route tables implicitly through AWS semantics.

Client path:

`Client → ALB (public subnet) → Node ENI / Pod IP (private) → Service → Pod`

---

## EKS Setup (What AWS runs vs what you run)

### AWS-managed

- **Kubernetes control plane** (API server, etcd, scheduler, controller-manager) — you pay the **EKS hourly control-plane charge** (not Free Tier).
- **Managed node group** lifecycle for EC2 behind the scenes.

### You-managed (this repo)

- VPC + routing + NAT design (directly affects **monthly platform cost**).
- IRSA role for the ALB controller (good security hygiene story).
- Kubernetes YAML for the sample app (application layer).

---

## Ingress + AWS Load Balancer Controller

**Controller responsibility**: watches **Ingress**, **IngressClass**, and related AWS-specific CRDs/services; translates desired routes into ELBv2 primitives.

### Why Helm for the controller (not Terraform here)

Provisioning the controller cleanly from Terraform commonly requires Helm/Kubernetes providers configured against a potentially brand-new endpoint; that’s workable, but brittle for newcomers’ first **`terraform apply`**.

Instead, Terraform creates the IAM trust + role; **SETUP_GUIDE.md** installs Helm with an explicit **values** file so you can:

- show each layer in interviews,
- retry controller installs without re-planning the entire VPC.

### `helm/aws-load-balancer-controller-values.yaml`

Ties Helm inputs to Terraform outputs (`clusterName`, `region`, `vpcId`, `serviceAccount.annotations` IRSA ARN).

Manifest `kubernetes/ingress.yaml` sets:

- **`ingressClassName: alb`** (created by Helm install by default pattern),
- **internet-facing** scheme,
- **IP targets** annotation for typical pod-backed services.

---

## Kubernetes Manifest Walkthrough (`kubernetes/`)

- **`namespace.yaml`**: namespaces isolate RBAC/policy evolution and show “production hygiene” starters.
- **`deployment.yaml`**: declares **desired replicas**, pod template identity labels, containers/ports — default image is **upstream nginx** so you can `kubectl apply` before ECR; swap to **`terraform output ecr_repository_url`** after your build/push.
- **`service.yaml`**: **`ClusterIP`** fronts stable DNS inside the cluster; Ingress references this Service.
- **`ingress.yaml`**: external HTTP entry using AWS annotations understood by AWS Load Balancer Controller.

---

## Sample Application (`app/`)

The **`Dockerfile`** copies a trivial static page into **`nginx:alpine`**. Interview narrative:

**Build artifact → immutable tag → scanned ECR repo → Deployment references digest/tag** promotes supply-chain conversations without requiring a heavyweight Node toolchain.

---

## End-to-End Traffic Story (Elevator Pitch)

You can compress the flow to five sentences:

1. Terraform builds a VPC with **two public subnets** (for LB + NAT ingress/egress) and **two private subnets** for workers.
2. EKS control plane attaches into that VPC topology; worker nodes reside privately and egress through **single NAT**.
3. IRSA binds the ALB controller pod identity to a least-privilege IAM role.
4. Helm installs the controller; your **Ingress** becomes an **ALB** with rules.
5. The Service selects Pods; the ALB target group health-checks Pod endpoints through the node network path.

---

## Interview Explanation Points (High Signal / Low Memorization Burden)

### Platform

- **Why private workers?** Reduce attack surface; no SSH/Internet-reachable kubelet ports by default pattern.
- **Why NAT at all (vs endpoints-only)?** Small learning clusters commonly use NAT for simplicity; mature orgs mix **VPC endpoints** (ECR/STS/S3/etc.) to reduce data-processing charges and tighten egress posture.
- **What’s still “expensive” in this design?** EKS control plane + NAT Gateway + ALB hours + data processing — calling these out signals cost literacy.

### Security

- **IRSA vs node IAM**: node role can stay smaller; compromised workload doesn’t automatically mean “same power as AWS LB controller IAM.”
- **IMDSv2 on nodes**: blocks trivial metadata abuse classes from naive lateral movement patterns.
- **API public endpoint CIDR tightening**: swap `0.0.0.0/0` to your **`/32`** for real life.

### Operations

- **Managed node groups vs Karpenter/Fargate**: this repo picks **managed nodes** because it’s easiest to explain EC2-backed networking + costs in interviews without autoscaler domain depth.
- **Two replicas + two AZ subnets**: demonstrates **scheduler spreading** vocabulary (not a guarantee — but a realistic starting posture).

---

## What This Repo Intentionally Does *Not* Include

- GitOps (Argo CD/Flux), service mesh, multi-cluster federation, progressive delivery, enterprise policy engines.
- Many layers of IAM guardrails / SCPs / centralized logging — you can bolt these on once the base mental model sticks.

Those omissions are **scope control**, not recommendations against them in mature orgs.
