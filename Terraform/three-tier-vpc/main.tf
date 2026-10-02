# The VPC enables AWS DNS resolution so private resources can resolve both AWS
# service endpoints and private hosted-zone records.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Public internet access exists only through this gateway and the public route.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# Tier 1: public subnets for internet-facing load balancers, NAT gateways, or
# tightly controlled web hosts.
resource "aws_subnet" "public" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${local.availability_zones[count.index]}"
    Tier = "public-web"
  }
}

# Tier 2: private application subnets. Instances receive no public IP address;
# outbound internet traffic is routed through a NAT gateway.
resource "aws_subnet" "application" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = local.application_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-application-${local.availability_zones[count.index]}"
    Tier = "private-application"
  }
}

# Tier 3: isolated database subnets. Their route tables intentionally have no
# internet or NAT default route.
resource "aws_subnet" "database" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = local.database_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-database-${local.availability_zones[count.index]}"
    Tier = "isolated-database"
  }
}

# A single public route table is sufficient because every public subnet uses the
# same Internet Gateway in this VPC.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
    Tier = "public-web"
  }
}

resource "aws_route_table_association" "public" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# By default a NAT gateway is created in each AZ, avoiding a cross-AZ dependency
# and cross-AZ processing charges. single_nat_gateway trades resilience for cost.
resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : var.availability_zone_count

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : var.availability_zone_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${local.name_prefix}-nat-${local.availability_zones[count.index]}"
  }
}

# One application route table per AZ keeps each application subnet associated
# with its local NAT gateway in the highly available configuration.
resource "aws_route_table" "application" {
  count = var.availability_zone_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "${local.name_prefix}-application-${local.availability_zones[count.index]}-rt"
    Tier = "private-application"
  }
}

resource "aws_route_table_association" "application" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.application[count.index].id
  route_table_id = aws_route_table.application[count.index].id
}

# Database route tables contain only the VPC's implicit local route. Keeping one
# per AZ makes future inspection and controlled routing changes unambiguous.
resource "aws_route_table" "database" {
  count = var.availability_zone_count

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-database-${local.availability_zones[count.index]}-rt"
    Tier = "isolated-database"
  }
}

resource "aws_route_table_association" "database" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}

# This subnet group allows the isolated tier to be selected directly by Amazon
# RDS and Aurora resources created by an application stack.
resource "aws_db_subnet_group" "database" {
  name        = "${local.name_prefix}-database"
  description = "Isolated database subnets for ${local.name_prefix}"
  subnet_ids  = aws_subnet.database[*].id

  tags = {
    Name = "${local.name_prefix}-database"
    Tier = "isolated-database"
  }
}

