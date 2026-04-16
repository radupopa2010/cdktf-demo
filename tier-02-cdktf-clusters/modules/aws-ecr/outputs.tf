output "repository_url" {
  value       = aws_ecr_repository.this.repository_url
  description = "Full ECR registry URL for docker push/pull."
}

output "repository_name" {
  value = aws_ecr_repository.this.name
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}
