variable "name_prefix" {
  description = "Prefix used for naming the domain, e.g. 'complaints-rag'."
  type        = string
  default     = "complaints-rag"
}

variable "environment" {
  description = "Environment name (dev, uat, prod)."
  type        = string
  default     = "dev"
}

variable "engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.15"
}

##############################################
# Data node sizing
##############################################
variable "instance_type" {
  description = "Data node instance type. Use an *r*/*or* memory-optimised family for vector (k-NN) workloads, e.g. r6g.large.search."
  type        = string
  default     = "r6g.large.search"
}

variable "instance_count" {
  description = "Number of data nodes. Should be a multiple of the AZ count for even distribution."
  type        = number
  default     = 3
}

variable "zone_awareness_enabled" {
  description = "Spread data nodes across multiple AZs. Recommended true for prod."
  type        = bool
  default     = true
}

variable "availability_zone_count" {
  description = "Number of AZs to spread across when zone_awareness_enabled = true. Must be 2 or 3, and instance_count/dedicated master count should be a multiple of this."
  type        = number
  default     = 3

  validation {
    condition     = contains([2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 2 or 3."
  }
}

##############################################
# Dedicated master nodes
##############################################
variable "dedicated_master_enabled" {
  description = "Use dedicated master nodes, separate from data nodes. Strongly recommended for prod clusters serving RAG query traffic."
  type        = bool
  default     = true
}

variable "master_instance_type" {
  description = "Dedicated master node instance type."
  type        = string
  default     = "m6g.large.search"
}

variable "master_instance_count" {
  description = "Number of dedicated master nodes. AWS recommends 3 for prod (odd number, quorum)."
  type        = number
  default     = 3
}

##############################################
# Storage
##############################################
variable "ebs_volume_size_gb" {
  description = "EBS volume size per data node, in GB. Size for the historical corpus (900k complaints / 6 months) plus the embedding vectors, with headroom to the 20,000/day scale target."
  type        = number
  default     = 512
}

variable "ebs_volume_type" {
  description = "EBS volume type. gp3 is recommended for cost/performance."
  type        = string
  default     = "gp3"
}

variable "ebs_throughput" {
  description = "Throughput (MiB/s) when ebs_volume_type = gp3."
  type        = number
  default     = 250
}

variable "ebs_iops" {
  description = "IOPS when ebs_volume_type = gp3."
  type        = number
  default     = 3000
}

##############################################
# Networking — VPC only. Public domains are not supported by this module;
# a complaints platform handling PII should never expose OpenSearch publicly.
##############################################
variable "vpc_id" {
  description = "VPC ID to deploy the domain into."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs, one per AZ (count must equal availability_zone_count when zone_awareness_enabled = true, else exactly 1)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to the domain's ENIs. If empty, one is created automatically, allowing only vpc_endpoint_ingress_cidrs on 443."
  type        = list(string)
  default     = []
}

variable "vpc_endpoint_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the domain on 443, when a security group is auto-created."
  type        = list(string)
  default     = []
}

##############################################
# Encryption
##############################################
variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest. If null, the AWS-managed key for OpenSearch is used."
  type        = string
  default     = null
}

variable "tls_security_policy" {
  description = "Minimum TLS policy for HTTPS traffic to the domain."
  type        = string
  default     = "Policy-Min-TLS-1-2-PFS-2023-10"
}

##############################################
# Fine-grained access control
##############################################
variable "master_user_arn" {
  description = "IAM role/user ARN mapped as the fine-grained-access-control master user. Recommended over an internal username/password master user."
  type        = string
}

variable "data_access_principal_arns" {
  description = "Additional IAM role/user ARNs granted access via the domain's resource-based access policy (e.g. embedding Lambda role, retrieval Lambda role)."
  type        = list(string)
  default     = []
}

##############################################
# Logging
##############################################
variable "enable_slow_logs" {
  description = "Publish index and search slow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for slow/application logs."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
