locals {
  # Build a flat list of { az, cidr, type } objects so we can loop cleanly
  public_subnets = [
    for i, cidr in var.public_subnet_cidrs : {
      az   = var.availability_zones[i % length(var.availability_zones)]
      cidr = cidr
    }
  ]

  private_subnets = [
    for i, cidr in var.private_subnet_cidrs : {
      az   = var.availability_zones[i % length(var.availability_zones)]
      cidr = cidr
    }
  ]

  common_tags = merge(var.tags, {
    Project   = var.project
    ManagedBy = "terraform"
  })
}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# ─────────────────────────────────────────────
# Internet Gateway
# ─────────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# ─────────────────────────────────────────────
# Public Subnets
# ─────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index].cidr
  availability_zone       = local.public_subnets[count.index].az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"
    # Tag required by EKS to auto-discover public subnets for external Load Balancers
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ─────────────────────────────────────────────
# Private Subnets
# ─────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index].cidr
  availability_zone = local.private_subnets[count.index].az

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-private-${count.index + 1}"
    # Tag required by EKS to auto-discover private subnets for internal Load Balancers
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ─────────────────────────────────────────────
# NAT Gateway count: 1 when single_nat_gateway is
# true, otherwise one per AZ for high availability.
# ─────────────────────────────────────────────
locals {
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.availability_zones)
}

# ─────────────────────────────────────────────
# Elastic IPs for NAT Gateways
# ─────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ─────────────────────────────────────────────
# NAT Gateways  (placed in public subnets)
# ─────────────────────────────────────────────
resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ─────────────────────────────────────────────
# Public Route Table
# ─────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-rt-public"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────
# Private Route Tables  (one per AZ)
# Each routes 0.0.0.0/0 to a NAT Gateway. With a
# single NAT, all AZs route through NAT index 0;
# otherwise each AZ uses its own NAT.
# ─────────────────────────────────────────────
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-rt-private-${count.index + 1}"
  })
}

# Associate each private subnet with the route table of its AZ
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index % length(var.availability_zones)].id
}
