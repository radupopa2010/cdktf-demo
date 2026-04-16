variable "name" { type = string }
variable "cluster_name" { type = string }
variable "subnet_ids" { type = list(string) }

variable "instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "min_size" {
  type    = number
  default = 1
}
variable "max_size" {
  type    = number
  default = 2
}
variable "desired_size" {
  type    = number
  default = 1
}
variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
