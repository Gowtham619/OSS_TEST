output "collection_id" {
  description = "ID of the OpenSearch Serverless collection."
  value       = aws_opensearchserverless_collection.this.id
}

output "collection_arn" {
  description = "ARN of the OpenSearch Serverless collection."
  value       = aws_opensearchserverless_collection.this.arn
}

output "collection_endpoint" {
  description = "Data-plane API endpoint for the collection (used by embedding Lambdas and Bedrock knowledge base)."
  value       = aws_opensearchserverless_collection.this.collection_endpoint
}

output "dashboard_endpoint" {
  description = "OpenSearch Dashboards endpoint for the collection."
  value       = aws_opensearchserverless_collection.this.dashboard_endpoint
}

output "vpc_endpoint_id" {
  description = "ID of the AOSS VPC endpoint, if created."
  value       = local.use_vpc ? aws_opensearchserverless_vpc_endpoint.this[0].id : null
}

output "aoss_access_role_arn" {
  description = "ARN of the IAM role created for Lambda/Bedrock access to the collection, if created."
  value       = var.create_bedrock_access_role ? aws_iam_role.aoss_access[0].arn : null
}
