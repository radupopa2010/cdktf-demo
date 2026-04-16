variable "enabled" {
  type        = bool
  default     = false
  description = "Toggle to install cert-manager."
}

variable "chart_version" {
  type    = string
  default = "v1.15.0"
}

variable "namespace" {
  type    = string
  default = "cert-manager"
}
