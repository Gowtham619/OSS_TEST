variable "name_prefix" {
  type    = string
  default = "complaints-rag"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "bedrock_model_arns" {
  description = "ARNs (or ARN patterns) of Bedrock foundation models the embedding/retrieval Lambdas are allowed to invoke."
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0",
    "arn:aws:bedrock:*::foundation-model/amazon.titan-embed-image-v1",
  ]
}

variable "admin_principal_arns" {
  description = "IAM user/role ARNs allowed to assume the admin role used as the OpenSearch fine-grained-access-control master user. If empty, defaults to the account's root — tighten this before prod."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
