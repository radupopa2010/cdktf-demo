terraform {
  required_version = ">= 1.6"
  required_providers {
    helm       = { source = "hashicorp/helm", version = ">= 2.15.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.31.0" }
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "cdktf"
      "app.kubernetes.io/part-of"    = "rust-demo"
    }
  }
}

resource "helm_release" "rust_demo" {
  name      = var.release_name
  chart     = var.chart_path
  namespace = kubernetes_namespace_v1.this.metadata[0].name

  values = [
    yamlencode({
      replicaCount = var.replicas
      image = {
        repository = var.image_repository
        tag        = var.image_tag
      }
    })
  ]
}
