variable "cluster_name" { type = string }
variable "cluster_version" {
  type    = string
  default = "1.30"
}

variable "vpc_id" { type = string }

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from tier-01."
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
