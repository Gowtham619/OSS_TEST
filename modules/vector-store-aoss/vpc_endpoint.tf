##############################################
# Security group for the AOSS VPC endpoint
# Only created when the caller doesn't supply their own SGs.
##############################################
resource "aws_security_group" "aoss_endpoint" {
  count = local.use_vpc && length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${local.collection_name}-aoss-endpoint-sg"
  description = "Allow HTTPS to AOSS VPC endpoint for ${local.collection_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = length(var.vpc_endpoint_ingress_cidrs) > 0 ? var.vpc_endpoint_ingress_cidrs : ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.collection_name}-aoss-endpoint-sg"
  })
}

##############################################
# VPC endpoint for private AOSS access
##############################################
resource "aws_opensearchserverless_vpc_endpoint" "this" {
  count = local.use_vpc ? 1 : 0

  name       = "${local.collection_name}-vpce"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.aoss_endpoint[0].id]
}
