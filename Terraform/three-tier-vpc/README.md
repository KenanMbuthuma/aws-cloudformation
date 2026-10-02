# AWS three-tier VPC

This Terraform root module creates a production-oriented three-tier network in
two or three AWS Availability Zones.

```text
Internet
   |
Internet Gateway
   |
Public web subnets (HTTP/HTTPS security group, NAT gateways)
   |
Private application subnets (application port allowed from web SG)
   |
Isolated database subnets (database port allowed from application SG)
```

The public tier has a route to the Internet Gateway. The application tier has no
public IP assignment and sends outbound traffic through NAT. The database tier
has neither an Internet Gateway nor NAT default route. An RDS/Aurora DB subnet
group and security groups for the permitted web-to-app-to-database flow are also
created.

## Folder contents

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider constraints |
| `.terraform.lock.hcl` | Checked-in provider selection and integrity hashes |
| `providers.tf` | AWS provider, default tags, and AZ discovery |
| `variables.tf` | Typed, validated inputs |
| `locals.tf` | Names, selected AZs, and non-overlapping subnet CIDRs |
| `main.tf` | VPC, subnets, gateways, routes, and DB subnet group |
| `security-groups.tf` | Tier-to-tier security group rules |
| `outputs.tf` | IDs and maps consumed by application stacks |
| `terraform.tfvars.example` | Example deployment values |

No backend is hard-coded. Configure an S3/HCP Terraform backend according to
the organization's state-management standard before using this in a team.

## Addressing

The module accepts a `/16` through `/20` VPC CIDR and derives non-overlapping
`/24` subnets. With three AZs the allocation is:

| Tier | Net numbers for a `10.0.0.0/16` example |
|---|---|
| Public web | `10.0.0.0/24` through `10.0.2.0/24` |
| Private application | `10.0.3.0/24` through `10.0.5.0/24` |
| Isolated database | `10.0.6.0/24` through `10.0.8.0/24` |

Choose a VPC CIDR that does not overlap on-premises, peered VPCs, Transit
Gateway attachments, or other connected networks.

## Usage

Copy the example variables and edit every environment-specific value:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=three-tier-vpc.tfplan
terraform apply three-tier-vpc.tfplan
```

On PowerShell:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=three-tier-vpc.tfplan
terraform apply three-tier-vpc.tfplan
```

Terraform uses the normal AWS credential chain. Verify the intended identity
before applying:

```bash
aws sts get-caller-identity
```

## Important choices

- `single_nat_gateway = false` (default) creates a NAT gateway in each AZ for
  resilience and keeps application egress in-AZ. NAT gateways and their traffic
  incur charges.
- Set `single_nat_gateway = true` for non-production cost reduction. All private
  application subnets then depend on the first AZ's NAT gateway.
- `web_ingress_cidrs` defaults to public HTTP/HTTPS access. Restrict it when the
  entry point is internal or is reached only through known proxy/CDN addresses.
- The default application port is `8080`; the default database port is `5432`.
  Change them to match the deployed application and database engine.
- Database resources created elsewhere should use
  `database_subnet_group_name` and the database security group output.
- Database security-group egress is intentionally absent. Add a narrowly scoped
  egress rule if database agents or extensions must initiate outbound sessions.

## Production considerations

Before production deployment, configure remote state with encryption and
locking, restrict CI/CD permissions, review NAT cost and resilience, and run a
saved plan through the normal approval process. VPC Flow Logs, network firewall
inspection, IPv6, and VPC endpoints are environment-specific controls and are
therefore not enabled implicitly by this baseline.
