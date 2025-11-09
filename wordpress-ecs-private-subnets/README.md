# WordPress on AWS ECS with Enhanced Security

> **Production-ready WordPress deployment on AWS ECS Fargate with private subnet architecture**

## 🏗️ Architecture Overview

This project demonstrates deploying a secure WordPress application on AWS ECS Fargate with enterprise-grade security features including private subnets, dedicated security groups, and NAT Gateway for controlled internet access.

```mermaid
graph TB
    subgraph "Internet"
        U[Users]
    end
    
    subgraph "AWS Region: us-east-1"
        subgraph "VPC: Default VPC (172.31.0.0/16)"
            subgraph "Public Subnets (Multi-AZ)"
                ALB[Application Load Balancer<br/>Internet-Facing<br/>Port 80]
                NAT[NAT Gateway<br/>98.82.207.73<br/>Outbound Internet Access]
            end
            
            subgraph "Private Subnets (Multi-AZ)"
                subgraph "us-east-1a: 172.31.96.0/20"
                    subgraph "ECS Cluster: Fargate"
                        subgraph "Task Definition"
                            WP1[WordPress Container<br/>Port 80<br/>No Public IP]
                            DB1[MySQL 5.7 Container<br/>Port 3306<br/>Health Check Enabled]
                        end
                    end
                end
                
                subgraph "us-east-1b: 172.31.112.0/20"
                    subgraph "ECS Cluster: Fargate"
                        subgraph "Task Definition"
                            WP2[WordPress Container<br/>Port 80<br/>No Public IP]
                            DB2[MySQL 5.7 Container<br/>Port 3306<br/>Health Check Enabled]
                        end
                    end
                end
            end
            
            ALBSG[ALB Security Group<br/>sg-0935e322c5774b1ed<br/>Inbound: 0.0.0.0/0:80]
            APPSG[Container Security Group<br/>sg-0af75bfdf1a9ce600<br/>Inbound: ALB SG Only]
            TG[Target Group<br/>Health Check: 200,302<br/>10s interval, 2s timeout]
            RT[Private Route Table<br/>0.0.0.0/0 → NAT Gateway]
        end
        
        CW[CloudWatch Logs<br/>/ecs/wordpress]
        IAM[IAM Role<br/>ecsTaskExecutionRole]
    end
    
    U -->|HTTP/HTTPS| ALB
    ALB -->|Load Balance| TG
    TG -->|Health Checks| WP1
    TG -->|Health Checks| WP2
    WP1 -->|127.0.0.1:3306| DB1
    WP2 -->|127.0.0.1:3306| DB2
    WP1 -->|Internet Access| NAT
    WP2 -->|Internet Access| NAT
    NAT -->|Docker Pulls/Updates| U
    WP1 -->|Logs| CW
    WP2 -->|Logs| CW
    DB1 -->|Logs| CW
    DB2 -->|Logs| CW
    ALBSG -.->|Protects| ALB
    APPSG -.->|Protects| WP1
    APPSG -.->|Protects| WP2
    RT -.->|Routes Traffic| NAT
    IAM -.->|Execution Role| WP1
    IAM -.->|Execution Role| WP2
    
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef security fill:#FF4B4B,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef container fill:#4B9AFF,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef network fill:#9D5AAE,stroke:#232F3E,stroke-width:2px,color:#fff
    
    class ALB,TG,CW,IAM,NAT aws
    class ALBSG,APPSG security
    class WP1,WP2,DB1,DB2 container
    class RT network
```

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Basic understanding of AWS services

### 1. Clone Repository
```bash
git clone https://github.com/schinchli/ArchitectingonAWS.git
cd ArchitectingonAWS/wordpress-ecs-amazonq
```

### 2. Deploy Infrastructure
Follow the step-by-step commands in the deployment guide below, or use the provided deployment script.

## 📋 Infrastructure Components

