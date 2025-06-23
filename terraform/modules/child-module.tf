terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
        }
    }
}

resource "aws_vpc" "vpc" {
    cidr_block = var.cidr_block
    enable_dns_hostnames = true

    tags = {
        Name = var.name
    }
}

resource "aws_subnet" "public_subnet" {
    for_each                = var.subnets
    
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = each.value.cidr_block
    availability_zone       = each.value.availability_zone
    map_public_ip_on_launch = true    
    
    tags = {
        Name = "${each.key}"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id
    tags = {
        Name = "${var.name}-igw"
    }
}

resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "${var.name}-public-rt"
    }
}

resource "aws_route_table_association" "public_assoc" {
    for_each       = var.subnets

    subnet_id      = aws_subnet.public_subnet[each.key].id
    route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "sg-child" {
    name        = "${var.name}-sg"
    description = "Allow SSH, ICMP"
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

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

locals {
    instance_defs = flatten([
        for subnet_key, subnet in var.subnets : [
            for i in range(subnet.server_count) : {
                key         = "${subnet_key}-${i}"
                subnet_id   = aws_subnet.public_subnet[subnet_key].id
                subnet_name = subnet_key
                subnet_zone = subnet.availability_zone
                index       = i
            }
        ]
    ])

    instance_map = {
        for inst in local.instance_defs :
            inst.key => {
                subnet_id   = inst.subnet_id
                subnet_name = inst.subnet_name
                subnet_zone = inst.subnet_zone
                index       = inst.index
            }
    }
}

resource "aws_instance" "child" {
    for_each = local.instance_map

    ami                     = var.ami_id
    instance_type           = var.instance_type
    subnet_id               = each.value.subnet_id
    vpc_security_group_ids  = [aws_security_group.sg-child.id]
    key_name                = var.instance_key

    tags = {
        Name = "child-${each.value.subnet_zone}-${each.value.index}"
    }

    user_data = templatefile("${path.module}/../cloud-init-child.sh", {
        new_hostname = "child-${each.value.subnet_zone}-${each.value.index}"
        master_ip = var.master_ip
    })
}

output "vpc_id" {
    value = aws_vpc.vpc.id
}