# terraform-complaints-rag-platform

Full, deployable-from-nothing stack for the Complaints RAG Platform's
Vector Store layer (Layer 3) and its immediate dependencies: networking
and the IAM roles Layers 2 and 4 need to reach it.

```
terraform-complaints-rag-platform/
├── modules/
│   ├── network/               VPC, public+private subnets, NAT, VPC endpoints
│   ├── iam/                   Lambda execution roles + admin role
│   ├── vector-store-aoss/     OpenSearch Serverless (from the earlier build)
│   └── vector-store-cluster/  Managed OpenSearch domain (from the earlier build)
├── network.tf / iam.tf / vector-store.tf   root module wiring
├── variables.tf / outputs.tf
└── terraform.tfvars.example
```

## What gets built

1. **Network** — a VPC across `az_count` AZs (default 3), public subnets
   with an Internet Gateway, private subnets with NAT Gateway egress, an
   S3 gateway endpoint, and interface endpoints for Secrets Manager,
   Bedrock Runtime, STS and CloudWatch Logs (so Lambdas in the private
   subnets don't need the NAT Gateway for those calls).
2. **IAM** — an execution role for the embedding Lambda (Layer 2), one for
   the retrieval Lambda (Layer 4) — both with VPC access, Bedrock
   `InvokeModel` on the Titan embedding models, and basic logging — plus an
   admin role used as the OpenSearch fine-grained-access-control master
   user.
3. **Vector store** — `vector_store_type` picks AOSS, the cluster-based
   domain, or both side by side (distinct names, no collision) for a bake-off.

Everything is wired together automatically: the vector store modules get
their `vpc_id`/`subnet_ids` from the network module and their
`data_access_principal_arns` from the IAM module's Lambda role ARNs.

## Deploying from zero

```bash
cd terraform-complaints-rag-platform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: region, admin_principal_arns at minimum

terraform init
terraform plan  -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

First apply order (Terraform resolves this automatically via the module
dependency graph, this is just what to expect watching it run):
VPC/subnets/NAT → IAM roles → AOSS security policies / OpenSearch
service-linked role → the collection or domain itself → VPC endpoint
attachment. NAT Gateways typically finish in ~1-2 minutes; the AOSS VPC
endpoint can take up to ~20-30 minutes; a cluster-based domain with
dedicated masters commonly takes 20-40 minutes total.

## Before you point real Lambdas at this

- Use `terraform output lambda_vpc_config` for the exact `vpc_config`
  (subnets + security group) your embedding/retrieval Lambda function
  resources need — they must run inside these private subnets to reach
  either vector store privately.
- `admin_principal_arns` defaults to account root if left empty. That's
  fine for a five-minute dev spike; replace it with real IAM
  users/roles before this touches anything with real complaint data.
- If you set `vector_store_type = "both"`, you'll be paying for a NAT
  Gateway, an AOSS collection *and* a 3-node-plus-3-master OpenSearch
  domain simultaneously — that's meant for a side-by-side bake-off, not
  a steady-state deployment. Pick one before prod.

## Cost shape (rough, `serverless` + `single_nat_gateway = true`, dev-sized)

- NAT Gateway: ~$0.045/hr + data processing
- Interface endpoints (4): ~$0.01/hr each + data processing
- AOSS: billed per OCU-hour actually used, no idle data-node cost
- The `cluster` option is always-on instance-hours instead — see that
  module's README for the sizing note before switching.

## Tearing down

```bash
terraform destroy -var-file=terraform.tfvars
```

Note the OpenSearch service-linked role (if you set
`create_opensearch_service_linked_role = true`) is account-wide; destroying
this stack won't remove it, and it shouldn't be removed if other domains
in the account still depend on it.
