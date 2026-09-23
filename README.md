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

## Testing ingestion (throwaway Lambda, fully Terraform-managed)

Set `deploy_ingestion_test_lambda = true` in `terraform.tfvars`, then:

```bash
terraform apply -var-file=terraform.tfvars
```

This adds a small Lambda (`<name_prefix>-<environment>-ingestion-test`) that
reuses the embedding Lambda's IAM role and VPC config — it gets a real
embedding from Bedrock Titan, then writes and searches a test document in
whichever store(s) you deployed. Invoke it:

```bash
FUNC=$(terraform output -raw ingestion_test_lambda_name)
aws lambda invoke --function-name "$FUNC" --region "$(terraform output -raw region 2>/dev/null || echo eu-west-1)" response.json
cat response.json | python3 -m json.tool
```

A working run shows `embedding_dimensions: 1024`, and under `aoss`/`cluster`
keys: `create_index` (200, or 400 on a rerun — fine), `index_doc` (201), and
`search` (200) with the test complaint text echoed back.

**Tear it down** the same way you brought it up — no manual `aws lambda
delete-function`:

```bash
# in terraform.tfvars: deploy_ingestion_test_lambda = false
terraform apply -var-file=terraform.tfvars
```

The Lambda, its CloudWatch log group, and the zip Terraform built for it are
all removed. It never modifies your real embedding/retrieval Lambda roles —
it only reads their ARN and VPC config.

## Query API — public HTTP endpoint for the frontend

Toggle with `deploy_query_api = true`. Deploys a Lambda (reusing the retrieval
role's IAM permissions) behind an API Gateway HTTP API:

```bash
terraform output query_api_url
# POST {"query_text": "..."} to this URL — embeds the query via Bedrock Titan,
# runs a k-NN similarity search against whichever store(s) are deployed,
# returns the top matches from each.
```

CORS currently allows `*` (see `frontend_cors_origins` in `auth.tf`) —
tighten this to your real frontend's origin before this is anything more
than a dev/test endpoint.

## Frontend — React app on ECS Fargate

Toggle with `deploy_frontend_fargate = true`. Deploys an ECR repo, ECS
Fargate cluster/service (ARM64/Graviton by default — matches Apple Silicon
builds), and a public ALB. See the companion `complaints-rag-frontend`
repo for the actual application and its own deploy instructions.

```bash
terraform output frontend_alb_dns_name        # public URL, HTTP only right now
terraform output frontend_ecr_repository_url  # docker push target
```

**Before production:** set `acm_certificate_arn` for HTTPS — this currently
serves plain HTTP.

## Authentication — Cognito federated to PingFederate (SAML)

Toggle with `enable_pingfederate_auth = true` (see `auth.tf`). PingFederate
only issues SAML assertions, so Cognito sits in between as a broker: it
federates to PingFederate via SAML, issues its own JWT after a successful
login, and API Gateway validates that JWT on the query API's route.

This requires out-of-band coordination with your PingFederate admin — see
the comments at the top of `auth.tf` for the exact handshake (their
metadata in, `pingfederate_sp_acs_url` / `pingfederate_sp_entity_id` out).
**Not yet activated in this deployment** — the React frontend doesn't yet
redirect through Cognito's Hosted UI or attach a JWT to its requests; the
Terraform side is ready and waiting.

## Ingestion test Lambda — disposable, Terraform-managed

Toggle with `deploy_ingestion_test_lambda = true`. Same Lambda also
supports a query mode for manual testing:

```bash
FUNC=$(terraform output -raw ingestion_test_lambda_name)

# ingestion self-test (create index, write a doc, search)
aws lambda invoke --function-name "$FUNC" --region eu-west-1 response.json

# real semantic query
aws lambda invoke --function-name "$FUNC" --region eu-west-1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"query_text": "my card was used without my permission"}' \
  query_response.json
```

## Current deployment status (as of this writing)

- ✅ `vector_store_type = "both"` — AOSS and the cluster domain are both
  live simultaneously (fine for comparison; pick one before anything
  resembling steady-state production, given the OpenSearch cluster's
  always-on instance cost)
- ✅ Query API, ingestion test Lambda, and the React frontend on Fargate
  are all deployed and verified working end to end
- ⏳ `test-complaints` index still contains only placeholder test data on
  both stores — clear it before pointing this at anything real
- ⏳ PingFederate auth is built but not activated (see above)
- ⏳ HTTPS not yet configured on either the query API custom domain or the
  frontend ALB

## Tearing down

```bash
terraform destroy -var-file=terraform.tfvars
```

Note the OpenSearch service-linked role (if you set
`create_opensearch_service_linked_role = true`) is account-wide; destroying
this stack won't remove it, and it shouldn't be removed if other domains
in the account still depend on it.
