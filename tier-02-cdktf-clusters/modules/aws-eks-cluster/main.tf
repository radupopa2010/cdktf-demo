terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.50" }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access       = var.endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Demo: install only the must-have add-ons.
  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  # IRSA OIDC provider — required by tier-03 (LBC) and tier-04.
  enable_irsa = true

  # We create node groups in a separate module so they can be modified/scaled
  # without touching control-plane state.
  eks_managed_node_groups = {}

  # Cluster admins. Demo: grant the operator's caller identity.
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}
