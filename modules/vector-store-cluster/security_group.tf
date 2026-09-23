resource "aws_security_group" "domain" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${local.domain_name}-os-domain-sg"
  description = "Allow HTTPS to ${local.domain_name} OpenSearch domain"
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
    Name = "${local.domain_name}-os-domain-sg"
  })
}

locals {
  domain_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.domain[0].id]
}
