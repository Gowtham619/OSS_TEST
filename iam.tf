module "iam" {
  source = "./modules/iam"

  name_prefix           = var.name_prefix
  environment           = var.environment
  bedrock_model_arns    = var.bedrock_model_arns
  admin_principal_arns  = var.admin_principal_arns
  tags                  = var.tags
}
