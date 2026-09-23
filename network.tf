module "network" {
  source = "./modules/network"

  name_prefix                = var.name_prefix
  environment                 = var.environment
  vpc_cidr                    = var.vpc_cidr
  az_count                    = var.az_count
  single_nat_gateway          = var.single_nat_gateway
  create_interface_endpoints  = true
  tags                        = var.tags
}
