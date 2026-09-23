##############################################
# Trust policy — which services can assume this role
##############################################
data "aws_iam_policy_document" "assume_role" {
  count = var.create_bedrock_access_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = var.bedrock_assume_role_services
    }
  }
}

resource "aws_iam_role" "aoss_access" {
  count = var.create_bedrock_access_role ? 1 : 0

  name               = "${local.collection_name}-aoss-access-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role[0].json
  tags               = local.common_tags
}

##############################################
# Permissions policy — API-level access to the collection.
# NOTE: this grants the *IAM* action aoss:APIAccessAll, which is what
# actually lets the caller reach the AOSS data-plane API at all. The
# fine-grained CRUD permissions above (in the data access policy) are
# enforced on top of this by AOSS itself.
##############################################
data "aws_iam_policy_document" "aoss_api_access" {
  count = var.create_bedrock_access_role ? 1 : 0

  statement {
    sid       = "AOSSAPIAccess"
    effect    = "Allow"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.this.arn]
  }

  statement {
    sid       = "AOSSDashboardsAccess"
    effect    = "Allow"
    actions   = ["aoss:DashboardsAccessAll"]
    resources = [aws_opensearchserverless_collection.this.arn]
  }
}

resource "aws_iam_policy" "aoss_api_access" {
  count = var.create_bedrock_access_role ? 1 : 0

  name   = "${local.collection_name}-aoss-api-access"
  policy = data.aws_iam_policy_document.aoss_api_access[0].json
}

resource "aws_iam_role_policy_attachment" "aoss_api_access" {
  count = var.create_bedrock_access_role ? 1 : 0

  role       = aws_iam_role.aoss_access[0].name
  policy_arn = aws_iam_policy.aoss_api_access[0].arn
}
