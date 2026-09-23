variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "name_prefix" {
  type    = string
  default = "complaints-rag"
}

variable "environment" {
  type    = string
  default = "dev"
}

##############################################
# Networking
##############################################
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of AZs. 3 is required if you want zone_awareness on the cluster-based OpenSearch domain."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway (cheaper, dev-friendly). false = one per AZ (resilient, for prod)."
  type        = bool
  default     = true
}

##############################################
# Vector store choice
##############################################
variable "vector_store_type" {
  description = "Which vector store(s) to deploy: 'serverless' (AOSS), 'cluster' (managed OpenSearch domain), or 'both' (side by side, for comparison — separate collection/domain names, no conflict)."
  type        = string
  default     = "serverless"

  validation {
    condition     = contains(["serverless", "cluster", "both"], var.vector_store_type)
    error_message = "vector_store_type must be 'serverless', 'cluster', or 'both'."
  }
}

variable "create_opensearch_service_linked_role" {
  description = "Only relevant when vector_store_type includes 'cluster'. Set true ONLY the first time you ever deploy a VPC-based OpenSearch domain in this account/region; false on every run after that."
  type        = bool
  default     = false
}

variable "aoss_standby_replicas" {
  type    = string
  default = "DISABLED"
}

variable "cluster_instance_type" {
  type    = string
  default = "r6g.large.search"
}

variable "cluster_instance_count" {
  type    = number
  default = 3
}

variable "cluster_dedicated_master_enabled" {
  type    = bool
  default = true
}

variable "cluster_ebs_volume_size_gb" {
  type    = number
  default = 512
}

##############################################
# IAM
##############################################
variable "admin_principal_arns" {
  description = "IAM user/role ARNs allowed to assume the vector-store admin role. Leave empty only for an initial dev spike — it defaults to account root, which is too broad for anything beyond that."
  type        = list(string)
  default     = []
}

variable "bedrock_model_arns" {
  type = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
    "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-image-v1",
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}
