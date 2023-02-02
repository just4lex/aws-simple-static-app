terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

variable "PUBLIC_KEY_MATERIAL" {
    type = string
    description = "AWS SSH publick key material"
}

provider "aws" {
    region = "us-east-1"
}

data "http" "myip" {
    url = "http://ipv4.icanhazip.com"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "http_subnet" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.10.0/24"
    availability_zone = "us-east-1a"
}

resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "vpc_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.vpc_rt.id
}

resource "aws_security_group" "http_sg" {
    name = "http_sg"
    description = "Allow SSH from my address and HTTP from any address"
    vpc_id = aws_vpc.main.id

    ingress {
        description = "Allow SSH from my address"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]

    }
    ingress {
        description = "Allow HTTP from any address"
        from_port = 0
        to_port = 80
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
        protocol = "tcp"
    }

    egress {
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }
}

resource "aws_key_pair" "http_app" {
    key_name = "http-app-key"
    public_key = var.PUBLIC_KEY_MATERIAL
}

resource "aws_instance" "ec2_http_app" {
    ami = "ami-0859831a09ef09d7b"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "http-app-key"
    subnet_id = aws_subnet.http_subnet.id

    tags = {
        Application = "http_static"
    }
}

resource "aws_network_interface_sg_attachment" "sg_attachment" {
  security_group_id    = aws_security_group.http_sg.id
  network_interface_id = aws_instance.ec2_http_app.primary_network_interface_id
}

resource "aws_eip" "app" {
    instance = aws_instance.ec2_http_app.id
    vpc = true
}

resource "aws_ebs_volume" "http_app_ebs" {
  availability_zone = "us-east-1a"
  size = 5

}

resource "aws_volume_attachment" "ebs_app_att" {
    device_name = "/dev/xvdb"
    volume_id = aws_ebs_volume.http_app_ebs.id
    instance_id = aws_instance.ec2_http_app.id
}

resource "aws_route53_zone" "primary" {
    name = "apankratovhttpapp.com"
}

resource "aws_route53_record" "www" {
    zone_id = aws_route53_zone.primary.zone_id
    name = "www.apankratovhttpapp.com"
    type = "A"
    ttl = 300
    records = [aws_eip.app.public_ip]
}

resource "aws_s3_bucket" "http_s3" {
    bucket = "apankratov-http-app-test-bucket"
}

resource "aws_s3_bucket_versioning" "http_s3_ver" {
    bucket = aws_s3_bucket.http_s3.id
    versioning_configuration {
      status = "Enabled"
    }
}

resource "aws_s3_bucket_acl" "http_s3_acl" {
    bucket = aws_s3_bucket.http_s3.id
    acl = "private"
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.app.public_ip
}