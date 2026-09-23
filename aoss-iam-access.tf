##############################################
# AOSS requires two separate layers of authorization: the resource-based
# data access policy (module.vector_store_aoss's data_access_principal_arns
# — already correct, controls fine-grained CRUD) AND an identity-based IAM
# policy on the caller granting aoss:APIAccessAll on the collection — this
# second layer was missing for the embedding/retrieval/admin roles, which
# is why AOSS returned a bare 403 even with a correct data access policy.
##############################################

resource "aws_iam_policy" "aoss_api_access_for_platform_roles" {
  count = local.deploy_serverless ? 1 : 0

  name = "${var.name_prefix}-${var.environment}-aoss-caller-api-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = module.vector_store_aoss[0].collection_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "embedding_aoss_api" {
  count      = local.deploy_serverless ? 1 : 0
  role       = module.iam.embedding_lambda_role_name
  policy_arn = aws_iam_policy.aoss_api_access_for_platform_roles[0].arn
}

resource "aws_iam_role_policy_attachment" "retrieval_aoss_api" {
  count      = local.deploy_serverless ? 1 : 0
  role       = module.iam.retrieval_lambda_role_name
  policy_arn = aws_iam_policy.aoss_api_access_for_platform_roles[0].arn
}

resource "aws_iam_role_policy_attachment" "admin_aoss_api" {
  count      = local.deploy_serverless ? 1 : 0
  role       = module.iam.admin_role_name
  policy_arn = aws_iam_policy.aoss_api_access_for_platform_roles[0].arn
}
