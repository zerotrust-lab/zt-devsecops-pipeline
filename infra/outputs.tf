output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_repository_url" {
  description = "Set this as the ECR_REPOSITORY repository variable in GitHub."
  value       = aws_ecr_repository.app.repository_url
}

output "kms_key_arn" {
  description = "Platform KMS key ARN."
  value       = aws_kms_key.devsecops.arn
}
