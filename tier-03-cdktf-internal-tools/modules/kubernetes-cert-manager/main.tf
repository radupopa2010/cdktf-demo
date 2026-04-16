terraform {
  required_version = ">= 1.6"
  required_providers {
    helm = { source = "hashicorp/helm", version = ">= 2.15.0" }
  }
}

resource "helm_release" "cert_manager" {
  count = var.enabled ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  set = [
    { name = "installCRDs", value = "true" },
  ]
}
