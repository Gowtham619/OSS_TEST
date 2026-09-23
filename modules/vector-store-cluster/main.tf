resource "aws_opensearch_domain" "this" {
  domain_name    = local.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.instance_type
    instance_count           = var.instance_count
    zone_awareness_enabled   = var.zone_awareness_enabled
    dedicated_master_enabled = var.dedicated_master_enabled
    dedicated_master_type    = var.dedicated_master_enabled ? var.master_instance_type : null
    dedicated_master_count   = var.dedicated_master_enabled ? var.master_instance_count : null

    dynamic "zone_awareness_config" {
      for_each = var.zone_awareness_enabled ? [1] : []
      content {
        availability_zone_count = var.availability_zone_count
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.ebs_volume_type
    volume_size = var.ebs_volume_size_gb
    throughput  = var.ebs_volume_type == "gp3" ? var.ebs_throughput : null
    iops        = var.ebs_volume_type == "gp3" ? var.ebs_iops : null
  }

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = local.domain_security_group_ids
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy  = var.tls_security_policy
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = false

    master_user_options {
      master_user_arn = var.master_user_arn
    }
  }

  dynamic "log_publishing_options" {
    for_each = var.enable_slow_logs ? {
      INDEX_SLOW_LOGS  = aws_cloudwatch_log_group.index_slow[0].arn
      SEARCH_SLOW_LOGS = aws_cloudwatch_log_group.search_slow[0].arn
      ES_APPLICATION_LOGS = aws_cloudwatch_log_group.application[0].arn
    } : {}
    content {
      log_type                 = log_publishing_options.key
      cloudwatch_log_group_arn = log_publishing_options.value
      enabled                  = true
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_service_linked_role.opensearch,
    aws_cloudwatch_log_resource_policy.opensearch,
  ]

  # Data-node and master-node changes can trigger a blue/green migration
  # that takes a long time; give Terraform room instead of timing out.
  timeouts {
    update = "180m"
  }
}

##############################################
# Resource-based access policy — IAM principals allowed to call the domain's
# HTTP API. Fine-grained per-index permissions are then layered on top via
# OpenSearch's own role mappings (Dashboards -> Security -> Roles), which
# Terraform's aws provider does not manage — see README.
##############################################
data "aws_iam_policy_document" "domain_access" {
  statement {
    sid     = "AllowComplaintsRagPrincipals"
    effect  = "Allow"
    actions = ["es:ESHttp*"]

    resources = ["${aws_opensearch_domain.this.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = local.all_access_principal_arns
    }
  }
}

resource "aws_opensearch_domain_policy" "this" {
  domain_name     = aws_opensearch_domain.this.domain_name
  access_policies = data.aws_iam_policy_document.domain_access.json
}
