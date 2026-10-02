variable "aws_region" {
  description = "AWS Region in which to create the VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS Region name, for example af-south-1."
  }
}

variable "project_name" {
  description = "Short lowercase name used in resource names and tags."
  type        = string
  default     = "three-tier"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, numbers, or hyphens and cannot end with a hyphen."
  }
}

variable "environment" {
  description = "Environment name added to resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.environment))
    error_message = "environment must be 3-16 lowercase letters, numbers, or hyphens and cannot end with a hyphen."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC. Use an RFC1918 range with a /16 through /20 prefix."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }

  validation {
    condition = can(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 20
    )
    error_message = "vpc_cidr must use a prefix between /16 and /20 so the module can create /24 tier subnets."
  }
}

variable "availability_zone_count" {
  description = "Number of Availability Zones to use. Two is cost-conscious; three provides greater resilience."
  type        = number
  default     = 2

  validation {
    condition     = contains([2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be either 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway to reduce cost. Set false for one NAT gateway per AZ and higher availability."
  type        = bool
  default     = false
}

variable "web_ingress_cidrs" {
  description = "IPv4 networks permitted to reach HTTP and HTTPS on the web-tier security group."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.web_ingress_cidrs) > 0 && alltrue([for cidr in var.web_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "web_ingress_cidrs must contain at least one valid IPv4 CIDR block."
  }
}

variable "application_port" {
  description = "TCP port accepted by the application tier from the web tier."
  type        = number
  default     = 8080

  validation {
    condition     = var.application_port >= 1 && var.application_port <= 65535
    error_message = "application_port must be between 1 and 65535."
  }
}

variable "database_port" {
  description = "TCP port accepted by the database tier from the application tier. Defaults to PostgreSQL."
  type        = number
  default     = 5432

  validation {
    condition     = var.database_port >= 1 && var.database_port <= 65535
    error_message = "database_port must be between 1 and 65535."
  }
}

variable "additional_tags" {
  description = "Additional tags applied to every supported AWS resource."
  type        = map(string)
  default     = {}
}

