output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "availability_zones" {
  value = local.azs
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "endpoints_security_group_id" {
  value = var.create_interface_endpoints ? aws_security_group.endpoints[0].id : null
}
