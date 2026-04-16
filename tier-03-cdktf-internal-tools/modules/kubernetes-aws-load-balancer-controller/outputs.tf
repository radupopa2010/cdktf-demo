output "iam_role_arn" {
  value       = aws_iam_role.lbc.arn
  description = "IRSA role ARN of the LBC ServiceAccount."
}

output "namespace" { value = var.namespace }
output "service_account" { value = var.service_account }
output "release_name" { value = helm_release.lbc.name }
