##############################################
# Security group shared by all interface endpoints
##############################################
resource "aws_security_group" "endpoints" {
  count       = var.create_interface_endpoints ? 1 : 0
  name        = "${local.name}-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-vpce-sg" })
}

##############################################
# S3 gateway endpoint — free, attaches to route tables directly.
# Used for complaint data landing in S3 (Layer 1 ingestion).
##############################################
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(local.common_tags, { Name = "${local.name}-s3-endpoint" })
}

data "aws_region" "current" {}

##############################################
# Interface endpoints — Secrets Manager, Bedrock Runtime, STS, CloudWatch Logs.
# Once the embedding/retrieval Lambdas are attached to these private subnets
# they lose the default internet route; these keep the calls they need
# (invoke Bedrock Titan embeddings, assume roles, read secrets, ship logs)
# on the AWS network instead of requiring the NAT Gateway.
##############################################
locals {
  interface_endpoint_services = var.create_interface_endpoints ? [
    "secretsmanager",
    "bedrock-runtime",
    "sts",
    "logs",
  ] : []
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoint_services)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${local.name}-${each.value}-endpoint" })
}
