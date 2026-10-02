output "vpc_id" {
  description = "ID of the three-tier VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability Zones used by all three tiers."
  value       = local.availability_zones
}

output "public_subnet_ids" {
  description = "Public web-tier subnet IDs keyed by Availability Zone."
  value       = zipmap(local.availability_zones, aws_subnet.public[*].id)
}

output "application_subnet_ids" {
  description = "Private application-tier subnet IDs keyed by Availability Zone."
  value       = zipmap(local.availability_zones, aws_subnet.application[*].id)
}

output "database_subnet_ids" {
  description = "Isolated database-tier subnet IDs keyed by Availability Zone."
  value       = zipmap(local.availability_zones, aws_subnet.database[*].id)
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs used by the private application tier."
  value       = aws_nat_gateway.this[*].id
}

output "database_subnet_group_name" {
  description = "RDS/Aurora subnet group covering the isolated database tier."
  value       = aws_db_subnet_group.database.name
}

output "security_group_ids" {
  description = "Security group IDs for the web, application, and database tiers."
  value = {
    web         = aws_security_group.web.id
    application = aws_security_group.application.id
    database    = aws_security_group.database.id
  }
}

output "route_table_ids" {
  description = "Route table IDs for each network tier."
  value = {
    public      = [aws_route_table.public.id]
    application = aws_route_table.application[*].id
    database    = aws_route_table.database[*].id
  }
}

