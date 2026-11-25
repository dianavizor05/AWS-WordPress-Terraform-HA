# WordPress Infrastructure on AWS (Terraform)

A Terraform project that automatically builds and configures cloud infrastructure on AWS to run a WordPress website.

## What This Project Builds
- **Network (VPC):** Public subnets (for Load Balancer and Bastion Hosts) and private subnets (for servers and database).
- **Servers & Scaling:** Amazon Linux 2023 EC2 instances managed by Auto Scaling, running WordPress in Docker.
- **Database & Storage:** MySQL database (RDS) and shared file storage (EFS) in private subnets.
- **Security:** Firewall rules (Security Groups) allowing SSH access only through Bastion Hosts.
- **Environments:** Ready to deploy as `TEST`, `DEVELOPER`, or `PRODUCTION`.

## Files
- `main.tf` - main AWS infrastructure setup
- `variables.tf` - configuration variables (region, environment, database settings)
- `outputs.tf` - shows created URLs and endpoints after deployment
- `user_data.sh` - Linux setup script

## Tech Stack
- Terraform, AWS (VPC, EC2, Auto Scaling, ALB, RDS, EFS), Docker, Linux (Bash)
