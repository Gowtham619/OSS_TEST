output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "embedding_lambda_role_arn" {
  description = "Attach this role to the ML Processing & Embedding Lambda (Layer 2)."
  value       = module.iam.embedding_lambda_role_arn
}

output "retrieval_lambda_role_arn" {
  description = "Attach this role to the Retrieval & Routing Lambda (Layer 4)."
  value       = module.iam.retrieval_lambda_role_arn
}

output "admin_role_arn" {
  value = module.iam.admin_role_arn
}

output "lambda_vpc_config" {
  description = "Pass this as the vpc_config block for both Lambdas — they must run in these private subnets to reach the vector store."
  value = {
    subnet_ids         = module.network.private_subnet_ids
    security_group_ids = compact([module.network.endpoints_security_group_id])
  }
}

output "aoss_collection_endpoint" {
  value = local.deploy_serverless ? module.vector_store_aoss[0].collection_endpoint : null
}

output "aoss_collection_arn" {
  value = local.deploy_serverless ? module.vector_store_aoss[0].collection_arn : null
}

output "cluster_domain_endpoint" {
  value = local.deploy_cluster ? module.vector_store_cluster[0].domain_endpoint : null
}

output "cluster_domain_arn" {
  value = local.deploy_cluster ? module.vector_store_cluster[0].domain_arn : null
}
