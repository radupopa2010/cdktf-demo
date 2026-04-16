variable "name" {
  type        = string
  description = "VPC name (also used as a prefix for child resources)."
}

variable "vpc_cidr" {
  type        = string
  description = "Top-level VPC CIDR (e.g. 10.251.0.0/20)."
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across (>=2 for ALB)."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets (one per AZ)."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private subnets (one per AZ)."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource."
  default     = {}
}
