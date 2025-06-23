variable "cidr_block" { type = string }
variable "name" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "instance_key" { type = string }
variable "master_ip" { type = string }

variable "subnets" {
    type = map(object({
        cidr_block         = string
        server_count       = number
        availability_zone  = string
    }))
}
