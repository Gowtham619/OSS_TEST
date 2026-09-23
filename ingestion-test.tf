##############################################
# Throwaway Lambda for testing ingestion into the vector store(s).
#
# Set deploy_ingestion_test_lambda = true and `terraform apply` to create
# it; set it back to false and `terraform apply` to destroy it cleanly —
# no manual `aws lambda create-function` / `delete-function` needed, and
# it never touches your real embedding/retrieval Lambdas (it reuses the
# embedding Lambda's IAM role and VPC config read-only).
##############################################

variable "deploy_ingestion_test_lambda" {
  description = "Deploy a throwaway ingestion-test Lambda alongside the platform. Flip back to false and re-apply to tear it down through Terraform."
  type        = bool
  default     = false
}

locals {
  # Both stores expose their endpoint in a slightly different shape (AOSS
  # includes the https:// scheme already; the cluster domain's `endpoint`
  # attribute is just the hostname) — normalize both to a full URL so the
  # Lambda code never has to guess.
  aoss_endpoint_url = local.deploy_serverless ? (
    startswith(module.vector_store_aoss[0].collection_endpoint, "http")
    ? module.vector_store_aoss[0].collection_endpoint
    : "https://${module.vector_store_aoss[0].collection_endpoint}"
  ) : ""

  cluster_endpoint_url = local.deploy_cluster ? (
    startswith(module.vector_store_cluster[0].domain_endpoint, "http")
    ? module.vector_store_cluster[0].domain_endpoint
    : "https://${module.vector_store_cluster[0].domain_endpoint}"
  ) : ""
}

data "archive_file" "ingestion_test" {
  count       = var.deploy_ingestion_test_lambda ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/ingestion-test"
  output_path = "${path.module}/.build/ingestion-test.zip"
}

resource "aws_cloudwatch_log_group" "ingestion_test" {
  count             = var.deploy_ingestion_test_lambda ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-${var.environment}-ingestion-test"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "ingestion_test" {
  count = var.deploy_ingestion_test_lambda ? 1 : 0

  function_name = "${var.name_prefix}-${var.environment}-ingestion-test"
  role          = module.iam.embedding_lambda_role_arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.ingestion_test[0].output_path
  source_code_hash = data.archive_file.ingestion_test[0].output_base64sha256

  vpc_config {
    subnet_ids         = module.network.private_subnet_ids
    security_group_ids = compact([module.network.endpoints_security_group_id])
  }

  environment {
    variables = {
      AOSS_ENDPOINT             = local.aoss_endpoint_url
      CLUSTER_ENDPOINT          = local.cluster_endpoint_url
      ADMIN_ROLE_ARN            = module.iam.admin_role_arn
      EMBEDDING_LAMBDA_ROLE_ARN = module.iam.embedding_lambda_role_arn
      RETRIEVAL_LAMBDA_ROLE_ARN = module.iam.retrieval_lambda_role_arn
    }
  }

  tags = merge(var.tags, {
    Purpose = "throwaway-ingestion-test"
  })

  depends_on = [aws_cloudwatch_log_group.ingestion_test]
}

output "ingestion_test_lambda_name" {
  description = "Invoke with: aws lambda invoke --function-name <this> response.json"
  value       = var.deploy_ingestion_test_lambda ? aws_lambda_function.ingestion_test[0].function_name : null
}
