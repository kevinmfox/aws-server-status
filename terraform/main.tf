# this terraform script creates the 'master' server and all its related components
# if you want to update those variables (for the master), take a look at anything
##  in the variables.tf file with a prefix of 'master_'
# this script will also launch modules for each region you want to deploy children into
# us-east-2 and us-west-2 are commented out to start
# there's a 'vpcs' variable in variables.tf that controls subnets, server counts, vpcs, etc. 
##  for each region. That will need to be checked/updated before launching.
# the servers will pull relevant scripts from a github repo, and install/start those automatically
# if you decide to add another region:
##  update the provider block below to include it
##  update the 'vpcs' variable in variables.tf to include it
##  copy a module block below to include it
##  run terraform init to add it

provider "aws" {
    alias  = "us-east-1"
    region = "us-east-1"
}

provider "aws" {
    alias  = "us-east-2"
    region = "us-east-2"
}

provider "aws" {
    alias  = "us-west-2"
    region = "us-west-2"
}

locals {
    vpc_regions = distinct([for v in var.vpcs : v.region])

    vpcs_by_region = {
        for region in local.vpc_regions :
        region => { for k, v in var.vpcs : k => v if v.region == region }
    }
}

module "us_east_1" {
    source = "./modules/"
    for_each = local.vpcs_by_region["us-east-1"]

    name            = each.key
    cidr_block      = each.value.cidr_block
    subnets         = each.value.subnets
    ami_id          = each.value.ami_id
    instance_type   = var.instance_type
    instance_key    = var.instance_key
    master_ip       = aws_eip.master.public_ip
    depends_on      = [ aws_eip.master ]

    providers = {
        aws = aws.us-east-1
    }
}

module "us_east_2" {
    source = "./modules/"
    for_each = local.vpcs_by_region["us-east-2"]

    name            = each.key
    cidr_block      = each.value.cidr_block
    subnets         = each.value.subnets
    ami_id          = each.value.ami_id
    instance_type   = var.instance_type
    instance_key    = var.instance_key
    master_ip       = aws_eip.master.public_ip
    depends_on      = [ aws_eip.master ]

    providers = {
        aws = aws.us-east-2
    }
}

module "us_west_2" {
    source = "./modules/"
    for_each = local.vpcs_by_region["us-west-2"]

    name            = each.key
    cidr_block      = each.value.cidr_block
    subnets         = each.value.subnets
    ami_id          = each.value.ami_id
    instance_type   = var.instance_type
    instance_key    = var.instance_key
    master_ip       = aws_eip.master.public_ip
    depends_on      = [ aws_eip.master ]

    providers = {
        aws = aws.us-west-2
    }
}

resource "aws_vpc" "vpc" {
    cidr_block = var.master_vpc_cidr
    enable_dns_hostnames = true

    tags = {
        Name = "master-vpc"
    }
}

resource "aws_subnet" "public_subnet" {
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = var.master_subnet_cidr
    availability_zone       = var.master_availability_zone
    map_public_ip_on_launch = true    
    
    tags = {
        Name = "master-subnet"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id
    tags = {
        Name = "master-igw"
    }
}

resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "master-public-rt"
    }
}

resource "aws_route_table_association" "public_assoc" {
    subnet_id      = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "master" {
    name        = "master"
    description = "Allow SSH, ICMP, HTTP, MySQL"
    vpc_id      = aws_vpc.vpc.id

    ingress {
        description = "SSH"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow ICMP PING"
    }

    ingress {
        description = "HTTP"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

        ingress {
        description = "MySQL"
        from_port   = 3306
        to_port     = 3306
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_iam_role" "ece_instance_role" {
    name = "ece-instance-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
            Action = "sts:AssumeRole",
            Effect = "Allow",
            Principal = {
                Service = "ec2.amazonaws.com"
            }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "ece_readonly_policy" {
    role       = aws_iam_role.ece_instance_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_policy" "ece_custom_read_policy" {
    name        = "ece-read-ec2"
    description = "Allow read-only access to EC2, VPCs, and Subnets"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
        {
            Effect = "Allow",
            Action = [
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeTags"
            ],
            Resource = "*"
        }]
    })
}

resource "aws_iam_role_policy_attachment" "ece_custom_policy_attach" {
    role       = aws_iam_role.ece_instance_role.name
    policy_arn = aws_iam_policy.ece_custom_read_policy.arn
}

resource "aws_iam_instance_profile" "ece_instance_profile" {
    name = "ece-instance-profile"
    role = aws_iam_role.ece_instance_role.name
}

resource "aws_eip" "master" {
    instance  = aws_instance.master.id
    domain    = "vpc"
    tags = {
        Name = "master"
    }
}

resource "aws_instance" "master" {
    ami                     = var.master_ami_id
    instance_type           = var.instance_type
    subnet_id               = aws_subnet.public_subnet.id
    vpc_security_group_ids  = [aws_security_group.master.id]
    key_name                = var.instance_key
    iam_instance_profile    = aws_iam_instance_profile.ece_instance_profile.name

    tags = {
        Name = "master"
    }

    user_data = templatefile("${path.module}/cloud-init-master.sh", {
        new_hostname = "master"
    })
}

output "master_eip" {
    value       = "http://${aws_eip.master.public_ip}"
    description = "Master server HTTP app"
}