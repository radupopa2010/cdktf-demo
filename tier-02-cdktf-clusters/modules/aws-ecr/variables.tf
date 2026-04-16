variable "repository_name" {
  type        = string
  description = "ECR repository name (e.g. cdktf-demo/rust-demo)."
}

variable "image_retention_count" {
  type        = number
  default     = 10
  description = "Lifecycle keeps only this many most-recent images."
}

variable "tags" {
  type    = map(string)
  default = {}
}
