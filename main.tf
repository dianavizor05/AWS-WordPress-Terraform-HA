terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  project = lower(var.project_name)
  env     = upper(var.environment)

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  instance_types = {
    TEST       = "t3.micro"
    DEVELOPER  = "t3.small"
    PRODUCTION = "t3.medium"
  }

  asg_min = {
    TEST       = 1
    DEVELOPER  = 2
    PRODUCTION = 2
  }

  asg_max = {
    TEST       = 3
    DEVELOPER  = 3
    PRODUCTION = 6
  }

  common_tags = {
    Project     = var.project_name
    Environment = local.env
    ManagedBy   = "Terraform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# =========================
# VPC
# =========================

resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-igw"
  })
}

# Public subnets: ALB, NAT Gateway, Bastion
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-public-${count.index + 1}"
    Tier = "public"
  })
}

# Private app subnets: WordPress EC2 Auto Scaling Group
resource "aws_subnet" "private_app" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-private-app-${count.index + 1}"
    Tier = "private-app"
  })
}

# Private DB subnets: RDS
resource "aws_subnet" "private_db" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 20)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-private-db-${count.index + 1}"
    Tier = "private-db"
  })
}

# =========================
# Routing
# =========================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = local.env == "PRODUCTION" ? 2 : 1

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count = local.env == "PRODUCTION" ? 2 : 1

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_app" {
  count = 2

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-private-app-rt-${count.index + 1}"
  })
}

resource "aws_route" "private_app_to_internet" {
  count = 2

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # TEST/DEVELOPER używa jednego NAT Gateway, PRODUCTION dwóch NAT Gateway.
  nat_gateway_id = aws_nat_gateway.nat[local.env == "PRODUCTION" ? count.index : 0].id
}

resource "aws_route_table_association" "private_app" {
  count = 2

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

resource "aws_route_table" "private_db" {
  count = 2

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-private-db-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private_db" {
  count = 2

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db[count.index].id
}

# =========================
# Security Groups
# Zasada:
# - EGRESS: dozwolone wszystko
# - INGRESS: ograniczone maksymalnie
# =========================

resource "aws_security_group" "alb" {
  name        = "${local.project}-${local.env}-alb-sg"
  description = "Security group for public Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.certificate_arn != "" ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_out" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "bastion" {
  name        = "${local.project}-${local.env}-bastion-sg"
  description = "Security group for bastion hosts"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-bastion-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from administrator IP only"
  cidr_ipv4         = var.admin_ip_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion_all_out" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "wordpress" {
  name        = "${local.project}-${local.env}-wordpress-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-wordpress-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "wordpress_http_from_alb" {
  security_group_id            = aws_security_group.wordpress.id
  description                  = "HTTP from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "wordpress_ssh_from_bastion" {
  security_group_id            = aws_security_group.wordpress.id
  description                  = "SSH from bastion hosts only"
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "wordpress_all_out" {
  security_group_id = aws_security_group.wordpress.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "rds" {
  name        = "${local.project}-${local.env}-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_wordpress" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from WordPress instances only"
  referenced_security_group_id = aws_security_group.wordpress.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_out" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "efs" {
  name        = "${local.project}-${local.env}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-efs-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs_from_wordpress" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS from WordPress instances only"
  referenced_security_group_id = aws_security_group.wordpress.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "efs_all_out" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# =========================
# Bastion Hosts
# =========================

resource "aws_instance" "bastion" {
  count = 2

  ami                         = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-bastion-${count.index + 1}"
  })
}

# =========================
# EFS
# =========================

resource "aws_efs_file_system" "wordpress" {
  encrypted = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-efs"
  })
}

resource "aws_efs_mount_target" "wordpress" {
  count = 2

  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private_app[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# =========================
# RDS MySQL
# =========================

resource "aws_db_subnet_group" "wordpress" {
  name       = "${local.project}-${lower(local.env)}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-db-subnet-group"
  })
}

resource "aws_db_instance" "wordpress" {
  identifier = "${local.project}-${lower(local.env)}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = local.env == "PRODUCTION" ? true : false
  publicly_accessible = false

  backup_retention_period = local.env == "PRODUCTION" ? 7 : 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-rds"
  })
}

# =========================
# Application Load Balancer
# =========================

resource "aws_lb" "wordpress" {
  name               = "${local.project}-${lower(local.env)}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]
  subnets         = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-alb"
  })
}

resource "aws_lb_target_group" "wordpress" {
  name     = "${local.project}-${lower(local.env)}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.env}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.wordpress.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# =========================
# Launch Template WordPress
# =========================

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${local.project}-${local.env}-wordpress-"
  image_id      = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = local.instance_types[local.env]
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.wordpress.id]

  user_data = base64encode(<<EOF
#!/bin/bash

exec > /var/log/user-data.log 2>&1

dnf update -y
dnf install -y docker

systemctl enable docker
systemctl start docker

docker rm -f wordpress || true

docker run -d \
  --name wordpress \
  --restart always \
  -p 80:80 \
  -e WORDPRESS_DB_HOST="${aws_db_instance.wordpress.address}:3306" \
  -e WORDPRESS_DB_NAME="${var.db_name}" \
  -e WORDPRESS_DB_USER="${var.db_username}" \
  -e WORDPRESS_DB_PASSWORD="${var.db_password}" \
  wordpress:latest
EOF
)

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${local.project}-${local.env}-wordpress"
    })
  }

  depends_on = [
    aws_efs_mount_target.wordpress,
    aws_db_instance.wordpress
  ]
}

# =========================
# Auto Scaling Group
# =========================

resource "aws_autoscaling_group" "wordpress" {
  name = "${local.project}-${local.env}-asg"

  min_size         = local.asg_min[local.env]
  desired_capacity = local.asg_min[local.env]
  max_size         = local.asg_max[local.env]

  vpc_zone_identifier = aws_subnet.private_app[*].id
  target_group_arns   = [aws_lb_target_group.wordpress.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.project}-${local.env}-wordpress-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = local.env
    propagate_at_launch = true
  }

  depends_on = [
    aws_lb_listener.http
  ]
}

resource "aws_autoscaling_policy" "wordpress_cpu_policy" {
  name                   = "${local.project}-${local.env}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}