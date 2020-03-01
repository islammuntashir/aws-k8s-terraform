# take data for Zones
data "aws_availability_zones" "available" {}

resource "aws_vpc" "hishab-cnative" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "kubernetes.io/cluster"
  }
}

#Create AWS Internet gateway
resource "aws_internet_gateway" "hishab_internet_gateway" {
  vpc_id = aws_vpc.hishab-cnative.id

  tags = {
    Name = "Hishab k8s IGW"
  }
}

# Create Single public subnet for hishab
resource "aws_subnet" "hishab_public_subnet" {
  vpc_id     = aws_vpc.hishab-cnative.id
  cidr_block = "10.70.1.0/24"
  availability_zone = element(var.azs, 0)

  tags = {
    Name = "Hishab cnative public Subnet"
    Tier = "Public"
  }
}

resource "aws_subnet" "hishab_k8s_subnet" {
  count             = length(var.k8s_private_subnets_cidr)
  vpc_id            = aws_vpc.hishab-cnative.id
  cidr_block        = element(var.k8s_private_subnets_cidr, count.index)
  availability_zone = element(var.azs, count.index)
  tags = {
    Name = "k8s-Private-Subnet-${count.index + 1}"
  }
}

# Create ROUTE TABLE and add ipv4 route to it
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.hishab-cnative.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hishab_internet_gateway.id
  }

  tags = {
    Name = "k8s public RT"
  }
}

# Create default ROUTE TABLE from VPC route
resource "aws_default_route_table" "default_private_rt" {
  default_route_table_id = aws_vpc.hishab-cnative.default_route_table_id

  tags = {
    Name = "Default private RT"
  }
}


# Make association with public subnet with ROUTE table
resource "aws_route_table_association" "rt_public_assoc" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.hishab_public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_RT.id
}


# Generate EIP for Nat Gateway
resource "aws_eip" "hishab_eip_nat" {
  vpc        = true
  depends_on = [aws_internet_gateway.hishab_internet_gateway]
  tags = {
    Name = "EIP for NAT GW"
  }
}

# Generate NAT gateway with EIP
resource "aws_nat_gateway" "nat-gw" {
  allocation_id = aws_eip.hishab_eip_nat.id
  subnet_id     = element(aws_subnet.hishab_public_subnet.*.id, 1)

  tags = {
    Name = "Hishab NAT GW"
  }
}


# Route Table for k8s subnets
resource "aws_route_table" "k8s_private_RT" {
  vpc_id = aws_vpc.hishab-cnative.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw.id
  }

  tags = {
    Name = "k8s Private RT"
  }
}

#route table association with k8s private RT
resource "aws_route_table_association" "rt_k8s_assoc" {
  count          = length(var.k8s_private_subnets_cidr)
  subnet_id      = element(aws_subnet.hishab_k8s_subnet.*.id, count.index)
  route_table_id = aws_route_table.k8s_private_RT.id
}

#IAM Policy
data "template_file" "master_policy_json" {
  template = file("${path.module}/template/master-policy.json.tpl")

  vars = {}
}

resource "aws_iam_policy" "master_policy" {
  name        = "k8s-master"
  path        = "/"
  description = "Policy for role k8s-master"
  policy      = data.template_file.master_policy_json.rendered
}


resource "aws_iam_role" "master_role" {
  name = "k8s-master"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy_attachment" "master-attach" {
  name = "master-attachment"
  roles = [aws_iam_role.master_role.name]
  policy_arn = aws_iam_policy.master_policy.arn
}

resource "aws_iam_instance_profile" "k8s-master_profile" {
  name = "k8s-master"
  role = aws_iam_role.master_role.name
}

#node
data "template_file" "worker_policy_json" {
  template = file("${path.module}/template/node-policy.json.tpl")

  vars = {}
}

resource "aws_iam_policy" "worker_policy" {
  name = "worker-node"
  path = "/"
  description = "Policy for role k8s-worker"
  policy = data.template_file.worker_policy_json.rendered
}

resource "aws_iam_role" "worker_role" {
  name = "k8s-worker"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_policy_attachment" "worker-attach" {
  name       = "worker-attachment"
  roles      = [aws_iam_role.worker_role.name]
  policy_arn = aws_iam_policy.worker_policy.arn
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "k8s-worker"
  role = aws_iam_role.worker_role.name
}


resource "aws_key_pair" "ssh" {
  count      = var.aws_key_pair_name == null ? 1 : 0
  key_name   = "${var.owner}-${var.project}"
  public_key = file(var.ssh_public_key_path)
}

## Amazon Linux AMI for Bastion Host
data "aws_ami" "amazonlinux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

}

