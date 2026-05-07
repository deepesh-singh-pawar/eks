# -----------------------------------------------------------------------------
# Security groups: cluster API vs worker traffic patterns for EKS.
# We keep scope tight-enough-for-learning without reproducing full enterprise policy engines.
# -----------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster to node communication"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# Nodes can initiate connections to kube-apiserver (443 HTTPS). Control plane communicates to kubelets.
resource "aws_security_group_rule" "cluster_inbound_from_nodes" {
  description              = "Nodes to kubernetes API server"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "cluster_outbound" {
  description       = "Cluster security group egress (nodes pull images, APIs, etc. via SG references)"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Managed node worker communication"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "nodes_internal" {
  description              = "Node to node and pod mesh traffic"
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "nodes_kubelet_from_cluster" {
  description              = "Cluster control plane to kubelet on workers"
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "node_outbound" {
  description       = "Allow nodes to NAT out for deps (ECR, packages, IAM, STS, APIs)"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}
