locals {
  deploy_serverless = contains(["serverless", "both"], var.vector_store_type)
  deploy_cluster    = contains(["cluster", "both"], var.vector_store_type)

  vector_store_principals = [
    module.iam.embedding_lambda_role_arn,
    module.iam.retrieval_lambda_role_arn,
  ]

  # Same as above, plus the admin role — used for full read/write access
  # from manual testing (e.g. an assumed-role ingestion test script), so
  # the admin role can write to AOSS the same way it already can to the
  # cluster domain (as its fine-grained-access-control master user).
  aoss_data_access_principals = concat(local.vector_store_principals, [module.iam.admin_role_arn])
}

module "vector_store_aoss" {
  count  = local.deploy_serverless ? 1 : 0
  source = "./modules/vector-store-aoss"

  name_prefix          = var.name_prefix
  environment          = var.environment
  standby_replicas     = var.aoss_standby_replicas
  network_access_type  = "vpc"

  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  vpc_endpoint_ingress_cidrs = [module.network.vpc_cidr_block]

  data_access_principal_arns = local.aoss_data_access_principals
  read_only_principal_arns   = var.admin_principal_arns

  create_bedrock_access_role = true

  tags = var.tags
}

module "vector_store_cluster" {
  count  = local.deploy_cluster ? 1 : 0
  source = "./modules/vector-store-cluster"

  name_prefix = var.name_prefix
  # keep names distinct when both are deployed side by side
  environment = local.deploy_serverless ? "${var.environment}-cluster" : var.environment

  create_service_linked_role = var.create_opensearch_service_linked_role

  instance_type             = var.cluster_instance_type
  instance_count            = var.cluster_instance_count
  zone_awareness_enabled    = var.az_count > 1
  availability_zone_count   = var.az_count
  dedicated_master_enabled  = var.cluster_dedicated_master_enabled

  ebs_volume_size_gb = var.cluster_ebs_volume_size_gb

  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  vpc_endpoint_ingress_cidrs = [module.network.vpc_cidr_block]

  master_user_arn = module.iam.admin_role_arn

  data_access_principal_arns = local.vector_store_principals

  tags = var.tags
}