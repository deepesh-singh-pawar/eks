variable "aws_region" {
  type        = string
  description = "AWS region for all resources. us-east-1 is common for examples and has broad service support."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short name used in resource Name tags and the ECR repository name."
  default     = "eks-learning"
}

variable "environment" {
  type        = string
  description = "Environment label for tagging (learning, dev, etc.)."
  default     = "learning"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name. Keep it short and DNS-friendly."
  default     = "eks-learning"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS control plane version. Pin a specific minor line for predictability; bump as AWS deprecates older versions."
  default     = "1.31"
}

variable "node_instance_type" {
  type        = string
  description = "Worker node size. t3.small is a cost/comfort balance for small clusters (t3.micro is often too tight for stable scheduling)."
  default     = "t3.small"
}

variable "node_desired_size" {
  type        = number
  description = "Managed node group desired count. Set to 2 for this low-cost layout."
  default     = 2
}

variable "node_min_size" {
  type        = number
  description = "Minimum nodes (kept equal to desired for predictable cost in a learning cluster)."
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Maximum nodes for basic scale headroom without surprise bills."
  default     = 4
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR. /16 leaves room for /24 subnets across AZs."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One /24 public subnet per AZ (NAT + load balancer facing subnets)."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "One /24 private subnet per AZ (nodes + private endpoints traffic stays internal)."
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "If true, your kube-apiserver endpoint is reachable from the internet subject to public_access_cidrs (fine for learning; tighten for real prod)."
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "Who can reach the public Kubernetes API endpoint. Default is open internet — replace with your home /32 or office CIDR."
  default     = ["0.0.0.0/0"]
}

variable "common_tags" {
  type        = map(string)
  description = "Tags merged into aws provider default_tags (Project/Environment/ManagedBy, etc.)."
  default = {
    Project     = "eks-learning"
    Environment = "learning"
    ManagedBy   = "Terraform"
    Purpose     = "InterviewPrep"
  }
}
