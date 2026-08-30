data "aws_caller_identity" "current" {}

# Customer-managed KMS key: audit-logged root of trust for registry encryption
# and any envelope-encryption the platform requires.
resource "aws_kms_key" "devsecops" {
  description             = "Zero-Trust DevSecOps platform KMS key"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true
  multi_region            = false

  # Explicit key policy: root account administers, CI role gets use-only.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCIRoleUse"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.github_actions.arn }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "devsecops" {
  name          = "alias/zt-devsecops"
  target_key_id = aws_kms_key.devsecops.key_id
}
