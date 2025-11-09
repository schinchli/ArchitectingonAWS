#!/bin/bash

# WordPress ECS Deployment Validation Script
# Tests the deployment using existing infrastructure

set -e

REGION=${1:-us-east-1}
ENV="validation"
CLUSTER_NAME="wordpress-cluster-${ENV}"
SERVICE_NAME="wordpress-service-${ENV}"
ALB_NAME="wordpress-alb-${ENV}"
TG_NAME="wordpress-tg-${ENV}"

echo "🧪 Validating WordPress ECS deployment in region: $REGION"

# Use existing private subnets (replace with your actual subnet IDs)
PRIVATE_SUBNET_1="subnet-XXXXXXXXXXXXXXXXX"  # Replace with your private subnet 1
PRIVATE_SUBNET_2="subnet-XXXXXXXXXXXXXXXXX"  # Replace with your private subnet 2

# Use existing security groups from main deployment (replace with your actual security group IDs)
ALB_SG_ID="sg-XXXXXXXXXXXXXXXXX"      # Replace with your ALB security group ID
CONTAINER_SG_ID="sg-XXXXXXXXXXXXXXXXX" # Replace with your container security group ID

echo "📋 Using existing infrastructure:"
echo "  - Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo "  - Security Groups: ALB=$ALB_SG_ID, Container=$CONTAINER_SG_ID"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $REGION)

# Create ECS cluster
echo "🐳 Creating validation ECS cluster..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $REGION

# Create CloudWatch log group
echo "📊 Creating CloudWatch log group..."
aws logs create-log-group --log-group-name "/ecs/wordpress-$ENV" --region $REGION 2>/dev/null || echo "Log group already exists"

# Update task definition
echo "📝 Creating validation task definition..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -e "s|/ecs/wordpress|/ecs/wordpress-$ENV|g" \
    -e "s|YOUR_ACCOUNT_ID|$ACCOUNT_ID|g" \
    -e "s|us-east-1|$REGION|g" \
    wordpress-task-definition.json > "wordpress-task-definition-$ENV.json"

# Register task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://wordpress-task-definition-$ENV.json \
  --region $REGION \
  --query "taskDefinition.taskDefinitionArn" --output text)

echo "Task definition registered: $TASK_DEF_ARN"

# Get public subnets for ALB
PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[0:2].SubnetId" --output text --region $REGION)

# Create ALB
echo "⚖️ Creating validation ALB..."
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
  --matcher '{"HttpCode":"200,302"}' \
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
echo "🚀 Creating validation ECS service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_DEF_ARN \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2],securityGroups=[$CONTAINER_SG_ID],assignPublicIp=DISABLED}" \
  --load-balancers targetGroupArn=$TG_ARN,containerName=wordpress,containerPort=80 \
  --region $REGION

echo "⏳ Waiting for service to stabilize..."
sleep 60

# Test the deployment
echo "🧪 Testing WordPress deployment..."
for i in {1..10}; do
  echo "Test attempt $i/10..."
  if curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS" | grep -q "302\|200"; then
    echo "✅ WordPress is responding correctly!"
    break
  fi
  if [ $i -eq 10 ]; then
    echo "❌ WordPress not responding after 10 attempts"
    exit 1
  fi
  sleep 30
done

# Check service health
echo "🔍 Checking service health..."
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}" \
  --output table

# Check target health
echo "🎯 Checking target group health..."
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $REGION \
  --query "TargetHealthDescriptions[0].{Target:Target.Id,Health:TargetHealth.State}" \
  --output table

echo "✅ Validation completed successfully!"
echo "🌐 WordPress URL: http://$ALB_DNS"

# Save validation results
cat > "validation-results.json" << EOF
{
  "region": "$REGION",
  "environment": "$ENV",
  "cluster": "$CLUSTER_NAME",
  "service": "$SERVICE_NAME",
  "alb_dns": "$ALB_DNS",
  "status": "success",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "📄 Validation results saved to: validation-results.json"
