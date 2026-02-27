# Guidance-Grade Three-Tier Production Stack (AWS)
**Lead Enterprise Solutions Architect:** Dan Alwende, PMP

## 🏗️ Project Architecture
This project demonstrates the deployment of a resilient, serverless, and globally distributed application stack on AWS. It utilizes a **"Sovereign Factory"** approach where every tier is governed by code.



## 🛠️ Tech Stack
- **Edge:** Amazon CloudFront (CDN)
- **Identity:** Amazon Cognito (User Auth)
- **Compute:** AWS ECS Fargate (Serverless Containers)
- **Load Balancing:** Application Load Balancer (Multi-AZ)
- **Database:** Amazon DynamoDB (NoSQL)
- **Network:** VPC with NAT Gateway (Private Isolation)

## 🚀 Deployment Instructions
```bash
terraform init
terraform apply -auto-approve
```

---
*Developed for the Wakwetu Executive Project Portfolio.*
