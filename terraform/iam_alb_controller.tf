# -----------------------------------------------------------------------------
# OIDC + IRSA for the AWS Load Balancer Controller (ALB/NLB) pod identity.
# Terraform creates the IAM role; Helm (see SETUP_GUIDE.md) binds the role to the Pod via an annotation.
#
# Why IRSA: Pods get short-lived AWS credentials scoped to a role — better than reusing node IAM for everything.
# -----------------------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.cluster_name}-eks-oidc"
  }
}

locals {
  oidc_issuer_hostpath = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the controller ServiceAccount in kube-system can mint creds for this role.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_hostpath}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json

  tags = {
    Name = "${var.cluster_name}-alb-controller-irsa"
  }
}

resource "aws_iam_policy" "alb_controller" {
  name_prefix = "${var.cluster_name}-alb-ctrl-"
  policy      = file("${path.module}/policies/alb_controller_iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
