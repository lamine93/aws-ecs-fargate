#####################
# Réseau: VPC + Subnets
#####################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_a_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_b_cidr
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

#############################
# Security Groups (v2 res/rules)
#############################
resource "aws_security_group" "lb_sg" {
  name        = "alb_security_group"
  vpc_id      = aws_vpc.main.id
}

# Inbound HTTP from Internet → ALB
resource "aws_vpc_security_group_ingress_rule" "allow_lb_http" {
  security_group_id = aws_security_group.lb_sg.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress ALB to ECS tasks (strict : only toward SG ECS, port app)
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_security_group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "allow_lb_to_ecs" {
  security_group_id            = aws_security_group.lb_sg.id
  referenced_security_group_id = aws_security_group.ecs_sg.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# Inbound ECS from ALB (port app)
resource "aws_vpc_security_group_ingress_rule" "allow_task_from_lb" {
  security_group_id            = aws_security_group.ecs_sg.id
  referenced_security_group_id = aws_security_group.lb_sg.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# Egress ECS to Internet (HTTPS) for ECR/Logs/etc.
resource "aws_vpc_security_group_egress_rule" "allow_https_outbound" {
  security_group_id = aws_security_group.ecs_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

###############################
# ECR + Logs + IAM Execution Role
###############################
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/ecs-fargate"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

###########################
# ECS Cluster + Task + Svc
###########################
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "${var.project}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  # (Optionnel) forcer l’archi :
  # runtime_platform {
  #   operating_system_family = "LINUX"
  #   cpu_architecture        = "X86_64" # ou "ARM64"
  # }

  container_definitions = jsonencode([
    {
      name  = "app-container"
      image = "${aws_ecr_repository.app_repo.repository_url}:latest"
      portMappings = [
        {  
            containerPort = var.app_port, 
            hostPort      = var.app_port,
            protocol      = "tcp" 
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.ecs_log_group.name}"
          awslogs-region        = "${var.region}"
          awslogs-stream-prefix = "ecs"
        }
      }
      # (Optionnel) healthCheck interne si image possède curl :
      # healthCheck = {
      #   command     = ["CMD-SHELL", "curl -f http://localhost:${var.app_port}/ || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 10
      # }
    }
  ])
}

#######################
# ALB + TG + Listener
#######################
resource "aws_lb" "app_alb" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  depends_on = [aws_lb.app_alb]
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

#####################
# ECS Service (Fargate)
#####################
resource "aws_ecs_service" "app_service" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app-container"
    container_port   = var.app_port
  }

  depends_on = [
    aws_lb_listener.app_listener
  ]
}