locals {
  collection_name = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Project     = "complaints-rag-platform"
      Layer       = "vector-store"
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.tags
  )

  use_vpc = var.network_access_type == "vpc"

  # Merge write and read-only principals for the network policy (network
  # policy only gates connectivity; fine-grained read/write is enforced
  # by the data access policy below).
  all_principal_arns = distinct(concat(
    var.data_access_principal_arns,
    var.read_only_principal_arns
  ))
}
