# terraform-opensearch-domain-complaints-rag

Terraform module that provisions a **managed OpenSearch domain (cluster-based)**
as an alternative to OpenSearch Serverless for the Complaints RAG Platform's
Vector Store layer (Layer 3).

## Serverless vs. cluster-based — when to use this one

| | AOSS (serverless) | This module (cluster-based) |
|---|---|---|
| Ops overhead | None — AWS manages capacity | You size and manage nodes, storage, shards |
| Cost model | Per OCU-hour, scales to near-zero | Fixed instance-hours, always-on |
| k-NN/vector tuning | Limited engine control | Full control (HNSW params, engine, shard count) |
| Best fit | Baseline 200/day, unpredictable/bursty load | Sustained high query volume approaching the 20,000/day scale target, or where you need fine-grained OpenSearch Security (index-level roles, field-level security) |

Both modules target the same architecture slot — swap one for the other
without changing Layers 1, 2, 4 or 5.

## What it creates

- `aws_opensearch_domain` — VPC-only (no public option; this platform handles PII)
- Dedicated master nodes + zone awareness across the VPC's AZs
- `gp3` EBS storage per data node
- Encryption at rest (AWS-managed or your KMS key) and node-to-node encryption
- Fine-grained access control with an **IAM master user** (not an internal username/password)
- A resource-based access policy for `data_access_principal_arns`
- CloudWatch Logs for index/search slow logs and application logs, with the resource policy OpenSearch needs to write to them
- Optionally, the account-wide `AWSServiceRoleForAmazonOpenSearchService` service-linked role

## Important one-time setup

VPC-based OpenSearch domains require the
`AWSServiceRoleForAmazonOpenSearchService` service-linked role, which is
**one per AWS account**, not one per domain. Set
`create_service_linked_role = true` on your *first* domain deployment in an
account/region, and `false` on every subsequent module call — a second
`true` will fail with `EntityAlreadyExists`.

## What it does not create

- **Index-level OpenSearch Security roles/role-mappings** (as opposed to the
  IAM-level domain access policy). Configure these in Dashboards, or via the
  `opensearch` community Terraform provider, once the domain and your
  `knn_vector` index mappings exist.
- **The k-NN index itself** — create it through your embedding Lambda's
  deploy step or an `opensearch` provider index resource, same as the AOSS
  module.

## Sizing note

`r6g.large.search` data nodes + `m6g.large.search` masters is a reasonable
starting point for the 200/day baseline with the 900k/6-month historical
load. Re-benchmark instance type/count before the 20,000/day (100x) scale
target — vector search is typically more memory-bound than traditional
text search, so watch `r`-family memory headroom, not just CPU.

## Usage

See `examples/complaints-rag-cluster/main.tf`.