### Core Services
- **ECS Cluster**: Fargate-based container orchestration in private subnets
- **Task Definition**: WordPress + MySQL containers with health checks
- **Application Load Balancer**: Multi-AZ load balancing in public subnets
- **NAT Gateway**: Controlled internet access for private subnet containers
- **Private Subnets**: Isolated container environment (172.31.96.0/20, 172.31.112.0/20)
- **Security Groups**: Dedicated groups for ALB and containers

### Security Features
- ✅ **Private Subnet Architecture**: Containers have no public IP addresses
- ✅ **Dedicated Security Groups**: Separate groups for ALB and containers
- ✅ **Least Privilege Access**: Container access only from ALB security group
- ✅ **NAT Gateway**: Controlled outbound internet access for updates
- ✅ **Multi-AZ Deployment**: High availability across availability zones
- ✅ **Network Isolation**: Defense in depth with multiple security layers

## 🛠️ Deployment Guide

### Step 1: Create ECS Cluster
```bash
aws ecs create-cluster --cluster-name wordpress-cluster --region us-east-1
```

### Step 2: Create Private Subnets
```bash
# Get your default VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region us-east-1)

# Create private subnets
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 172.31.96.0/20 \
  --availability-zone us-east-1a \
  --region us-east-1

aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 172.31.112.0/20 \
  --availability-zone us-east-1b \
  --region us-east-1
```

### Step 3: Create NAT Gateway
```bash
# Get public subnet ID
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[0].SubnetId" --output text --region us-east-1)

# Allocate Elastic IP
aws ec2 allocate-address --domain vpc --region us-east-1

# Create NAT Gateway (replace EIP_ALLOC_ID with your allocation ID)
aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_ID \
  --allocation-id $EIP_ALLOC_ID \
  --region us-east-1
```

### Step 4: Configure Route Table
```bash
# Create private route table
aws ec2 create-route-table --vpc-id $VPC_ID --region us-east-1

# Add route to NAT Gateway (replace NAT_GATEWAY_ID and ROUTE_TABLE_ID)
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GATEWAY_ID \
  --region us-east-1

# Associate private subnets with route table
aws ec2 associate-route-table \
  --subnet-id $PRIVATE_SUBNET_1_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region us-east-1

aws ec2 associate-route-table \
  --subnet-id $PRIVATE_SUBNET_2_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region us-east-1
```

### Step 5: Create Security Groups
```bash
# Create ALB security group
aws ec2 create-security-group \
  --group-name wordpress-alb-sg \
  --description "Security group for WordPress ALB" \
  --vpc-id $VPC_ID \
  --region us-east-1

# Create container security group
aws ec2 create-security-group \
  --group-name wordpress-container-sg \
  --description "Security group for WordPress containers" \
  --vpc-id $VPC_ID \
  --region us-east-1

# Allow HTTP access to ALB from internet
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1

# Allow container access only from ALB security group
aws ec2 authorize-security-group-ingress \
  --group-id $CONTAINER_SG_ID \
  --protocol tcp \
  --port 80 \
  --source-group $ALB_SG_ID \
  --region us-east-1
```

### Step 6: Create IAM Role
```bash
# Create trust policy file
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://trust-policy.json \
  --region us-east-1

# Attach policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  --region us-east-1
```

### Step 7: Create CloudWatch Log Group
```bash
aws logs create-log-group --log-group-name /ecs/wordpress --region us-east-1
```

### Step 8: Register Task Definition
Use the provided `wordpress-task-definition.json` file:
```bash
aws ecs register-task-definition \
  --cli-input-json file://wordpress-task-definition.json \
  --region us-east-1
```

### Step 9: Create Application Load Balancer
```bash
# Get public subnet IDs
PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[].SubnetId" --output text --region us-east-1)

# Create ALB in public subnets
aws elbv2 create-load-balancer \
  --name wordpress-alb \
  --subnets $PUBLIC_SUBNET_IDS \
  --security-groups $ALB_SG_ID \
  --region us-east-1
```

