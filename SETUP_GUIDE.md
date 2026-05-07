# Setup Guide: Provision, Install Controllers, Deploy, Verify, Clean Up

**Convention:** Sections that vary by shell list **Bash / Linux / macOS / WSL** first, then **Windows PowerShell**. Many **Terraform**, **kubectl**, **Helm**, and **AWS CLI** commands are identical in both — duplicated blocks avoid guesswork when you skim the doc.

Adjust account IDs, regions, and CIDRs deliberately — don’t copy-paste blindly into production.

---

## 0) What you’ll pay for (so “destroy” later)

Even a “small” EKS lab can bill for:

- **EKS control plane** hourly charge.
- **NAT Gateway** hourly + **data processing**.
- **Managed worker EC2** instances (this repo defaults to **two `t3.small`** nodes).
- **ALB** hourly + LCU usage (after you create an Ingress).
- **Elastic IP** attached to NAT (small, but real).
- **ECR** storage (images/layers).

Nothing here is financial advice — treat every hour as training budget.

---

## Part A — AWS Prerequisites

### A1) AWS account basics

- **AdministratorAccess** (simplest for learning) **or** a narrower policy that still allows: VPC, EC2, EKS, IAM (`iam:CreateRole`, `iam:CreatePolicy`, `iam:AttachRolePolicy`, OIDC provider), ECR, ELBv2, STS.
- **Billing alarms** (recommended): CloudWatch billing alarm or AWS Budgets notification.

### A2) Tooling you must install locally

- **Terraform** `>= 1.5` (`terraform version`).
- **AWS CLI v2** (`aws --version`).
- **`kubectl`** aligned with your cluster minor version (`kubectl version --client`).
- **`helm`** `v3` (`helm version`).
- **Docker Desktop** (or Docker Engine) if you want the full **ECR push** story.

### A3) AWS CLI authentication

Examples:

- **SSO**:

```bash
aws configure sso
aws sts get-caller-identity
```

- **Named profile static keys** (least recommended but common in labs):

**Bash / Linux / macOS / WSL:**

```bash
aws configure --profile eks-learning
export AWS_PROFILE=eks-learning
aws sts get-caller-identity
```

**Windows PowerShell:**

```powershell
aws configure --profile eks-learning
$env:AWS_PROFILE = "eks-learning"
aws sts get-caller-identity
```

---

## Part B — Remote Terraform Backend (S3 + DynamoDB locks)

### B1) Choose names

You need:

- **Globally unique S3 bucket** for state.
- **DynamoDB table** with **partition key** `LockID` (string).

### B2) Create the bucket (AWS CLI examples)

**If your region is `us-east-1` (no `LocationConstraint`):**

```bash
export AWS_REGION=us-east-1
export TF_BUCKET=your-company-eks-learning-tfstate-12345
export TF_LOCK_TABLE=eks-learning-tf-locks

aws s3api create-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION"
```

**If your region is NOT `us-east-1`:**

```bash
export AWS_REGION=us-west-2
export TF_BUCKET=your-company-eks-learning-tfstate-12345
export TF_LOCK_TABLE=eks-learning-tf-locks

aws s3api create-bucket --bucket "$TF_BUCKET" --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
```

**Hardening typical for state buckets (run after create):**

```bash
aws s3api put-bucket-versioning --bucket "$TF_BUCKET" --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$TF_BUCKET" --server-side-encryption-configuration '{
  "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
}'

aws s3api put-public-access-block --bucket "$TF_BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### B3) Create the DynamoDB lock table

```bash
aws dynamodb create-table \
  --table-name "$TF_LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### B4) Wire Terraform to the backend

Copy `terraform/backend.hcl.example` → `terraform/backend.hcl` and substitute real bucket/table names/region.

**Bash / macOS / Linux / WSL:**

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
# Edit values: bucket, key, region, dynamodb_table, encrypt
${EDITOR:-nano} terraform/backend.hcl
```

Initialize Terraform with backend config:

```bash
cd terraform
terraform init -backend-config=backend.hcl
cd ..
```

If you want **local-only state temporarily** while bootstrapping the bucket (still create the bucket/table first):

```bash
cd terraform
terraform init -backend=false
cd ..
```

**Windows PowerShell (same steps):**

```powershell
Copy-Item terraform/backend.hcl.example terraform/backend.hcl
notepad terraform/backend.hcl
```

```powershell
Push-Location terraform
terraform init -backend-config=backend.hcl
Pop-Location
```

```powershell
Push-Location terraform
terraform init -backend=false
Pop-Location
```

Interview note: **`encrypt=true`** protects state confidentiality at rest; **DynamoDB lock** avoids two humans/CI jobs corrupting shared state concurrently.

---

## Part C — Terraform: Plan and Apply Platform

### C1) Variables

Copy the example vars:

**Bash / Linux / macOS / WSL:**

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
${EDITOR:-nano} terraform/terraform.tfvars
```

**Windows PowerShell:**

```powershell
Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
notepad terraform/terraform.tfvars
```

