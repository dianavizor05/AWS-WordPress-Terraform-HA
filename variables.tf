variable "project_name" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "wordpress-project"
}

variable "aws_region" {
  description = "AWS region. Project supports us-east-2 and us-west-2."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = contains(["us-east-2", "us-west-2"], var.aws_region)
    error_message = "Allowed regions are us-east-2 and us-west-2."
  }
}

variable "environment" {
  description = "Environment type: TEST, DEVELOPER, or PRODUCTION."
  type        = string
  default     = "TEST"

  validation {
    condition     = contains(["TEST", "DEVELOPER", "PRODUCTION"], upper(var.environment))
    error_message = "Environment must be TEST, DEVELOPER, or PRODUCTION."
  }
}

variable "key_name" {
  description = "Name of an existing EC2 Key Pair used for SSH."
  type        = string
}

variable "admin_ip_cidr" {
  description = "Your public IP address in CIDR format for SSH access to bastion hosts, for example 1.2.3.4/32."
  type        = string
}

variable "db_name" {
  description = "WordPress database name."
  type        = string
  default     = "wordpressdb"
}

variable "db_username" {
  description = "WordPress database username."
  type        = string
  default     = "wpadmin"
}

variable "db_password" {
  description = "WordPress database password."
  type        = string
  sensitive   = true
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS listener. Leave empty for HTTP only."
  type        = string
  default     = ""
}