# 1. The Production VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "wakwetu-prod-vpc" }
}

# 2. Public Subnets (For ALB - Multi-AZ)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "wakwetu-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "wakwetu-public-2" }
}

# 3. Private Subnets (For App Tier - Multi-AZ)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "wakwetu-private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "wakwetu-private-2" }
}

# 4. Gateways
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prod_vpc.id
  tags = { Name = "wakwetu-prod-igw" }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
  tags = { Name = "wakwetu-prod-nat" }
}

# 5. Routing Logic (Public)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. Routing Logic (Private)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "priv_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}

# 7. Security Group for ALB (Internet Facing)
resource "aws_security_group" "alb_sg" {
  name        = "wakwetu-alb-sg"
  description = "Allow HTTP inbound from anywhere"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 8. Security Group for ECS Tasks (Private)
resource "aws_security_group" "ecs_sg" {
  name        = "wakwetu-ecs-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 9. Application Load Balancer
resource "aws_lb" "prod_alb" {
  name               = "wakwetu-prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "wakwetu-prod-alb" }
}

# 10. ALB Target Group (The "Backstage" area for Containers)
resource "aws_lb_target_group" "ecs_tg" {
  name        = "wakwetu-ecs-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.prod_vpc.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

# 11. ALB Listener (Connecting the Front Door to the Backstage)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# 12. ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "wakwetu-prod-cluster"
}

# 13. IAM Role for ECS Task Execution (The "Permission Slip")
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "wakwetu-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 14. ECS Task Definition (The Blueprints)
resource "aws_ecs_task_definition" "app" {
  family                   = "wakwetu-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "wakwetu-app"
      image     = "nginx:latest" # Standard high-performance web server
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

# 15. ECS Service (The Orchestrator)
resource "aws_ecs_service" "main" {
  name            = "wakwetu-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 2 # High Availability: Running 2 copies across our private subnets

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "wakwetu-app"
    container_port   = 80
  }
}

# 16. Output the Load Balancer URL
output "alb_dns_name" {
  value = aws_lb.prod_alb.dns_name
}

# 17. DynamoDB Table (The Persistent Store)
resource "aws_dynamodb_table" "app_data" {
  name           = "wakwetu-app-table"
  billing_mode   = "PAY_PER_REQUEST" # Serverless billing: No idle cost
  hash_key       = "UserId"

  attribute {
    name = "UserId"
    type = "S" # String
  }

  tags = { Name = "wakwetu-prod-data" }
}

# 18. IAM Policy for DynamoDB Access
resource "aws_iam_policy" "ecs_dynamo_policy" {
  name        = "wakwetu-ecs-dynamo-policy"
  description = "Allows ECS tasks to read/write to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.app_data.arn
      }
    ]
  })
}

# 19. Attach Policy to the Task Execution Role
resource "aws_iam_role_policy_attachment" "ecs_dynamo_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_dynamo_policy.arn
}

# 20. CloudFront Distribution (The Global Edge)
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_lb.prod_alb.dns_name
    origin_id   = "ALB-Origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # In production, we'd use HTTPS
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = ""

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-Origin"

    forwarded_values {
      query_string = true
      headers      = ["Host"] # Ensures the ALB knows which host is being requested

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "wakwetu-global-cdn" }
}

# 21. Output the CDN Domain
output "cdn_domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

# 22. Cognito User Pool (The User Directory)
resource "aws_cognito_user_pool" "pool" {
  name = "wakwetu-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

# 23. Cognito User Pool Client (The App Interface)
resource "aws_cognito_user_pool_client" "client" {
  name         = "wakwetu-app-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

# 24. Outputs for the Dev Team
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
}