Strongly recommended for realism (not openness-to-the-world):

```hcl
# Example: tighten kube-apiserver public exposure to ONLY your IP
cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
```

### C2) Plan and apply

**Bash / Linux / macOS / WSL:**

```bash
cd terraform
terraform fmt -recursive
terraform plan -out=tfplan
terraform apply tfplan
cd ..
```

**Windows PowerShell:**

```powershell
Push-Location terraform
terraform fmt -recursive
terraform plan -out=tfplan
terraform apply tfplan
Pop-Location
```

### C3) Record important outputs

**Bash / Linux / macOS / WSL:**

```bash
cd terraform
terraform output
cd ..
```

**Windows PowerShell:**

```powershell
Push-Location terraform
terraform output
Pop-Location
```

You’ll reuse:

- `aws_load_balancer_controller_role_arn`
- `vpc_id`
- `ecr_repository_url`
- `eks_kubeconfig_command`

---

## Part D — kubectl: Talk to Your Cluster

### D1) Update kubeconfig

Use Terraform’s `eks_kubeconfig_command` output or run the equivalents below (**change region/cluster name if you overrode vars**):

**Bash / Linux / macOS / WSL:**

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-learning
kubectl get nodes
kubectl get pods -A
```

**Windows PowerShell:**

```powershell
aws eks update-kubeconfig --region us-east-1 --name eks-learning
kubectl get nodes
kubectl get pods -A
```

If auth fails:

- Confirm **`AWS_PROFILE` / SSO session** freshness.
- Confirm your IAM principal matches what created the cluster (cluster creator retains admin semantics in typical setups).

---

## Part E — Helm: Install AWS Load Balancer Controller

### E1) Add the chart repo

**Bash / Linux / macOS / WSL:**

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

**Windows PowerShell:**

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

### E2) Fill Helm values placeholders

Open `helm/aws-load-balancer-controller-values.yaml` in an editor and replace the placeholder strings.

**Bash / Linux / macOS / WSL:**

```bash
${EDITOR:-nano} helm/aws-load-balancer-controller-values.yaml
```

**Windows PowerShell:**

```powershell
notepad helm/aws-load-balancer-controller-values.yaml
```

Substitute:

| Placeholder         | Typical source                                                                      |
|---------------------|-------------------------------------------------------------------------------------|
| `CLUSTER_NAME`      | Terraform output `eks_cluster_name`                                                 |
| `AWS_REGION`        | Terraform var `aws_region`                                                        |
| `VPC_ID`            | Terraform output `vpc_id`                                                           |
| `IRSA_ROLE_ARN`     | Terraform output `aws_load_balancer_controller_role_arn`                             |

### E3) Install the controller release

The controller commonly runs in **`kube-system`**.

**Bash / Linux / macOS / WSL:**

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --create-namespace \
  -f helm/aws-load-balancer-controller-values.yaml \
  --wait
```

**Windows PowerShell:**

```powershell
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system `
  --create-namespace `
  -f helm/aws-load-balancer-controller-values.yaml `
  --wait
```

Optional pinning (recommended once you pick a chart revision for your study notes):

**Bash / Linux / macOS / WSL:**

```bash
helm search repo eks/aws-load-balancer-controller --versions
```

**Windows PowerShell:**

```powershell
helm search repo eks/aws-load-balancer-controller --versions
```

Notes:

- Prefer **pinning a chart version** with `helm upgrade ... --version <CHART_SEMVER>` once you record it in your notes so your interview artifact does not float silently.
- If install fails IAM-wise, **`kubectl logs -n kube-system deploy/aws-load-balancer-controller`** is your first breadcrumb trail.

Verify:

**Bash / Linux / macOS / WSL:**

```bash
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get ingressclass
```

**Windows PowerShell:**

```powershell
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get ingressclass
```

Expect an **`alb`** IngressClass row if chart defaults survived.

---

## Part F — Application: Dockerfile → ECR (Optional but Recommended)

### F1) Authenticate Docker to ECR

**Bash / Linux / macOS / WSL:**

```bash
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "${REGION}" \
| docker login --username AWS --password-stdin "${REGISTRY}"
```

**Windows PowerShell:**

```powershell
$REGION = "us-east-1"
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$REGISTRY = "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region $REGION `
| docker login --username AWS --password-stdin $REGISTRY
```

### F2) Build and push

Retrieve repo URL explicitly if needed:

**Bash / Linux / macOS / WSL:**

```bash
cd terraform
ECR_REPO=$(terraform output -raw ecr_repository_url)
cd ..

cd app
docker build -t sample-eks:latest .
docker tag sample-eks:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"
cd ..
```

**Windows PowerShell:**

```powershell
Push-Location terraform
$ECR_REPO = terraform output -raw ecr_repository_url
Pop-Location

