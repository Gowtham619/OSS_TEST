# terraform-aoss-complaints-rag

Terraform module that provisions **Amazon OpenSearch Serverless (AOSS)** as
the Vector Store layer (Layer 3) of the Complaints RAG Platform, per the
greenfield architecture: Data Ingestion → ML Processing & Embedding →
**Vector Store** → Retrieval & Routing → User Interface.

This module covers the Phase 2 vector store option from the architecture
paper (OpenSearch Serverless), as a drop-in replacement path from the
Phase 1 S3 Vectors option once query volume or recall requirements justify
the move.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_opensearchserverless_collection` | The `VECTORSEARCH` collection holding complaint embeddings |
| `aws_opensearchserverless_security_policy` (encryption) | At-rest encryption, AWS-owned or customer KMS key |
| `aws_opensearchserverless_security_policy` (network) | Restricts the collection to a VPC endpoint (default) or public+IAM |
| `aws_opensearchserverless_access_policy` | Data-plane CRUD policy, split into read-write and read-only principals |
| `aws_opensearchserverless_vpc_endpoint` + security group | Private connectivity from the complaints platform VPC |
| `aws_iam_role` + policy | Assumable role for the embedding Lambda / Bedrock knowledge base to call the AOSS data API |

## What it does **not** create

- **Indexes.** AOSS indexes (mappings, `knn_vector` field dimensions, HNSW
  parameters) are not managed by the `aws` Terraform provider. Create them
  post-apply with the `opensearch` provider, a Lambda-backed custom
  resource, or a CI step that calls the collection endpoint directly. See
  `examples/index-bootstrap-note.md`-style guidance in your embedding
  Lambda's deploy pipeline — this is intentionally left out of the Terraform
  layer so index schema changes don't require a `terraform apply`.
- **Bedrock Knowledge Base resource itself** — this module only creates the
  IAM role and AOSS access needed for one to be pointed at the collection.
- **The embedding/retrieval Lambdas** (Layer 2 and 4) — pass their execution
  role ARNs into `data_access_principal_arns`.

## Usage

```hcl
module "complaints_vector_store" {
  source = "./terraform-aoss-complaints-rag"

  name_prefix          = "complaints-rag"
  environment          = "prod"
  network_access_type  = "vpc"
  vpc_id               = var.vpc_id
  subnet_ids           = var.private_subnet_ids
  standby_replicas     = "ENABLED"

  data_access_principal_arns = [
    aws_iam_role.embedding_lambda.arn,
    aws_iam_role.retrieval_lambda.arn,
  ]
}
```

See `examples/complaints-rag-vector-store/main.tf` for a full example.

## Key variables

| Variable | Default | Notes |
|---|---|---|
| `collection_type` | `VECTORSEARCH` | Keep as-is for the embedding/retrieval use case |
| `standby_replicas` | `DISABLED` | Set `ENABLED` in prod for Multi-AZ (~2x OCU cost) |
| `network_access_type` | `vpc` | Use `public` only for early dev spikes; PII/complaint data should stay on `vpc` |
| `data_access_principal_arns` | — (required) | Roles needing read+write on the collection/indexes |
| `kms_key_arn` | `null` | Supply a CMK if your data classification requires customer-managed keys |

## Cost note

AOSS bills per OCU-hour (compute) plus storage, not per-node like managed
OpenSearch. At the platform's stated baseline (200 complaints/day, 900k
every 6 months) a single indexing + single search OCU pair (no standby)
is normally sufficient; re-evaluate `standby_replicas` and OCU limits
against the 20,000/day scale target before that migration.

## Outputs

`collection_endpoint` and `aoss_access_role_arn` are the two values the
embedding Lambda (Layer 2) and retrieval Lambda (Layer 4) need injected as
environment variables / IAM role assumptions.
