terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
        backend "s3" {
            bucket = "fabio-landing-zone-state"
            key = "dev/terraform.tfstate"
            region = "us-east-2"
            profile = "AdministratorAccess-072942364694"
        }
    }
    provider "aws" {
        region = "us-east-1"
        profile = "AdministratorAccess-072942364694"

    }
    resource "aws_vpc" "main" {
        cidr_block = "10.0.0.0/16"
    tags = {
        Name = "landing-zone-vpc"
    }
    }
    data "aws_ami" "amazon_linux"{
      most_recent = true
      owners = ["amazon"]
      filter {
        name = "name"
        values = ["al2023-ami-*-x86_64"]
      }
    }

    resource "aws_subnet" "public_1" {
        vpc_id = aws_vpc.main.id
        cidr_block = "10.0.1.0/24"
        availability_zone = "us-east-1a"
        tags = {
            Name = "landing-zone-public-1a"
        
        }
    }
    resource "aws_subnet" "public_2" {
        vpc_id = aws_vpc.main.id
        cidr_block = "10.0.2.0/24"
        availability_zone = "us-east-1b"
        tags = {
            Name = "landing-zone-public-1b"
        }
    }
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "landing-zone-private-1a"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "landing-zone-private-1b"
  }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "landing-zone-igw"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "landing-zone-public-rt"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "landing-zone-private-rt"
  }
  route { 
  cidr_block = "0.0.0.0/0"
nat_gateway_id = aws_nat_gateway.main.id
}
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
resource "aws_security_group" "web" {
  name = "web-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

}
ingress {
  from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
egress {
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
}
resource "aws_eip" "nat"{
  domain = "vpc"
  tags = {
    Name = "landing-zone-nat-eip"
  }
}
resource "aws_nat_gateway" "main"{
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public_1.id
  tags = { Name = "landing-zone-nat" }
}

