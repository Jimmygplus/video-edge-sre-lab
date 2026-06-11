# Video Edge Reliability Stack — cloud host
# One small EC2 instance running k3s (same kernel as the local k3d lab).
# Cost guard: t4g.small (2 vCPU / 2GB, ARM) ≈ US$12/mo in ap-southeast-2.
#
# Usage:
#   terraform init
#   terraform apply -var "my_ip=$(curl -s ifconfig.me)/32"
#   ssh -i ~/.ssh/sre-lab.pem ubuntu@$(terraform output -raw public_ip)

terraform {
  required_version = ">= 1.5"
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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "instance_type" {
  description = "EC2 instance type (ARM Graviton for price/perf)"
  type        = string
  default     = "t4g.small"
}

variable "my_ip" {
  description = "Your public IP in CIDR form (x.x.x.x/32) — SSH and kubectl are restricted to this"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used for the instance"
  type        = string
  default     = "~/.ssh/sre-lab.pub"
}

# Ubuntu 24.04 LTS ARM64
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "sre-lab"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "lab" {
  name        = "sre-lab"
  description = "video-edge reliability stack"

  # SSH + Kubernetes API: admin IP only
  ingress {
    description = "ssh (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    description = "k3s API (admin only)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Public demo surfaces
  ingress {
    description = "HTTP (demo API / read-only Grafana via ingress)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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

resource "aws_instance" "lab" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.lab.key_name
  vpc_security_group_ids = [aws_security_group.lab.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # k3s single-node install on first boot
  user_data = <<-EOF
    #!/bin/bash
    set -e
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
  EOF

  tags = {
    Name    = "video-edge-sre-lab"
    Project = "sre-lab"
  }
}

output "public_ip" {
  value = aws_instance.lab.public_ip
}

output "ssh" {
  value = "ssh -i ~/.ssh/sre-lab ubuntu@${aws_instance.lab.public_ip}"
}

output "monthly_cost_note" {
  value = "t4g.small on-demand ap-southeast-2 ≈ US$12/mo + EBS 20GB ≈ US$2/mo + egress"
}
