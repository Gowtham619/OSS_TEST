locals {
  name = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Project     = "complaints-rag-platform"
      Layer       = "iam"
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

##############################################
# Bedrock invoke policy — shared by both Lambda roles
##############################################
data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid       = "InvokeEmbeddingModels"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = var.bedrock_model_arns
  }
}

resource "aws_iam_policy" "bedrock_invoke" {
  name   = "${local.name}-bedrock-invoke"
  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

##############################################
# Embedding Lambda role — Layer 2 (ML Processing & Embedding)
##############################################
resource "aws_iam_role" "embedding_lambda" {
  name               = "${local.name}-embedding-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "embedding_basic" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "embedding_vpc" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "embedding_bedrock" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

##############################################
# Retrieval Lambda role — Layer 4 (Retrieval & Routing)
##############################################
resource "aws_iam_role" "retrieval_lambda" {
  name               = "${local.name}-retrieval-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "retrieval_basic" {
  role       = aws_iam_role.retrieval_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "retrieval_vpc" {
  role       = aws_iam_role.retrieval_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "retrieval_bedrock" {
  role       = aws_iam_role.retrieval_lambda.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

##############################################
# Admin role — used as the OpenSearch fine-grained-access-control master
# user (cluster-based module) and as a break-glass principal for AOSS.
##############################################
data "aws_iam_policy_document" "admin_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      identifiers = length(var.admin_principal_arns) > 0 ? var.admin_principal_arns : [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }
}

resource "aws_iam_role" "admin" {
  name               = "${local.name}-vector-store-admin-role"
  assume_role_policy = data.aws_iam_policy_document.admin_assume_role.json
  tags               = local.common_tags
}

# Lets the admin role (used for manual testing, e.g. an assumed-role
# ingestion test script) call Bedrock directly — same policy the
# embedding/retrieval Lambdas use.
resource "aws_iam_role_policy_attachment" "admin_bedrock" {
  role       = aws_iam_role.admin.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

##############################################
# Lets the embedding/retrieval Lambda roles assume the admin role — needed
# once, to bootstrap the OpenSearch cluster domain's internal Security
# plugin role-mapping (an IAM access policy alone does not grant any
# in-domain privileges; only the master user, i.e. this admin role, can
# grant other identities permissions inside OpenSearch itself).
##############################################
data "aws_iam_policy_document" "assume_admin" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.admin.arn]
  }
}

resource "aws_iam_policy" "assume_admin" {
  name   = "${local.name}-assume-admin"
  policy = data.aws_iam_policy_document.assume_admin.json
}

resource "aws_iam_role_policy_attachment" "embedding_assume_admin" {
  role       = aws_iam_role.embedding_lambda.name
  policy_arn = aws_iam_policy.assume_admin.arn
}

resource "aws_iam_role_policy_attachment" "retrieval_assume_admin" {
  role       = aws_iam_role.retrieval_lambda.name
  policy_arn = aws_iam_policy.assume_admin.arn
}
