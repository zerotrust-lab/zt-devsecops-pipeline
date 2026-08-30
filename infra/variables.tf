variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or username that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the org prefix)."
  type        = string
  default     = "zt-devsecops-pipeline"
}

variable "allowed_branches" {
  description = "Git refs permitted to assume the CI role (least privilege on the OIDC trust)."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository for the signed microservice image."
  type        = string
  default     = "zt-devsecops/go-microservice"
}

variable "kms_deletion_window_days" {
  description = "KMS key deletion window. Keys pending deletion are still billed, so use 7 for short-lived lab projects."
  type        = number
  default     = 7
}
