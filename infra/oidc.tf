# GitHub's OIDC thumbprint is resolved dynamically rather than hardcoded,
# so this survives GitHub rotating its certificate.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# Trust policy: only tokens from OUR repo AND an allowed branch may assume this
# role. The sub condition is the most security-critical line in this repo --
# without it, any GitHub repo could assume the role.
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub sends the subject in two possible shapes:
    #   1. repo:ORG/REPO:ref:REF                       (classic)
    #   2. repo:ORG@<org-id>/REPO@<repo-id>:ref:REF    (with immutable numeric IDs)
    # Both are accepted. The "@*" wildcard is safe because GitHub org and repo
    # names cannot contain "@", so it cannot match a different organisation.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        [for ref in var.allowed_branches : "repo:${var.github_org}/${var.github_repo}:ref:${ref}"],
        [for ref in var.allowed_branches : "repo:${var.github_org}@*/${var.github_repo}@*:ref:${ref}"],
      )
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "zt-devsecops-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Permission policy: push/pull images and obtain an auth token. Nothing else.
data "aws_iam_policy_document" "ci_permissions" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken does not support resource scoping.
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages"
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ci_permissions" {
  name   = "ecr-push-pull"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}
