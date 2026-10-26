locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─────────────────────────────────────────────
# AWS Academy / LabRole constraint
#
# The Academy lab account cannot create IAM roles
# or policies. Instead, the pre-existing LabRole is
# reused for BOTH the EKS control plane and the
# worker node group. We look it up as a data source
# so Terraform never attempts to create it.
#
# The node group inherits LabRole, so pods that need
# AWS access (evaluation-service → SQS, analytics-service
# → SQS + DynamoDB) use the node instance credentials
# (LabRole) instead of IRSA, which is unavailable here.
# ─────────────────────────────────────────────
data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

# ─────────────────────────────────────────────
# Security Group — EKS Control Plane
# ─────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-eks-cluster-sg"
  })
}

# ─────────────────────────────────────────────
# EKS Cluster  (uses LabRole as the cluster role)
# ─────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = data.aws_iam_role.lab.arn

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Enable EKS control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })
}

# ─────────────────────────────────────────────
# Security Group — Worker Nodes
# ─────────────────────────────────────────────
resource "aws_security_group" "nodes" {
  name        = "${var.project}-${var.environment}-eks-nodes-sg"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id

  # Allow all traffic between nodes
  ingress {
    description = "Node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow control plane to reach nodes
  ingress {
    description     = "Control plane to nodes"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.cluster.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-eks-nodes-sg"
  })
}

# Allow nodes to communicate back to the control plane
resource "aws_security_group_rule" "cluster_ingress_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Worker nodes to control plane"
}

# ─────────────────────────────────────────────
# Launch Template for worker nodes
#
# A custom launch template is required to raise the IMDS (instance metadata)
# hop limit from the default of 1 to 2. On AWS Academy there is no IRSA, so
# pods obtain AWS credentials from the node's LabRole via IMDS. With the
# default hop limit of 1, the metadata response cannot traverse the extra
# network hop into the pod network, so the AWS SDK inside pods fails with
# "NoCredentialProviders" / "Unable to locate credentials" (breaking
# evaluation-service → SQS and analytics-service → SQS/DynamoDB). Hop limit 2
# lets pod-originated IMDS requests reach the endpoint.
#
# NOTE: deliberately no custom AMI or user_data here — EKS injects its
# EKS-optimized AMI and bootstrap into this template, so the managed node
# group still auto-registers nodes cleanly.
# ─────────────────────────────────────────────
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-${var.node_group_name}-"

  # Root EBS volume (moved here from the node group; disk_size on the node
  # group is not allowed together with a custom launch template).
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  # Raise IMDS hop limit to 2 so pods can reach instance metadata and assume
  # the node's LabRole (the no-IRSA workaround for AWS Academy).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-${var.node_group_name}"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# EKS Managed Node Group  (uses LabRole as node role)
# ─────────────────────────────────────────────
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${var.node_group_name}"
  node_role_arn   = data.aws_iam_role.lab.arn

  # Place worker nodes in private subnets
  subnet_ids = var.private_subnet_ids

  # instance_types stays on the node group; disk_size moves into the launch
  # template (they are mutually exclusive with a custom LT).
  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  # Attach the custom launch template (IMDS hop limit 2). Using "$Latest"
  # tracks template updates on the next node refresh.
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role        = "worker"
    environment = var.environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${var.node_group_name}"
  })
}
