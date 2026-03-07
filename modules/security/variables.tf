variable "vpc_id" {
  type        = string      # The type of the variable, in this case a string
  description = "속한 VPC ID" # Description of what this variable represents
}

variable "sg" {
  type = map(
    object({
      name=string
    })
  )
}

variable "sg_rules" {
  type = list(object({
    sg_key      = string   # web / db
    type        = string   # ingress or egress
    from_port   = number
    to_port     = number
    protocol    = optional(string,"tcp")
    cidr_blocks = optional(list(string), [])
    description = optional(string, null)
    source_sg_key=optional(string,null)
  }))
}