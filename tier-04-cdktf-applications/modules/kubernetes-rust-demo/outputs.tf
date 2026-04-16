output "release_name" { value = helm_release.rust_demo.name }
output "namespace"    { value = kubernetes_namespace.this.metadata[0].name }
output "image"        { value = "${var.image_repository}:${var.image_tag}" }
