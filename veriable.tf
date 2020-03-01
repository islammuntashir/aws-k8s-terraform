variable "aws_region" {
	description = "This one is the aws region"
    type = string
    default = "ap-southeast-1"
}

variable "vpc_cidr" {
    description = "This is the subnet for Whole VPC"
    type =  string
    default = "10.70.0.0/16"
}

variable "azs" {
	type = list(string)
	default = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "k8s_private_subnets_cidr" {
	type = list(string)
	default = ["10.70.5.0/24", "10.70.6.0/24"]
}

variable "public_subnets_cidr" {
	type = list(string)
	default = ["10.70.1.0/24", "10.70.2.0/24"]
}

variable "aws_key_pair_name" {
  description = "AWS Key Pair name to use for EC2 Instances (if already existent)"
  type        = string
  default     = null
}

variable "ssh_public_key_path" {
  description = "SSH public key path (to create a new AWS Key Pair from existing local SSH public RSA key)"
  type        = string
  #default     = "~/.ssh/id_rsa.pub"
  default     = "~/workspace/sec/pem/hishab.pub"
}

variable "environment" {
  default = "staging"
}

variable "project" {
  description = "Project name used for tags"
  type        = string
  default     = "k8s-hishab-aws"
}

variable "owner" {
  description = "Owner name used for tags"
  type        = string
  default     = "muntashir"
}

variable "stage" {
  description = "Environment name (e.g. `testing`, `dev`, `staging`, `prod`)"
  type        = string
  default     = "staging"
}

variable "master_instance_type" {
  description = "EC2 instance type for K8s master instances"
  type        = string
  default     = "t3a.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for K8s worker instances"
  type        = string
  default     = "t3a.small"
}

variable "master_max_size" {
  description = "Maximum number of EC2 instances for K8s Master AutoScalingGroup"
  type        = number
  default     = 2
}

variable "master_min_size" {
  description = "Minimum number of EC2 instances for K8s Master AutoScalingGroup"
  type        = number
  default     = 2
}

variable "master_size" {
  description = "Desired number of EC2 instances for K8s Master AutoScalingGroup"
  type        = number
  default     = 2
}

variable "worker_max_size" {
  description = "Maximum number of EC2 instances for K8s Worker AutoScalingGroup"
  type        = number
  default     = 8
}

variable "worker_min_size" {
  description = "Minimum number of EC2 instances for K8s Worker AutoScalingGroup"
  type        = number
  default     = 4
}

variable "worker_size" {
  description = "Desired number of EC2 instances for K8s Worker AutoScalingGroup"
  type        = number
  default     = 4
}

variable "EC2_ROOT_VOLUME_SIZE" {
  type    = string
  default = "60"
  description = "The volume size for the root volume in GiB"
}

variable "EC2_ROOT_VOLUME_TYPE" {
  type    = string
  default = "standard"
  description = "The type of data storage: standard, gp2, io1"
}