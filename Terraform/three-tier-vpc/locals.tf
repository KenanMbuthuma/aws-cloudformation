locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # The first two or three available AZs are used consistently for every tier.
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    var.availability_zone_count
  )

  # All tiers use /24s. Net numbers are separated by tier to prevent overlap.
  vpc_prefix_bits = tonumber(split("/", var.vpc_cidr)[1])
  subnet_new_bits = 24 - local.vpc_prefix_bits

  public_subnet_cidrs = [
    for index in range(var.availability_zone_count) :
    cidrsubnet(var.vpc_cidr, local.subnet_new_bits, index)
  ]

  application_subnet_cidrs = [
    for index in range(var.availability_zone_count) :
    cidrsubnet(var.vpc_cidr, local.subnet_new_bits, index + var.availability_zone_count)
  ]

  database_subnet_cidrs = [
    for index in range(var.availability_zone_count) :
    cidrsubnet(var.vpc_cidr, local.subnet_new_bits, index + (var.availability_zone_count * 2))
  ]
}

