variable "cluster_name"      { type = string }
variable "region"            { type = string }
variable "vpc_id"            { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_issuer_url"   { type = string }

variable "chart_version" {
  type    = string
  default = "1.8.1"
}

variable "namespace" {
  type    = string
  default = "kube-system"
}

variable "service_account" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "tags" {
  type    = map(string)
  default = {}
}
