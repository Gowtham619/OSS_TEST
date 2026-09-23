##############################################
# Public query API for the frontend. Toggle with deploy_query_api.
# The Lambda stays VPC-attached (same subnets/SG as everything else) —
# only API Gateway's HTTP endpoint is public; it invokes the Lambda via
# the Lambda service's control plane, not through the VPC, so this does
# not expose the vector stores directly.
##############################################

variable "deploy_query_api" {
  description = "Deploy the public query API (API Gateway + Lambda) for the frontend. Flip back to false and re-apply to tear it down."
  type        = bool
  default     = false
}

variable "query_api_top_k" {
  description = "Number of nearest-neighbor results the query API returns per store."
  type        = number
  default     = 5
}

data "archive_file" "query_api" {
  count       = var.deploy_query_api ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/query-api"
  output_path = "${path.module}/.build/query-api.zip"
}

resource "aws_cloudwatch_log_group" "query_api" {
  count             = var.deploy_query_api ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-${var.environment}-query-api"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "query_api" {
  count = var.deploy_query_api ? 1 : 0

  function_name = "${var.name_prefix}-${var.environment}-query-api"
  role          = module.iam.retrieval_lambda_role_arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 256

  filename         = data.archive_file.query_api[0].output_path
  source_code_hash = data.archive_file.query_api[0].output_base64sha256

  vpc_config {
    subnet_ids         = module.network.private_subnet_ids
    security_group_ids = compact([module.network.endpoints_security_group_id])
  }

  environment {
    variables = {
      AOSS_ENDPOINT    = local.aoss_endpoint_url
      CLUSTER_ENDPOINT = local.cluster_endpoint_url
      TOP_K            = tostring(var.query_api_top_k)
    }
  }

  tags = merge(var.tags, { Purpose = "public-query-api" })

  depends_on = [aws_cloudwatch_log_group.query_api]
}

##############################################
# API Gateway HTTP API — public endpoint, CORS enabled for a browser
# frontend hosted anywhere (S3 static site, or opened as a local file).
##############################################
resource "aws_apigatewayv2_api" "query_api" {
  count         = var.deploy_query_api ? 1 : 0
  name          = "${var.name_prefix}-${var.environment}-query-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "query_api" {
  count                  = var.deploy_query_api ? 1 : 0
  api_id                 = aws_apigatewayv2_api.query_api[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.query_api[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "query_api" {
  count     = var.deploy_query_api ? 1 : 0
  api_id    = aws_apigatewayv2_api.query_api[0].id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.query_api[0].id}"
}

resource "aws_apigatewayv2_stage" "query_api" {
  count       = var.deploy_query_api ? 1 : 0
  api_id      = aws_apigatewayv2_api.query_api[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "query_api_apigw" {
  count         = var.deploy_query_api ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.query_api[0].execution_arn}/*/*"
}

output "query_api_url" {
  description = "POST {\"query_text\": \"...\"} here to search the vector store(s)."
  value       = var.deploy_query_api ? "${aws_apigatewayv2_stage.query_api[0].invoke_url}query" : null
}
