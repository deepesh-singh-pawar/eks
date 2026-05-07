output "eks_cluster_name" {
  description = "kubectl/Helm contexts use this cluster name with `aws eks update-kubeconfig`."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server URL (useful for debugging and for some clients)."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 CA bundle for kube-apiserver TLS."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "eks_kubeconfig_command" {
  description = "Shortcut command to register this cluster in ~/.kube/config via AWS CLI."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "aws_load_balancer_controller_role_arn" {
  description = "Helm values use this annotation: serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
  value       = aws_iam_role.alb_controller.arn
}

output "ecr_repository_url" {
  description = "ECR URL to tag/push the sample image (see SETUP_GUIDE: docker tag/build/push)."
  value       = aws_ecr_repository.sample_app.repository_url
}

output "vpc_id" {
  description = "VPC id for follow-up networking questions or peering exercises."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Subnets suitable for internet-facing ALBs (via tags + routes)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Worker / private Pod networking subnets."
  value       = aws_subnet.private[*].id
}
