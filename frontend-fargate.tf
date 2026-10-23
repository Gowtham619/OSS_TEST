##############################################
# Frontend on ECS Fargate — an ALB in the public subnets, tasks in the
# private subnets (reusing modules/network's existing NAT for image pulls
# and any outbound calls). Toggle with deploy_frontend_fargate.
##############################################

variable "deploy_frontend_fargate" {
  description = "Deploy the React frontend as an ECS Fargate service behind an ALB. Flip to false and re-apply to tear it down."
  type        = bool
  default     = false
}

variable "frontend_container_image" {
  description = "Full ECR image URI to run, e.g. '<account>.dkr.ecr.<region>.amazonaws.com/complaints-rag-frontend:latest'. Defaults to a placeholder public nginx image so the service deploys successfully before you've built and pushed your real image — replace this once you have."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable"
}

variable "frontend_container_port" {
  type    = number
  default = 80
}

variable "frontend_desired_count" {
  description = "Number of running tasks. 2+ for any real availability — a single task means a deploy or AZ blip takes the frontend down."
  type        = number
  default     = 2
}

variable "frontend_cpu" {
  description = "Fargate task vCPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Fargate task memory in MB."
  type        = number
  default     = 512
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on the ALB. Leave null to run HTTP-only for initial testing — replace with a real cert before anything beyond a quick test, since auth tokens will otherwise cross the wire unencrypted."
  type        = string
  default     = null
}

locals {
  frontend_enabled = var.deploy_frontend_fargate
}

##############################################
# ECR repository for your built image
##############################################
resource "aws_ecr_repository" "frontend" {
  count                = local.frontend_enabled ? 1 : 0
  name                 = "${var.name_prefix}-${var.environment}-frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

##############################################
# ECS cluster, log group
##############################################
resource "aws_ecs_cluster" "this" {
  count = local.frontend_enabled ? 1 : 0
  name  = "${var.name_prefix}-${var.environment}-cluster"
  tags  = var.tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  count             = local.frontend_enabled ? 1 : 0
  name              = "/ecs/${var.name_prefix}-${var.environment}-frontend"
  retention_in_days = 30
  tags              = var.tags
}

##############################################
# IAM — task execution role (pulls image, writes logs) and task role
# (permissions the running container itself needs; empty for now — a
# pure static-serving container needs none, add policies here if the
# app later needs to call AWS services directly at runtime).
##############################################
data "aws_iam_policy_document" "ecs_tasks_assume" {
  count = local.frontend_enabled ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  count              = local.frontend_enabled ? 1 : 0
  name               = "${var.name_prefix}-${var.environment}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count      = local.frontend_enabled ? 1 : 0
  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  count              = local.frontend_enabled ? 1 : 0
  name               = "${var.name_prefix}-${var.environment}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume[0].json
  tags               = var.tags
}

##############################################
# Task definition
##############################################
resource "aws_ecs_task_definition" "frontend" {
  count                    = local.frontend_enabled ? 1 : 0
  family                   = "${var.name_prefix}-${var.environment}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn

  # Graviton (ARM64) — matches images built natively on Apple Silicon
  # without cross-platform emulation, and typically ~20% cheaper than
  # the X86_64 default. If you ever push an amd64-only image, either
  # remove this block (Fargate defaults to X86_64) or rebuild with
  # `docker build --platform linux/arm64`.
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_container_image
      essential = true
      portMappings = [
        { containerPort = var.frontend_container_port, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend[0].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = var.tags
}

##############################################
# Security groups — ALB open to the internet on 80/443; the service only
# accepts traffic from the ALB's security group, never directly.
##############################################
resource "aws_security_group" "alb" {
  count       = local.frontend_enabled ? 1 : 0
  name        = "${var.name_prefix}-${var.environment}-alb-sg"
  description = "Public ALB for the frontend"
  vpc_id      = module.network.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.acm_certificate_arn != null ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-alb-sg" })
}

resource "aws_security_group" "frontend_service" {
  count       = local.frontend_enabled ? 1 : 0
  name        = "${var.name_prefix}-${var.environment}-frontend-service-sg"
  description = "Frontend Fargate tasks - only reachable from the ALB"
  vpc_id      = module.network.vpc_id

  ingress {
    description     = "From ALB only"
    from_port       = var.frontend_container_port
    to_port         = var.frontend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-frontend-service-sg" })
}

##############################################
# ALB, target group, listeners
##############################################
resource "aws_lb" "frontend" {
  count              = local.frontend_enabled ? 1 : 0
  name               = "${var.name_prefix}-${var.environment}-frontend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = module.network.public_subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "frontend" {
  count       = local.frontend_enabled ? 1 : 0
  name        = "${var.name_prefix}-${var.environment}-frontend-tg"
  port        = var.frontend_container_port
  protocol    = "HTTP"
  vpc_id      = module.network.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  count             = local.frontend_enabled ? 1 : 0
  load_balancer_arn = aws_lb.frontend[0].arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.acm_certificate_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.acm_certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.frontend[0].arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.frontend_enabled && var.acm_certificate_arn != null ? 1 : 0
  load_balancer_arn = aws_lb.frontend[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend[0].arn
  }
}

##############################################
# ECS service
##############################################
resource "aws_ecs_service" "frontend" {
  count           = local.frontend_enabled ? 1 : 0
  name            = "${var.name_prefix}-${var.environment}-frontend"
  cluster         = aws_ecs_cluster.this[0].id
  task_definition = aws_ecs_task_definition.frontend[0].arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.network.private_subnet_ids
    security_groups  = [aws_security_group.frontend_service[0].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend[0].arn
    container_name   = "frontend"
    container_port   = var.frontend_container_port
  }

  depends_on = [aws_lb_listener.http]
}

##############################################
# Basic CPU-based autoscaling — a sensible enterprise-readiness default,
# not a requirement to get this running.
##############################################
resource "aws_appautoscaling_target" "frontend" {
  count              = local.frontend_enabled ? 1 : 0
  max_capacity       = var.frontend_desired_count * 3
  min_capacity       = var.frontend_desired_count
  resource_id        = "service/${aws_ecs_cluster.this[0].name}/${aws_ecs_service.frontend[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  count              = local.frontend_enabled ? 1 : 0
  name               = "${var.name_prefix}-${var.environment}-frontend-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend[0].resource_id
  scalable_dimension = aws_appautoscaling_target.frontend[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}

##############################################
# Outputs
##############################################
output "frontend_ecr_repository_url" {
  description = "Push your built image here: docker push <this>:latest"
  value       = local.frontend_enabled ? aws_ecr_repository.frontend[0].repository_url : null
}

output "frontend_alb_dns_name" {
  description = "Public URL for the frontend (put a real domain + Route53 CNAME on top of this before sharing it around)."
  value       = local.frontend_enabled ? aws_lb.frontend[0].dns_name : null
}

output "frontend_ecs_cluster_name" {
  value = local.frontend_enabled ? aws_ecs_cluster.this[0].name : null
}

output "frontend_ecs_service_name" {
  value = local.frontend_enabled ? aws_ecs_service.frontend[0].name : null
}
