

# VPC

resource "aws_vpc" "vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags       = {
        Name = "Feather VPC"
    }
}

resource "aws_internet_gateway" "internet_gateway" {
    vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "pub_subnet_a" {
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = "10.0.0.0/24"
    availability_zone       = "${var.availability_zone_a}"

    depends_on = [
      aws_vpc.vpc
    ]
}

resource "aws_subnet" "pub_subnet_b" {
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = "10.0.2.0/24"
    availability_zone       = "${var.availability_zone_b}"

    depends_on = [
      aws_vpc.vpc
    ]
}

# Route Tables

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.internet_gateway.id
    }

    depends_on = [
      aws_vpc.vpc
    ]
}

resource "aws_route_table_association" "route_table_association" {
    subnet_id      = aws_subnet.pub_subnet_a.id
    route_table_id = aws_route_table.public.id
}

# ALB

# Security group for the ALB
resource "aws_security_group" "alb_sg" {
  name        = "service-core-alb"
  vpc_id      = aws_vpc.vpc.id

  # Allow HTTP 80 from anywhere - ideally we should lock this down futher - we only need to allow traffic from API Gateway
  ingress {
    self        = false
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP 80 from anywhere"
  }

  egress {
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    self        = false
    description = "Allow all egress traffic"
  }
}

resource "aws_alb" "service_core" {
  name = "service-alb"
  internal = false
  subnets = [ aws_subnet.pub_subnet_a.id, aws_subnet.pub_subnet_b.id ]
  security_groups = [ aws_security_group.alb_sg.id ]
}

resource "aws_alb_target_group" "service_core" {
  name = "service-core-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id

  depends_on = [aws_alb.service_core]

  health_check {
    path = "/v1/health"
    protocol = "http"
  }
}

resource "aws_alb_listener" "alb_listener" {
  load_balancer_arn = aws_alb.service_core.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.service_core.id
    type             = "forward"
  }
}

# Security Groups

resource "aws_security_group" "ecs_sg" {
    vpc_id      = aws_vpc.vpc.id

    ingress {
        self        = true
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        description = "."
    }

    ingress {
        self            = false
        from_port       = 8080
        to_port         = 8080
        protocol        = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
    }

    egress {
        self            = false
        from_port       = 0
        to_port         = 65535
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    depends_on = [
      aws_vpc.vpc
    ]
}

resource "aws_security_group" "rds_sg" {
    vpc_id      = aws_vpc.vpc.id

    ingress {
        protocol        = "tcp"
        from_port       = 7274
        to_port         = 7274
        cidr_blocks     = ["0.0.0.0/0"]
        security_groups = [aws_security_group.ecs_sg.id]
    }

    egress {
        from_port       = 0
        to_port         = 65535
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    depends_on = [
      aws_vpc.vpc
    ]    
}

# DATABASE

resource "aws_db_subnet_group" "db_subnet_group" {
    subnet_ids  = [aws_subnet.pub_subnet_a.id, aws_subnet.pub_subnet_b.id]
}

resource "aws_db_instance" "postgres" {
    identifier                = "feather"
    allocated_storage         = 15
    multi_az                  = false
    apply_immediately         = true
    engine                    = "postgres"
    engine_version            = "12.6"
    instance_class            = "db.t2.micro"
    name                      = "feather_db"
    username                  = "ftr_db_user"
    password                  = "atr74kd%3kd"
    port                      = "7274"
    db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.id
    vpc_security_group_ids    = [aws_security_group.rds_sg.id, aws_security_group.ecs_sg.id]
    skip_final_snapshot       = true
    publicly_accessible       = true
}

# Autoscaling

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecsInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}


resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecsInstanceRole"
  role = aws_iam_role.ecs_agent.name
}

# Amazon Linux 2 ECS Optimized AMI
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
resource "aws_launch_configuration" "ecs_launch_config" {
    image_id             = "ami-06e650acd294da294"
    iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
    security_groups      = [aws_security_group.ecs_sg.id]
    user_data            = "#!/bin/bash\necho ECS_CLUSTER=feather >> /etc/ecs/ecs.config"
    instance_type        = "t2.micro"
    associate_public_ip_address = true
    name_prefix = "ftr-ecs"
}

resource "aws_autoscaling_group" "failure_analysis_ecs_asg" {
    name                      = "asg"
    vpc_zone_identifier       = [aws_subnet.pub_subnet_a.id]
    launch_configuration      = aws_launch_configuration.ecs_launch_config.name
    force_delete              = true
    desired_capacity          = 1
    min_size                  = 1
    max_size                  = 1
    health_check_grace_period = 300
    health_check_type         = "EC2"
}

# ECS

resource "aws_cloudwatch_log_group" "service_logs" {
  name = "service-core"
  retention_in_days = 7
}

data "template_file" "task_definition_template" {
  template = "${file("${path.module}/task_definition.json.tpl")}"
  vars = {
    repository_rul = "${aws_ecr_repository.worker.repository_url}"
    db_url = "host=${aws_db_instance.postgres.address} port=${aws_db_instance.postgres.port} dbname=${aws_db_instance.postgres.name} user=${aws_db_instance.postgres.username} password=${aws_db_instance.postgres.password}"
  }
}

resource "aws_ecr_repository" "worker" {
    name  = "ftr-service-core"
}

resource "aws_ecs_cluster" "ecs_cluster" {
    name  = "feather"
}

resource "aws_ecs_task_definition" "task_definition" {
  family                = "ftr-service-core"
  container_definitions = data.template_file.task_definition_template.rendered
  network_mode    = "awsvpc"
}

resource "aws_ecs_service" "worker" {
  name            = "feather-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_alb_target_group.service_core.arn
    container_name   = "ftr-service-core"
    container_port   = 8080
  }

  network_configuration {
    subnets         = [aws_subnet.pub_subnet_a.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }
}
