locals {
  sg_rules = [
    # alb-sg inbound
    {
      sg_key    = "alb_sg"
      type      = "ingress"
      from_port = 80
      to_port   = 80
      protocol  = "tcp"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      description = "HTTP from internet"
    },
    {
      sg_key    = "alb_sg"
      type      = "ingress"
      from_port = 443
      to_port   = 443
      protocol  = "tcp"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      description = "HTTPS from internet"
    },

    # alb-sg outbound -> app-sg:8080
    {
      sg_key        = "alb_sg"
      type          = "egress"
      from_port     = 8080
      to_port       = 8080
      protocol      = "tcp"
      source_sg_key = "app_sg"
      description   = "To app-sg 8080"
    },

    # app-sg inbound <- alb-sg:8080
    {
      sg_key        = "app_sg"
      type          = "ingress"
      from_port     = 8080
      to_port       = 8080
      protocol      = "tcp"
      source_sg_key = "alb_sg"
      description   = "From alb-sg 8080"
    },

    # app-sg outbound -> db-sg:3306
    {
      sg_key        = "app_sg"
      type          = "egress"
      from_port     = 3306
      to_port       = 3306
      protocol      = "tcp"
      source_sg_key = "db_sg"
      description   = "To db-sg 3306"
    },

    # app-sg outbound -> internet:443
    {
      sg_key    = "app_sg"
      type      = "egress"
      from_port = 443
      to_port   = 443
      protocol  = "tcp"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
      description = "HTTPS to internet"
    },

    # db-sg inbound <- app-sg:3306
    {
      sg_key        = "db_sg"
      type          = "ingress"
      from_port     = 3306
      to_port       = 3306
      protocol      = "tcp"
      source_sg_key = "app_sg"
      description   = "From app-sg 3306"
    }
  ]

  security_groups = {
    alb_sg = { name = "alb_sg" }
    app_sg = { name = "app_sg" }
    db_sg  = { name = "db_sg" }
  }
}
