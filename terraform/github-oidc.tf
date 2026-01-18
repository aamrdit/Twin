############################################
# GitHub OIDC Integration for AWS
# - Prevents accidental deletion of OIDC provider and role
# - Correct repo casing: aamrdit/Twin
# - Environment-based sub claim: repo:aamrdit/Twin:environment:*
############################################

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' (case sensitive). Example: aamrdit/Twin"
  type        = string
  default     = "aamrdit/Twin"
}

############################################
# GitHub OIDC Provider
############################################
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # From GitHub documentation (verify if GitHub rotates in future)
  thumbprint_list = [
    "1b511abead59c6ce207077c0bf0e0043b1382612"
  ]

  lifecycle {
    prevent_destroy = true

    # Optional safety: avoid churn if AWS/GitHub changes ordering/representation
    ignore_changes = [
      thumbprint_list,
      client_id_list
    ]
  }

  tags = {
    Name      = "GitHub Actions OIDC Provider"
    ManagedBy = "terraform"
  }
}

############################################
# IAM Role for GitHub Actions
############################################
resource "aws_iam_role" "github_actions" {
  name = "github-actions-twin-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # IMPORTANT: Match real repo casing + environment-based workflow runs
            "token.actions.githubusercontent.com:sub" = "repo:aamrdit/Twin:environment:*"
          }
        }
      }
    ]
  })

  tags = {
    Name       = "GitHub Actions Deploy Role"
    Repository = var.github_repository
    ManagedBy  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

############################################
# Attach Managed Policies (broad; you can tighten later)
############################################
resource "aws_iam_role_policy_attachment" "github_lambda" {
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_apigateway" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_cloudfront" {
  policy_arn = "arn:aws:iam::aws:policy/CloudFrontFullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_iam_read" {
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_bedrock" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_dynamodb" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_acm" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_route53" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
  role       = aws_iam_role.github_actions.name
}

############################################
# Inline Policy for additional permissions
############################################
resource "aws_iam_role_policy" "github_additional" {
  name = "github-actions-additional"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:UpdateAssumeRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListInstanceProfilesForRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

############################################
# Output
############################################
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
