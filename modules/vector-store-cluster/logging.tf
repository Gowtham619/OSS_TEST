resource "aws_cloudwatch_log_group" "index_slow" {
  count             = var.enable_slow_logs ? 1 : 0
  name              = "/aws/opensearch/${local.domain_name}/index-slow-logs"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "search_slow" {
  count             = var.enable_slow_logs ? 1 : 0
  name              = "/aws/opensearch/${local.domain_name}/search-slow-logs"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "application" {
  count             = var.enable_slow_logs ? 1 : 0
  name              = "/aws/opensearch/${local.domain_name}/application-logs"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# OpenSearch's log-delivery service needs an explicit resource policy on the
# log groups before it will write to them.
data "aws_iam_policy_document" "log_delivery" {
  count = var.enable_slow_logs ? 1 : 0

  statement {
    sid     = "AllowOpenSearchLogDelivery"
    effect  = "Allow"
    actions = ["logs:PutLogEvents", "logs:CreateLogStream"]
    resources = [
      "${aws_cloudwatch_log_group.index_slow[0].arn}:*",
      "${aws_cloudwatch_log_group.search_slow[0].arn}:*",
      "${aws_cloudwatch_log_group.application[0].arn}:*",
    ]

    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  count           = var.enable_slow_logs ? 1 : 0
  policy_name     = "${local.domain_name}-os-log-delivery"
  policy_document = data.aws_iam_policy_document.log_delivery[0].json
}
