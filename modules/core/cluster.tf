
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

resource "aws_route_table_association" "route_table_association_b" {
    subnet_id      = aws_subnet.pub_subnet_b.id
    route_table_id = aws_route_table.public.id
}

# S3 Endpoint

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.us-east-2.s3"
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  route_table_id = aws_route_table.public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

# Security Groups

resource "aws_security_group" "ecs_sg" {
    vpc_id      = aws_vpc.vpc.id

    ingress {
        from_port       = 8080
        to_port         = 8080
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
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

resource "aws_security_group" "lambda_sg" {
    vpc_id      = aws_vpc.vpc.id

    # Only allow ingress from our service
    ingress {
        protocol        = "tcp"
        from_port       = 9000
        to_port         = 9000
        cidr_blocks     = ["0.0.0.0/0"]
        #security_groups = [aws_security_group.ecs_sg.id]
    }

    egress {
      cidr_blocks       = [ "0.0.0.0/0" ]
      from_port         = 443
      to_port           = 443
      protocol          = "tcp"
    }

    egress {
      cidr_blocks       = [ "0.0.0.0/0" ]
      from_port         = 0
      to_port           = 65535
      protocol          = "tcp"
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
    engine_version            = "12.7"
    instance_class            = "db.t2.micro"
    name                      = "feather_db"
    username                  = "ftr_db_user"
    password                  = var.db_password
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

  ingress {
    self        = false
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP 443 from anywhere"
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
  load_balancer_type = "application"
  subnets = [ aws_subnet.pub_subnet_a.id, aws_subnet.pub_subnet_b.id ]
  security_groups = [ aws_security_group.alb_sg.id ]
  idle_timeout = 600
}

resource "aws_alb_target_group" "service_core" {
  name = "service-core-target-group"
  port = 8080
  protocol = "HTTP"
  #target_type = "ip"
  vpc_id = aws_vpc.vpc.id

  depends_on = [aws_alb.service_core]

  health_check {
    path = "/v1/health"
    protocol = "HTTP"
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

resource "aws_alb_listener" "alb_listener_ssl" {
  load_balancer_arn = aws_alb.service_core.id
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-2:483384053975:certificate/0f3fc49d-267a-4d9a-844f-3eae656c6a9d"

  default_action {
    target_group_arn = aws_alb_target_group.service_core.id
    type             = "forward"
  }
}

# Runner Lambda

resource "aws_iam_user" "lambda_runner" {
  name = "lambda_runner"
  path = "/feather/"
}

resource "aws_iam_access_key" "lambda_runner" {
  user = aws_iam_user.lambda_runner.name
}

resource "aws_iam_user_policy" "lambda_runner" {
  name = "lambda_runner"
  user = aws_iam_user.lambda_runner.name

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:Get*",
                "s3:List*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_ecr_repository" "generic_runner" {
    name  = "generic_runner"
    image_tag_mutability = "MUTABLE"
}

resource "aws_cloudwatch_log_group" "generic_runner" {
  name              = "/lambda/${aws_ecr_repository.generic_runner.name}"
  retention_in_days = 7
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_policy" "lambda_networking" {
  name        = "lambda_networking"
  path        = "/"
  description = "IAM policy for networking from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeInstances",
        "ec2:AttachNetworkInterface"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_networking" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_networking.arn
}

resource "aws_lambda_function" "generic_runner_lambda" {
  function_name = "generic_runner"
  role          = aws_iam_role.iam_for_lambda.arn
  image_uri     = "${aws_ecr_repository.generic_runner.repository_url}:latest"
  memory_size   = 4096
  package_type  = "Image"
  timeout       = 300

  #vpc_config {
  #  subnet_ids = [aws_subnet.pub_subnet_a.id]
  #  security_group_ids = [ aws_security_group.lambda_sg.id ]
  #}

  environment {
    variables = {
      FTR_S3_ACCESS_KEY_ID = "${aws_iam_access_key.lambda_runner.id}"
      FTR_S3_SECRET_ACCESS_KEY = "${aws_iam_access_key.lambda_runner.secret}"
      FTR_S3_REGION = "${var.region}"
      FTR_S3_BUCKET_NAME = "${var.storage_main}"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.generic_runner,
  ]
}

# ECS

resource "aws_iam_user" "service_s3_user" {
  name = "service_s3_user"
  path = "/feather/"
}

resource "aws_iam_access_key" "service_s3_user" {
  user = aws_iam_user.service_s3_user.name
}

resource "aws_iam_user_policy" "service_s3_user" {
  name = "service_s3_user"
  user = aws_iam_user.service_s3_user.name

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:Get*",
                "s3:List*",
                "s3:Put*",
                "lambda:InvokeAsync",
                "lambda:InvokeFunction"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}
resource "aws_ecr_repository" "worker" {
    name  = "ftr-service-core"
}

resource "aws_ecs_cluster" "ecs_cluster" {
    name  = "feather"
}

resource "aws_cloudwatch_log_group" "service_logs" {
  name = "service-core"
  retention_in_days = 7
}

data "template_file" "task_definition_template" {
  template = "${file("${path.module}/task_definition.json.tpl")}"
  vars = {
    repository_rul = "${aws_ecr_repository.worker.repository_url}"
    db_url = "host=${aws_db_instance.postgres.address} port=${aws_db_instance.postgres.port} dbname=${aws_db_instance.postgres.name} user=${aws_db_instance.postgres.username} password=${aws_db_instance.postgres.password}"
    debug_user = "true"
    aws_access_key_id = "${aws_iam_access_key.service_s3_user.id}"
    aws_secret_access_key = "${aws_iam_access_key.service_s3_user.secret}"
    stripe_webhook_secret_key = "${var.stripe_webhook_secret_key}"
    stripe_secret_key = "${var.stripe_secret_key}"
    model_jwt_secret_key = "${var.model_jwt_secret_key}"
  }
}

resource "aws_ecs_task_definition" "task_definition" {
  family                = "ftr-service-core"
  network_mode          = "host"
  container_definitions = data.template_file.task_definition_template.rendered
}

# Security group for the ALB
resource "aws_security_group" "ecs_worker_sg" {
  name        = "ecs-worker-alb-sg"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    self        = false
    from_port   = 8080
    to_port     = 8080
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
}