# Data sources
## Ubuntu AMI for all K8s instances
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
}

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%BASTION%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
#Bastion Instance security Group
resource "aws_security_group" "bastion" {
  name_prefix = "bastion-"
  description = "Bastion"
  vpc_id      = aws_vpc.hishab-cnative.id

  tags = {
    Name    = "${var.project}-bastion"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

#AWS security group rule
resource "aws_security_group_rule" "ssh" {
  for_each = {
    "k8s-master" = aws_security_group.k8s-master.id,
    "k8s-worker" = aws_security_group.k8s-worker.id
    # "DB" = aws_security_group.db.id,
    # "ASR" = aws_security_group.asr.id
  }
  security_group_id        = each.value
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  description              = "SSH: Bastion - ${each.key}"
}

# Get local office's external IPv4 address
locals {
  workstation-external-cidr = "103.216.59.166/32"
}

#allow bastion lb to ssh on bastion instance
resource "aws_security_group_rule" "allow_ingress_on_bastion_ssh" {
  security_group_id        = aws_security_group.bastion.id
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  cidr_blocks              = [local.workstation-external-cidr]
  description              = "SSH: Bastion-LB - Bastion"
}

#allow all IP to connect 80 of bastion-lb
resource "aws_security_group_rule" "bastion-allow-http" {
  security_group_id = aws_security_group.bastion.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP: Workstation - BastionHost"
}

# bastion Instance
resource "aws_instance" "bastion" {
  # for_each                    = "data.aws_subnet_ids.hishab_subnet.ids"
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  monitoring                  = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = aws_subnet.hishab_public_subnet.id
  associate_public_ip_address = true
 

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install software-properties-common
              sudo apt-add-repository --yes --update ppa:ansible/ansible
              sudo apt install ansible --yes
              EOF 


   tags = {
    Name    = "${var.project}-Bastion-instance"
    Project = var.project
    Owner   = var.owner
  }
}

# Generate EIP for Nat Gateway
resource "aws_eip" "eip-bastion-host" {
  vpc        = true
  depends_on = [aws_internet_gateway.hishab_internet_gateway]
  tags = {
    Name = "eip-bastion-host"
  }
}

resource "aws_eip_association" "eip_assoc_bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.eip-bastion-host.id
}
## Egress
resource "aws_security_group_rule" "egress_all" {
  for_each = {
    "Bastion"         = aws_security_group.bastion.id,
    "Masters"         = aws_security_group.k8s-master.id,
    "Workers"         = aws_security_group.k8s-worker.id
  }
  security_group_id = each.value
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Egress ALL: ${each.key}"
}

#%%%%%%%%%%%%%%%%%%%%%%%%%K8s-master-worker-Node%%%%%%%%%%%%%%%%%%%%%%%%%

#k8s-master instance SG
resource "aws_security_group" "k8s-master" {
  name_prefix = "k8s-master-"
  description = "K8s-master"
  vpc_id      = aws_vpc.hishab-cnative.id

  tags = {
    Name    = "${var.project}-k8s"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

#k8s-work instance SG
resource "aws_security_group" "k8s-worker" {
  name_prefix = "k8s-worker-"
  description = "K8s-worker"
  vpc_id      = aws_vpc.hishab-cnative.id

  tags = {
    Name    = "${var.project}-k8s"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_ingress_worker_on_master_all" {
  security_group_id        = aws_security_group.k8s-master.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "all"
  source_security_group_id = aws_security_group.k8s-worker.id
  description              = "ALL: Workers - Masters"
}

### Worker
resource "aws_security_group_rule" "allow_ingress_on_worker_all" {
  security_group_id        = aws_security_group.k8s-worker.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "all"
  source_security_group_id = aws_security_group.k8s-master.id
  description              = "ALL:k8s - Workers"
}

resource "aws_security_group_rule" "k8s-master-remoteIP-ssh" {
  security_group_id = aws_security_group.k8s-master.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.workstation-external-cidr]
  description       = "SSH: Workstation - MasterPublicLB"
}

resource "aws_security_group_rule" "k8s-master-http-allowall" {
  security_group_id = aws_security_group.k8s-master.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "SSH: Workstation - MasterPublicLB"
}


resource "aws_launch_configuration" "k8s-master" {
  name_prefix                 = "master-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.master_instance_type
  security_groups             = [aws_security_group.k8s-master.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true
  iam_instance_profile        = aws_iam_instance_profile.k8s-master_profile.id

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install software-properties-common
              sudo apt-get install python3-pip -y
              sudo pip3 install awscli
              EOF
  
  root_block_device {
    volume_size           = var.EC2_ROOT_VOLUME_SIZE
    volume_type           = var.EC2_ROOT_VOLUME_TYPE
    delete_on_termination = false
  }
  

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "k8s-master" {
  max_size             = var.master_max_size
  min_size             = var.master_min_size
  desired_capacity     = var.master_size
  force_delete         = true
  launch_configuration = aws_launch_configuration.k8s-master.name
  vpc_zone_identifier  = aws_subnet.hishab_k8s_subnet.*.id
  #load_balancers       = [aws_elb.k8s.id]

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-k8s-worker"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}


resource "aws_launch_configuration" "k8s-worker" {
  name_prefix                 = "worker-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  security_groups             = [aws_security_group.k8s-worker.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install software-properties-common
              sudo apt-get install python3-pip -y
              sudo pip3 install awscli
              EOF
 root_block_device {
    volume_size           = var.EC2_ROOT_VOLUME_SIZE
    volume_type           = var.EC2_ROOT_VOLUME_TYPE
    delete_on_termination = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

## Kubernetes Master
resource "aws_autoscaling_group" "k8s-worker" {
  max_size             = var.worker_max_size
  min_size             = var.worker_min_size
  desired_capacity     = var.worker_size
  force_delete         = true
  launch_configuration = aws_launch_configuration.k8s-worker.name
  vpc_zone_identifier  = aws_subnet.hishab_k8s_subnet.*.id
  #load_balancers       = [aws_elb.k8s.id]

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-k8s-worker"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}




