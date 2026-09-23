output "domain_id" {
  description = "ID of the OpenSearch domain."
  value       = aws_opensearch_domain.this.domain_id
}

output "domain_arn" {
  description = "ARN of the OpenSearch domain."
  value       = aws_opensearch_domain.this.arn
}

output "domain_endpoint" {
  description = "VPC endpoint (private) for the domain's HTTP API — used by embedding and retrieval Lambdas."
  value       = aws_opensearch_domain.this.endpoint
}

output "kibana_endpoint" {
  description = "Dashboards/Kibana endpoint for the domain (private, VPC-only)."
  value       = aws_opensearch_domain.this.dashboard_endpoint
}

output "security_group_id" {
  description = "Security group ID protecting the domain's ENIs."
  value       = local.domain_security_group_ids[0]
}
