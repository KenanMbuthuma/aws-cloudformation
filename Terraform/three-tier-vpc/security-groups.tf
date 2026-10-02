# Security groups express the intended tier-to-tier flow. Rules are separate
# resources, following current AWS provider guidance and avoiding inline-rule
# ownership conflicts.
resource "aws_security_group" "web" {
  name_prefix = "${local.name_prefix}-web-"
  description = "Web tier: public HTTP and HTTPS ingress"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-web-sg"
    Tier = "public-web"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "application" {
  name_prefix = "${local.name_prefix}-application-"
  description = "Application tier: ingress only from the web tier"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-application-sg"
    Tier = "private-application"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-database-"
  description = "Database tier: database ingress only from the application tier"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-database-sg"
    Tier = "isolated-database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  for_each = toset(var.web_ingress_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  for_each = toset(var.web_ingress_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "application_from_web" {
  security_group_id            = aws_security_group.application.id
  description                  = "Application traffic from web tier"
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
  security_group_id            = aws_security_group.database.id
  description                  = "Database traffic from application tier"
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
}

# Web and application instances can initiate outbound traffic for updates,
# external APIs, and AWS services. The database group intentionally has no
# egress rule; security groups remain stateful for responses to allowed ingress.
resource "aws_vpc_security_group_egress_rule" "web" {
  security_group_id = aws_security_group.web.id
  description       = "Web tier outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "application" {
  security_group_id = aws_security_group.application.id
  description       = "Application tier outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

