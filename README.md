# WordPress Infrastructure on AWS (Terraform)

A Terraform project that automatically builds and configures cloud infrastructure on AWS to run a WordPress website.

## What This Project Builds
- **Network (VPC):** Public subnets (for Load Balancer and Bastion Hosts) and private subnets (for servers and database)[cite: 6].
- **Servers & Scaling:** Amazon Linux 2023 EC2 instances managed by Auto Scaling, running WordPress in Docker[cite: 6].
- **Database & Storage:** MySQL database (RDS) and shared file storage (EFS) in private subnets[cite: 6].
- **Security:** Firewall rules (Security Groups) allowing SSH access only through Bastion Hosts[cite: 6].
- **Environments:** Ready to deploy as `TEST`, `DEVELOPER`, or `PRODUCTION`[cite: 6, 12].

## Files
- `main.tf` - main AWS infrastructure setup[cite: 6]
- `variables.tf` - configuration variables (region, environment, database settings)[cite: 12]
- `outputs.tf` - shows created URLs and endpoints after deployment[cite: 7]
- `user_data.sh` - Linux setup script[cite: 11]

## Tech Stack
- Terraform, AWS (VPC, EC2, Auto Scaling, ALB, RDS, EFS), Docker, Linux (Bash)[cite: 6, 11]
