data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb" {
  name        = "mlops-alb-sg"
  description = "ALB inbound 80/443"
  vpc_id      = data.aws_vpc.default.id

  ingress { 
    from_port=80  
    to_port=80  
    protocol="tcp" 
    cidr_blocks=["0.0.0.0/0"] 
    }
  ingress { 
    from_port=443 
    to_port=443
    protocol="tcp" 
    cidr_blocks=["0.0.0.0/0"] 
    }
  egress  {
    from_port=0   
    to_port=0   
    protocol="-1"
    cidr_blocks=["0.0.0.0/0"] 
    }

  tags = { Project = "mlops-sklearn-portfolio" }
}

resource "aws_security_group" "tasks" {
  name        = "mlops-ecs-sg"
  description = "ECS tasks egress only"
  vpc_id      = data.aws_vpc.default.id

  egress { 
    from_port=0 
    to_port=0
    protocol="-1" 
    cidr_blocks=["0.0.0.0/0"] 
    }

  tags = { Project = "mlops-sklearn-portfolio" }
}
