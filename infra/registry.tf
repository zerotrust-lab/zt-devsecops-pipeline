resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE" # A tag can never be repointed after push.
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true # AWS-native scan; Trivy in CI is the enforced gate.
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.devsecops.arn
  }
}

# Retire untagged layers so the registry does not accumulate cost/attack surface.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
