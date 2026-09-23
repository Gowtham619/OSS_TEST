variable "name_prefix" {
  type    = string
  default = "complaints-rag"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread public/private subnets across. 3 recommended for prod (matches OpenSearch zone awareness)."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for all private subnets (cheaper, single point of failure) instead of one per AZ (resilient, ~3x NAT cost). Default true for dev/cost reasons — set false for prod."
  type        = bool
  default     = true
}

variable "create_interface_endpoints" {
  description = "Create VPC interface endpoints for Secrets Manager, Bedrock Runtime, STS and CloudWatch Logs, so Lambdas in the private subnets can reach them without traversing the NAT Gateway. Recommended true; keeps traffic off the public internet path entirely and reduces NAT data-processing cost."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
