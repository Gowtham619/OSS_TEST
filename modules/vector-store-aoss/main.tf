##############################################
# Encryption security policy (required first)
##############################################
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.collection_name}-enc"
  type        = "encryption"
  description = "Encryption policy for ${local.collection_name} complaints RAG vector collection"

  # The AOSS API rejects a "KmsARN" key that is present-but-null: when using
  # the AWS-owned key the field must be omitted entirely, not set to null.
  policy = var.kms_key_arn == null ? jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AWSOwnedKey = true
    }) : jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AWSOwnedKey = false
    KmsARN      = var.kms_key_arn
  })
}

##############################################
# Network security policy
##############################################
resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.collection_name}-net"
  type        = "network"
  description = "Network policy for ${local.collection_name} — ${var.network_access_type} access"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.collection_name}"]
        }
      ]
      AllowFromPublic = !local.use_vpc
      SourceVPCEs     = local.use_vpc ? [aws_opensearchserverless_vpc_endpoint.this[0].id] : null
    }
  ])

  depends_on = [aws_opensearchserverless_vpc_endpoint.this]
}

##############################################
# Data access policy (index + collection level permissions)
##############################################
resource "aws_opensearchserverless_access_policy" "data_access" {
  name        = "${local.collection_name}-access"
  type        = "data"
  description = "Data plane access for ${local.collection_name}"

  # AOSS rejects a statement whose Principal array is empty, so the
  # read-only statement is only emitted when there's actually a principal
  # to put in it.
  policy = jsonencode(concat(
    [
      {
        Rules = [
          {
            ResourceType = "collection"
            Resource     = ["collection/${local.collection_name}"]
            Permission = [
              "aoss:CreateCollectionItems",
              "aoss:DeleteCollectionItems",
              "aoss:UpdateCollectionItems",
              "aoss:DescribeCollectionItems"
            ]
          },
          {
            ResourceType = "index"
            Resource     = ["index/${local.collection_name}/*"]
            Permission = [
              "aoss:CreateIndex",
              "aoss:DeleteIndex",
              "aoss:UpdateIndex",
              "aoss:DescribeIndex",
              "aoss:ReadDocument",
              "aoss:WriteDocument"
            ]
          }
        ]
        Principal = var.data_access_principal_arns
      }
    ],
    length(var.read_only_principal_arns) > 0 ? [
      {
        Rules = [
          {
            ResourceType = "collection"
            Resource     = ["collection/${local.collection_name}"]
            Permission   = ["aoss:DescribeCollectionItems"]
          },
          {
            ResourceType = "index"
            Resource     = ["index/${local.collection_name}/*"]
            Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
          }
        ]
        Principal = var.read_only_principal_arns
      }
    ] : []
  ))
}

##############################################
# The collection itself
##############################################
resource "aws_opensearchserverless_collection" "this" {
  name             = local.collection_name
  type             = var.collection_type
  description      = "Vector store for complaint embeddings — complaints RAG platform (${var.environment})"
  standby_replicas = var.standby_replicas

  tags = local.common_tags

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}
