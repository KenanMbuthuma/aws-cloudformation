provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        ManagedBy   = "Terraform"
        Project     = var.project_name
        Environment = var.environment
      },
      var.additional_tags
    )
  }
}

# Only Availability Zones currently available to the account are selected.
data "aws_availability_zones" "available" {
  state = "available"
}

