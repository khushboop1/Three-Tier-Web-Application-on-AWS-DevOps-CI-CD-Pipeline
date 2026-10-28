data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]       # 10.0.0.0/24, 10.0.1.0/24
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]  # 10.0.10.0/24, 10.0.11.0/24

  enable_nat_gateway   = true
  single_nat_gateway   = true   # cheaper; use one per AZ for production HA
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags so Kubernetes can place load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb"                              = "1"
    "kubernetes.io/cluster/${var.project}-eks"            = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                     = "1"
    "kubernetes.io/cluster/${var.project}-eks"            = "shared"
  }
}
