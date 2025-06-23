variable "vpcs" {
    type = map(object({
        cidr_block  = string
        region      = string
        ami_id      = string
        subnets     = map(object({
            cidr_block   = string
            server_count = number
            availability_zone = string
        }))
    }))
    default = {
        vpc-us-east-1 = {
            region              = "us-east-1"
            ami_id              = "ami-020cba7c55df1f615"
            cidr_block          = "10.0.0.0/16"
            subnets = {
                subnet-us-east-1a = {
                    cidr_block      = "10.0.0.0/24"
                    server_count    = 1
                    availability_zone = "us-east-1a"
                }
                subnet-us-east-1b = {
                    cidr_block      = "10.0.1.0/24"
                    server_count    = 1
                    availability_zone = "us-east-1b"
                }                
            }
        },
        vpc-us-east-2 = {
            region              = "us-east-2"
            ami_id              = "ami-0d1b5a8c13042c939"
            cidr_block          = "10.1.0.0/16"
            subnets = {
                subnet-us-east-2a = {
                    cidr_block      = "10.1.0.0/24"
                    server_count    = 1
                    availability_zone = "us-east-2a"
                }
            }
        },        
        vpc-us-west-2 = {
            region              = "us-west-2"
            ami_id              = "ami-05f991c49d264708f"
            cidr_block          = "10.5.0.0/16"
            subnets = {
                subnet-us-west-2a = {
                    cidr_block      = "10.5.0.0/24"
                    server_count    = 1
                    availability_zone = "us-west-2a"
                }
            }
        }
    }
}

variable "instance_type" { 
    type = string 
    default = "t2.small"
}

variable "instance_key" { 
    type = string 
    default = "test-key"
}

variable "master_ami_id" { 
    type = string 
    default = "ami-020cba7c55df1f615"
}

variable "master_vpc_cidr" { 
    type = string 
    default = "10.50.0.0/16"
}

variable "master_subnet_cidr" {
    type = string
    default = "10.50.0.0/24"
}

variable "master_availability_zone" {
    type = string
    default = "us-east-1a"
}
