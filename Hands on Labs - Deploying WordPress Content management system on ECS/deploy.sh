#!/bin/bash

# WordPress on ECS Deployment Script
# Built with Amazon Q Developer CLI

set -e

echo "🚀 Starting WordPress on ECS deployment..."

# Variables (Update these for your deployment)
REGION="us-east-1"
CLUSTER_NAME="wordpress-cluster"
SERVICE_NAME="wordpress-service"
TASK_FAMILY="wordpress-task"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "📋 AWS Account ID: $ACCOUNT_ID"

# Get Default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
echo "🌐 Using VPC: $VPC_ID"

# Get Subnets
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[].SubnetId" --output text --region $REGION)
SUBNET_ARRAY=(${SUBNETS})
echo "🏗️  Using Subnets: ${SUBNET_ARRAY[@]}"

# Step 1: Create ECS Cluster
echo "1️⃣  Creating ECS Cluster..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION

# Step 2: Create Security Group
echo "2️⃣  Creating Security Group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name wordpress-sg \
  --description "Security group for WordPress ECS" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' --output text)
echo "🔒 Security Group ID: $SG_ID"

# Step 3: Create IAM Role
echo "3️⃣  Creating IAM Role..."
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://trust-policy.json \
  --region $REGION || echo "Role may already exist"

aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  --region $REGION || echo "Policy may already be attached"

# Step 4: Create CloudWatch Log Group
echo "4️⃣  Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name /ecs/wordpress --region $REGION || echo "Log group may already exist"

# Step 5: Update Task Definition with Account ID
echo "5️⃣  Updating Task Definition..."
sed "s/YOUR_ACCOUNT_ID/$ACCOUNT_ID/g" wordpress-task-definition.json > wordpress-task-definition-updated.json

# Step 6: Register Task Definition
echo "6️⃣  Registering Task Definition..."
aws ecs register-task-definition \
  --cli-input-json file://wordpress-task-definition-updated.json \
  --region $REGION

# Step 7: Create Application Load Balancer
echo "7️⃣  Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name wordpress-alb \
  --subnets ${SUBNET_ARRAY[@]} \
  --security-groups $SG_ID \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "⚖️  ALB DNS: $ALB_DNS"

# Step 8: Create Target Group
echo "8️⃣  Creating Target Group..."
TG_ARN=$(aws elbv2 create-target-group \
  --name wordpress-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path / \
  --health-check-interval-seconds 10 \
  --health-check-timeout-seconds 2 \
  --healthy-threshold-count 2 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Modify target group to accept 200,302 responses
aws elbv2 modify-target-group \
  --target-group-arn $TG_ARN \
  --matcher '{"HttpCode":"200,302"}' \
  --region $REGION

echo "🎯 Target Group ARN: $TG_ARN"

# Step 9: Create Listener
echo "9️⃣  Creating ALB Listener..."
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION

# Step 10: Create ECS Service
echo "🔟 Creating ECS Service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ARRAY[0]},${SUBNET_ARRAY[1]}],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=$TG_ARN,containerName=wordpress,containerPort=80 \
  --region $REGION

echo "✅ Basic infrastructure deployed!"
echo ""
echo "📝 Next Steps:"
echo "1. Create WAF Web ACL using waf-config.json"
echo "2. Create CloudFront Distribution using cloudfront-config.json"
echo "3. Configure CloudFront-only access security"
echo "4. Update WordPress URLs to use CloudFront domain"
echo ""
echo "🌐 ALB DNS Name: $ALB_DNS"
echo "🔒 Security Group ID: $SG_ID"
echo "🎯 Target Group ARN: $TG_ARN"
echo ""
echo "⚠️  Remember to:"
echo "   - Change default passwords in task definition"
echo "   - Update CloudFront domain in WordPress configuration"
echo "   - Configure security group for CloudFront-only access"
