terraform {
  required_version = ">= 1.6"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.50" }
    helm       = { source = "hashicorp/helm", version = ">= 2.15.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.31.0" }
  }
}

# IAM policy from upstream (k8s-sigs/aws-load-balancer-controller).
# We embed a checked-in copy so deploys are reproducible; refresh periodically.
locals {
  iam_policy_path = "${path.module}/iam-policy.json"
}

resource "aws_iam_policy" "lbc" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "Permissions for the AWS Load Balancer Controller in ${var.cluster_name}"
  policy      = file(local.iam_policy_path)
  tags        = var.tags
}

# IRSA trust policy: only the LBC ServiceAccount in `var.namespace` can assume.
data "aws_iam_policy_document" "lbc_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# Helm release of the controller.
resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = var.service_account },
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = aws_iam_role.lbc.arn },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
  ]

  depends_on = [aws_iam_role_policy_attachment.lbc]
}
