variable "name_prefix" {
  description = "Prefix used for naming all resources, e.g. 'complaints-rag'."
  type        = string
  default     = "complaints-rag"
}

variable "environment" {
  description = "Environment name (dev, uat, prod). Used in resource naming and tags."
  type        = string
  default     = "dev"
}

variable "collection_type" {
  description = "AOSS collection type. VECTORSEARCH for the embedding/retrieval layer, SEARCH or TIMESERIES for other use cases."
  type        = string
  default     = "VECTORSEARCH"

  validation {
    condition     = contains(["VECTORSEARCH", "SEARCH", "TIMESERIES"], var.collection_type)
    error_message = "collection_type must be one of VECTORSEARCH, SEARCH, TIMESERIES."
  }
}

variable "standby_replicas" {
  description = "Whether standby replicas are enabled (ENABLED costs ~2x OCU but gives Multi-AZ resilience; DISABLED is cheaper, recommended for dev/uat)."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.standby_replicas)
    error_message = "standby_replicas must be ENABLED or DISABLED."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for collection encryption at rest. If null, AWS-owned key is used."
  type        = string
  default     = null
}

variable "network_access_type" {
  description = "Whether the collection is reachable via 'public' internet (still IAM-authenticated) or only via 'vpc' endpoint(s). 'vpc' is recommended for a complaints/PII platform."
  type        = string
  default     = "vpc"

  validation {
    condition     = contains(["public", "vpc"], var.network_access_type)
    error_message = "network_access_type must be 'public' or 'vpc'."
  }
}

variable "vpc_id" {
  description = "VPC ID for the AOSS VPC endpoint. Required when network_access_type = 'vpc'."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnet IDs (one per AZ) for the AOSS VPC endpoint. Required when network_access_type = 'vpc'."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs attached to the AOSS VPC endpoint. If empty, a security group is created automatically."
  type        = list(string)
  default     = []
}

variable "vpc_endpoint_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the AOSS VPC endpoint on 443, when a security group is auto-created."
  type        = list(string)
  default     = []
}

variable "data_access_principal_arns" {
  description = "IAM role/user ARNs granted full data-plane access to the collection and its indexes (e.g. the ML processing Lambda role, the retrieval/routing Lambda role, an admin role). At least one principal must be supplied or the collection will be unreachable."
  type        = list(string)

  validation {
    condition     = length(var.data_access_principal_arns) > 0
    error_message = "Provide at least one IAM principal ARN in data_access_principal_arns."
  }
}

variable "read_only_principal_arns" {
  description = "Optional IAM role/user ARNs granted read-only access (search/describe only, no write) — e.g. a BI or audit role."
  type        = list(string)
  default     = []
}

variable "create_bedrock_access_role" {
  description = "Whether to create an IAM role assumable by Lambda/Bedrock knowledge base service for writing embeddings and querying the collection."
  type        = bool
  default     = true
}

variable "bedrock_assume_role_services" {
  description = "AWS service principals allowed to assume the Bedrock/AOSS access role."
  type        = list(string)
  default     = ["lambda.amazonaws.com", "bedrock.amazonaws.com"]
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
