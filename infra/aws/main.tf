# StarSI AWS site: one always-on arm64 CPU instance (k3s server, gateway,
# llama.cpp tier, capacity-controller) + one stoppable GPU instance (k3s agent,
# vLLM tier). Security group exposes port 22 ONLY — every service rides SSH.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── network: ssh in, everything out, intra-SG free (k3s server<->agent) ──────

resource "aws_security_group" "starsi" {
  name_prefix = "starsi-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH only — the sole public surface"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "intra-cluster (k3s apiserver, flannel) over the private VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── artifacts ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM: nodes read artifacts + shared k3s join token via SSM;
#        the CPU node may also start/stop the GPU node (capacity-controller) ──

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "starsi-node-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "node" {
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/starsi/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:DescribeInstances"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/starsi-role" = "gpu" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "starsi-node-"
  role        = aws_iam_role.node.name
}

# ── always-on CPU node ───────────────────────────────────────────────────────

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
}

resource "aws_instance" "cpu" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.cpu_instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.starsi.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  user_data              = templatefile("${path.module}/user-data-cpu.sh", { region = var.region })

  root_block_device {
    volume_size = 60
  }

  tags = { Name = "starsi-cpu", starsi-role = "cpu" }
}

resource "aws_eip" "cpu" {
  instance = aws_instance.cpu.id
  tags     = { Name = "starsi-cpu" }
}

# ── stoppable GPU node (capacity-controller starts/stops it) ─────────────────

data "aws_ami" "al2023_gpu" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-gpu-hvm-*-x86_64"]
  }
}

resource "aws_instance" "gpu" {
  ami                    = data.aws_ami.al2023_gpu.id
  instance_type          = var.gpu_instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.starsi.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  user_data = templatefile("${path.module}/user-data-gpu.sh", {
    region     = var.region
    server_ip  = aws_instance.cpu.private_ip
  })

  root_block_device {
    volume_size = 120
  }

  tags = { Name = "starsi-gpu", starsi-role = "gpu" }

  lifecycle {
    ignore_changes = [instance_state]
  }
}
