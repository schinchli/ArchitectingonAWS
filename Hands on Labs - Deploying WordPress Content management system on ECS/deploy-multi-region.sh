#!/bin/bash

# WordPress ECS Private Subnets Deployment Script
# Usage: ./deploy-multi-region.sh <region> <environment>
# Example: ./deploy-multi-region.sh us-west-2 prod

set -e

REGION=${1:-us-east-1}
ENV=${2:-dev}
CLUSTER_NAME="wordpress-cluster-${ENV}"
SERVICE_NAME="wordpress-service-${ENV}"
ALB_NAME="wordpress-alb-${ENV}"
TG_NAME="wordpress-tg-${ENV}"
ALB_SG_NAME="wordpress-alb-sg-${ENV}"
CONTAINER_SG_NAME="wordpress-container-sg-${ENV}"

echo "🚀 Deploying WordPress ECS to region: $REGION, environment: $ENV"

# Get default VPC
echo "📋 Getting VPC information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)
echo "VPC ID: $VPC_ID"

# Get availability zones
AZ1=$(aws ec2 describe-availability-zones --region $REGION --query "AvailabilityZones[0].ZoneName" --output text)
AZ2=$(aws ec2 describe-availability-zones --region $REGION --query "AvailabilityZones[1].ZoneName" --output text)
echo "Using AZs: $AZ1, $AZ2"

# Create private subnets with environment-specific CIDR blocks
echo "🔒 Creating private subnets..."
if [ "$ENV" = "test" ]; then
  CIDR1="172.31.128.0/20"
  CIDR2="172.31.144.0/20"
else
  CIDR1="172.31.96.0/20"
  CIDR2="172.31.112.0/20"
fi

PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $CIDR1 \
  --availability-zone $AZ1 \
  --region $REGION \
  --query "Subnet.SubnetId" --output text)

PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $CIDR2 \
  --availability-zone $AZ2 \
  --region $REGION \
  --query "Subnet.SubnetId" --output text)

echo "Private subnets created: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"

# Get public subnet for NAT Gateway
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[0].SubnetId" --output text --region $REGION)

# Create NAT Gateway
echo "🌐 Creating NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region $REGION --query "AllocationId" --output text)
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_ID \
  --allocation-id $EIP_ALLOC_ID \
  --region $REGION \
  --query "NatGateway.NatGatewayId" --output text)

echo "NAT Gateway created: $NAT_GATEWAY_ID"

# Wait for NAT Gateway to be available
echo "⏳ Waiting for NAT Gateway to be available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GATEWAY_ID --region $REGION

# Create route table
echo "🛣️ Creating route table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query "RouteTable.RouteTableId" --output text)

aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GATEWAY_ID \
  --region $REGION

# Associate private subnets with route table
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1 --route-table-id $ROUTE_TABLE_ID --region $REGION
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2 --route-table-id $ROUTE_TABLE_ID --region $REGION

# Create security groups
echo "🔐 Creating security groups..."
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name $ALB_SG_NAME \
  --description "Security group for WordPress ALB - $ENV" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" --output text)

CONTAINER_SG_ID=$(aws ec2 create-security-group \
  --group-name $CONTAINER_SG_NAME \
  --description "Security group for WordPress containers - $ENV" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" --output text)

# Configure security group rules
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $CONTAINER_SG_ID \
  --protocol tcp \
  --port 80 \
  --source-group $ALB_SG_ID \
  --region $REGION

# Create ECS cluster
echo "🐳 Creating ECS cluster..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION

# Create CloudWatch log group
echo "📊 Creating CloudWatch log group..."
aws logs create-log-group --log-group-name "/ecs/wordpress-$ENV" --region $REGION 2>/dev/null || echo "Log group already exists"

# Check if IAM role exists, create if not
echo "🔑 Checking IAM role..."
if ! aws iam get-role --role-name ecsTaskExecutionRole --region $REGION >/dev/null 2>&1; then
  echo "Creating IAM role..."
  aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document file://trust-policy.json \
    --region $REGION

  aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
    --region $REGION
  
  echo "Waiting for IAM role to propagate..."
  sleep 10
fi

# Update task definition for this environment
echo "📝 Updating task definition..."
sed "s|/ecs/wordpress|/ecs/wordpress-$ENV|g" wordpress-task-definition.json > "wordpress-task-definition-$ENV.json"

# Register task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://wordpress-task-definition-$ENV.json \
  --region $REGION \
  --query "taskDefinition.taskDefinitionArn" --output text)

echo "Task definition registered: $TASK_DEF_ARN"

# Get public subnets for ALB
PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[].SubnetId" --output text --region $REGION)

# Create ALB
echo "⚖️ Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name $ALB_NAME \
  --subnets $PUBLIC_SUBNET_IDS \
  --security-groups $ALB_SG_ID \
  --region $REGION \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query "LoadBalancers[0].DNSName" --output text)

echo "ALB created: $ALB_DNS"

# Create target group
echo "🎯 Creating target group..."
TG_ARN=$(aws elbv2 create-target-group \
  --name $TG_NAME \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path / \
  --matcher HttpCode=200,302 \
  --health-check-interval-seconds 10 \
  --health-check-timeout-seconds 2 \
  --healthy-threshold-count 2 \
  --region $REGION \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION

# Create ECS service
echo "🚀 Creating ECS service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_DEF_ARN \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2],securityGroups=[$CONTAINER_SG_ID],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=$TG_ARN,containerName=wordpress,containerPort=80 \
  --region $REGION

echo "✅ Deployment completed!"
echo "🌐 WordPress URL: http://$ALB_DNS"
echo "📋 Resources created:"
echo "  - Cluster: $CLUSTER_NAME"
echo "  - Service: $SERVICE_NAME"
echo "  - ALB: $ALB_DNS"
echo "  - Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "  - NAT Gateway: $NAT_GATEWAY_ID"

# Save deployment info
cat > "deployment-info-$ENV.json" << EOF
{
  "region": "$REGION",
  "environment": "$ENV",
  "cluster": "$CLUSTER_NAME",
  "service": "$SERVICE_NAME",
  "alb_dns": "$ALB_DNS",
  "alb_arn": "$ALB_ARN",
  "target_group_arn": "$TG_ARN",
  "private_subnets": ["$PRIVATE_SUBNET_1", "$PRIVATE_SUBNET_2"],
  "nat_gateway_id": "$NAT_GATEWAY_ID",
  "alb_security_group": "$ALB_SG_ID",
  "container_security_group": "$CONTAINER_SG_ID"
}
EOF

echo "📄 Deployment info saved to: deployment-info-$ENV.json"
