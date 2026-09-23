locals {
  domain_name = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Project     = "complaints-rag-platform"
      Layer       = "vector-store"
      Variant     = "cluster-based"
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.tags
  )

  all_access_principal_arns = distinct(concat(
    [var.master_user_arn],
    var.data_access_principal_arns
  ))
}
