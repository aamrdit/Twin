############################################
# GitHub OIDC Integration for AWS (GLOBAL)
# Place this in terraform-bootstrap/
############################################

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' (case sensitive). Example: aamrdit/Twin"
  type        = string
  default     = "aamrdit/Twin"
}

variable "github_role_name" {
  description = "IAM role name assumed by GitHub Actions via OIDC"
  type        = string
  default     = "github-actions-twin-deploy"
}

############################################
# GitHub OIDC Provider
############################################
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "1b511abead59c6ce207077c0bf0e0043b1382612"
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [thumbprint_list, client_id_list]
  }

  tags = {
    Name      = "GitHub Actions OIDC Provider"
    ManagedBy = "terraform"
  }
}

############################################
# IAM Role for GitHub Actions (GLOBAL)
############################################
resource "aws_iam_role" "github_actions" {
  name = var.github_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:*"
        }
      }
    }]
  })

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name       = "GitHub Actions Deploy Role"
    Repository = var.github_repository
    ManagedBy  = "terraform"
  }
}

############################################
# Managed Policy Attachments
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
# Inline Policy: Terraform-friendly IAM cleanup
############################################
resource "aws_iam_role_policy" "github_additional" {
  name = "github-actions-additional"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # General read/debug
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = "*"
      },

      # Allow Terraform to fully delete roles it created for the app (Lambda execution roles, etc.)
      # NOTE: This DOES NOT allow deleting the GitHub role itself, because prevent_destroy blocks it anyway.
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::*:role/twin-*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