### Step 10: Create Target Group
```bash
aws elbv2 create-target-group \
  --name wordpress-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path / \
  --matcher HttpCode=200,302 \
  --health-check-interval-seconds 10 \
  --health-check-timeout-seconds 2 \
  --healthy-threshold-count 2 \
  --region us-east-1
```

### Step 11: Create ECS Service
```bash
# Get private subnet IDs
PRIVATE_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=172.31.96.0/20,172.31.112.0/20" --query "Subnets[].SubnetId" --output text --region us-east-1)

# Create service in private subnets
aws ecs create-service \
  --cluster wordpress-cluster \
  --service-name wordpress-service \
  --task-definition wordpress-task:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_IDS],securityGroups=[$CONTAINER_SG_ID],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=$TARGET_GROUP_ARN,containerName=wordpress,containerPort=80 \
  --region us-east-1
```

## 📁 Configuration Files

All configuration files are provided in this repository:

- `wordpress-task-definition.json` - ECS task definition with WordPress and MySQL
- `waf-config.json` - WAF configuration with security rules
- `cloudfront-config.json` - CloudFront distribution configuration
- `trust-policy.json` - IAM role trust policy

## 🔒 Security Best Practices

### Implemented Security Measures
1. **Network Security**: Private subnets with no public IP addresses for containers
2. **Access Control**: Dedicated security groups with least privilege access
3. **Internet Access**: Controlled outbound access through NAT Gateway
4. **Defense in Depth**: Multiple security layers (ALB → Security Groups → Private Subnets)
5. **Monitoring**: CloudWatch logs for all components
6. **High Availability**: Multi-AZ deployment for resilience

### Production Recommendations
1. **HTTPS/TLS**: Add SSL/TLS termination at ALB with ACM certificate
2. **WAF Integration**: Add AWS WAF for application-layer protection
3. **Database**: Replace MySQL container with RDS in private subnets
4. **Secrets**: Use AWS Secrets Manager for database credentials
5. **VPC Flow Logs**: Enable for network traffic monitoring
6. **CloudTrail**: Enable for API call auditing
7. **Container Scanning**: Use ECR image scanning for vulnerabilities

## 🎯 Access Your WordPress

After deployment completes (5-10 minutes):

1. **WordPress Installation**: `http://YOUR_ALB_DNS_NAME/wp-admin/install.php`
2. **Website**: `http://YOUR_ALB_DNS_NAME`

**Note**: The ALB DNS name will be provided after ALB creation. Containers are in private subnets for enhanced security.

## 💰 Cost Optimization

- **Fargate Spot**: Consider for non-production workloads
- **Auto Scaling**: Configure based on CPU/memory utilization
- **Reserved Capacity**: For predictable workloads
- **CloudFront Caching**: Reduces origin load and costs

## 🔧 Troubleshooting

### Common Issues
1. **502/504 Errors**: Check target group health, security group rules, NAT Gateway connectivity
2. **Database Connection**: Verify container networking (127.0.0.1:3306)
3. **Container Startup Issues**: Check NAT Gateway for Docker image pulls
4. **Health Check Failures**: Verify health check accepts 200,302 responses
5. **Internet Access**: Ensure NAT Gateway route is configured correctly

### Monitoring Commands
```bash
# Check ECS service status
aws ecs describe-services --cluster wordpress-cluster --services wordpress-service --region us-east-1

# Check target health
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region us-east-1

# Check NAT Gateway status
aws ec2 describe-nat-gateways --region us-east-1

# Check route table configuration
aws ec2 describe-route-tables --region us-east-1
```

## 📚 Additional Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [AWS WAF Documentation](https://docs.aws.amazon.com/waf/)

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

**⚠️ Important**: This configuration is for demonstration purposes. For production use, implement additional security measures, monitoring, and backup strategies as outlined in the security best practices section.