Push-Location app
docker build -t sample-eks:latest .
docker tag sample-eks:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"
Pop-Location
```

### F3) Point Kubernetes at your pushed image

Edit `kubernetes/deployment.yaml` **`image:`** field to your ECR URL + tag (same value as **`${ECR_REPO}:latest`** from **F2** in bash, or **`$ECR_REPO:latest`** in PowerShell after `terraform output`).

Interview line: pinning by **immutable digest** is stronger than `:latest`; `:latest` is fine for demos.

---

## Part G — Kubernetes Manifests Apply

Apply in sensible order:

**Bash / Linux / macOS / WSL:**

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml
```

**Windows PowerShell:**

```powershell
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml
```

Watch rollout:

**Bash / Linux / macOS / WSL:**

```bash
kubectl rollout status deployment/sample-app -n demo
kubectl get pods -n demo -o wide
kubectl describe ingress sample-app -n demo
kubectl get ingress -n demo
```

**Windows PowerShell:**

```powershell
kubectl rollout status deployment/sample-app -n demo
kubectl get pods -n demo -o wide
kubectl describe ingress sample-app -n demo
kubectl get ingress -n demo
```

When the Ingress is reconciled, **`ADDRESS`** should populate with ALB hostname.

---

## Part H — Verification Checklist

**Bash / Linux / macOS / WSL:**

```bash
# Controller health (should be Ready)
kubectl get deploy -n kube-system aws-load-balancer-controller

# Target group memberships appear after ALB provisioning (describe ingress events)
kubectl describe ingress sample-app -n demo

# Hit the hostname (DNS propagation can take short time)
curl -sS "http://REPLACE_WITH_INGRESS_DNS/"
```

**Windows PowerShell:**

```powershell
# Controller health (should be Ready)
kubectl get deploy -n kube-system aws-load-balancer-controller

# Target group memberships appear after ALB provisioning (describe ingress events)
kubectl describe ingress sample-app -n demo

# Hit the hostname (DNS propagation can take short time)
curl.exe http://REPLACE_WITH_INGRESS_DNS/
```

If you retained **nginx upstream** rather than custom ECR, you should still see a page — swap to confirm your Dockerfile content when pushing to ECR.

---

## Part I — Troubleshooting (High-Yield Diagnostics)

### I1) Nodes never become Ready

- `kubectl describe node …` shows CNI/kubelet breadcrumbs.
- Check node group **`aws_eks_node_group`** in AWS console versus subnet routes (private subnets route to NAT).
- Confirm **`AmazonEKS_CNI_Policy`** attached — Terraform does this, but verifying is a deliberate interview maneuver.

### I2) ALB hostname never appears

- `kubectl describe ingress -n demo sample-app`: read **Events** referencing subnet discovery / tagging.
- Ensure **public subnets** carry ELB-facing tag `kubernetes.io/role/elb` (Terraform manages).
- Helm chart installed and **`aws-load-balancer-controller`** pod logs show errors.

### I3) 503/502 from ALB despite DNS resolving

Health checks failing — confirm:

- Pods **listening on port 80**,
- **`Service`** `targetPort` matches container port naming,
- **Security groups**: ALB-created SG permits traffic to Pod/node path (controller typically manages ancillary SG choreography; mis-tagged subnets break earlier).

### I4) Image pull errors switching to ECR

- Nodes need **IAM ECR pulls** (`AmazonEC2ContainerRegistryReadOnly`).
- Repo policy / image URI typos / forgetting **region** qualifier.

---

## Part J — Destroy / Cleanup Order (Prevent Surprise Bills)

### J1) Delete Kubernetes load balancers first

Ingress-managed ALBs should delete when Ingress deletes — still verify under **EC2 → Load Balancers**:

**Bash / Linux / macOS / WSL:**

```bash
kubectl delete ingress sample-app -n demo
kubectl delete deployment sample-app -n demo
kubectl delete service sample-app -n demo
```

**Windows PowerShell:**

```powershell
kubectl delete ingress sample-app -n demo
kubectl delete deployment sample-app -n demo
kubectl delete service sample-app -n demo
```

Wait until ALBs disappear (often minutes).

### J2) Helm uninstall controller (recommended before tearing IAM)

**Bash / Linux / macOS / WSL:**

```bash
helm uninstall aws-load-balancer-controller -n kube-system
```

**Windows PowerShell:**

```powershell
helm uninstall aws-load-balancer-controller -n kube-system
```

### J3) Terraform destroy

**Bash / Linux / macOS / WSL:**

```bash
cd terraform
terraform destroy
cd ..
```

**Windows PowerShell:**

```powershell
Push-Location terraform
terraform destroy
Pop-Location
```

If destroy stalls because of **EBS volumes / ENIs**, revisit AWS console breadcrumbs (typically resolved after load balancers finalize deletion).

### J4) Clean backend artifacts intentionally

Deleting only EC2 misses:

- **`terraform.tfstate`** in S3 (if you destroy outside Terraform or orphaned stacks).
- **ECR repository** leftover images Terraform created but you may purge manually cheaply via console if desired.
- **`Elastic IP`** should release with Terraform when NAT destroys — verify EC2 Elastic IPs page.

Interview line: IaC teardown still requires **verification** step because Kubernetes controllers asynchronously delete cloud resources.
