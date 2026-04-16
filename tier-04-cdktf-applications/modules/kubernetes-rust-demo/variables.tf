variable "namespace" {
  type    = string
  default = "rust-demo"
}
variable "release_name" {
  type    = string
  default = "rust-demo"
}
variable "chart_path" {
  type        = string
  description = "Path to the local Helm chart (../../app/helm/rust-demo from tier root)."
}

variable "image_repository" { type = string }
variable "image_tag" { type = string }
variable "replicas" {
  type    = number
  default = 1
}
