output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the created VPC."
}

output "vpc_cidr" {
  value       = module.vpc.vpc_cidr_block
  description = "Top-level CIDR of the VPC."
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "List of public subnet IDs (ALB-eligible)."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "List of private subnet IDs (EKS node-eligible)."
}

output "azs" {
  value       = module.vpc.azs
  description = "AZs in use."
}

output "nat_gateway_ids" {
  value       = module.vpc.natgw_ids
  description = "NAT gateway IDs (one in cheap-mode)."
}
