# WordPress ECS Private Subnets - Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying WordPress on AWS ECS Fargate with private subnet architecture for enhanced security.

## Architecture

- **Private Subnets**: Containers run without public IP addresses
- **NAT Gateway**: Provides controlled internet access for container operations
- **Dedicated Security Groups**: Separate groups for ALB and containers
- **Multi-AZ Deployment**: High availability across availability zones

## Prerequisites

- AWS CLI configured with appropriate permissions
- Basic understanding of AWS services (ECS, VPC, ALB)
- Account with permissions for ECS, EC2, IAM, and ELB services

## Deployment Options

### Option 1: Automated Deployment Script

Use the provided deployment script for quick setup:

```bash
# Deploy to us-east-1 with 'prod' environment
./deploy-multi-region.sh us-east-1 prod

# Deploy to us-west-1 with 'dev' environment  
./deploy-multi-region.sh us-west-1 dev
```

### Option 2: Manual Step-by-Step Deployment

Follow the detailed steps in the main README.md file.

## Validation

After deployment, validate the setup:

```bash
# Run validation script
./validate-deployment.sh us-east-1

# Manual validation
curl -I http://YOUR_ALB_DNS_NAME
```

Expected response: HTTP 302 redirect to WordPress installation page.

## Troubleshooting

### Common Issues

1. **Service Control Policies**: Some AWS accounts have SCPs that restrict deployment to specific regions
2. **IAM Permissions**: Ensure the user has necessary permissions for all AWS services
3. **CIDR Conflicts**: Modify CIDR blocks if subnets already exist
4. **Container Startup Time**: WordPress containers may take 3-5 minutes to become healthy

### Debugging Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster CLUSTER_NAME --services SERVICE_NAME --region REGION

# Check target group health
aws elbv2 describe-target-health --target-group-arn TARGET_GROUP_ARN --region REGION

# Check container logs
aws logs get-log-events --log-group-name /ecs/wordpress-ENV --log-stream-name STREAM_NAME --region REGION
```

## Security Considerations

### Implemented Security Features

- ✅ **Network Isolation**: Containers in private subnets with no public IPs
- ✅ **Least Privilege**: Security groups allow only necessary traffic
- ✅ **Controlled Internet Access**: NAT Gateway for outbound connections only
- ✅ **Defense in Depth**: Multiple security layers

### Production Recommendations

1. **HTTPS/TLS**: Add SSL certificate and redirect HTTP to HTTPS
2. **WAF**: Add AWS WAF for application-layer protection
3. **Database**: Replace MySQL container with RDS in private subnets
4. **Secrets Management**: Use AWS Secrets Manager for credentials
5. **Monitoring**: Set up CloudWatch alarms and notifications
6. **Backup**: Implement automated backup strategy

## Cost Optimization

- **NAT Gateway**: Consider NAT instances for lower-cost environments
- **Fargate Spot**: Use for non-production workloads
- **Auto Scaling**: Configure based on actual usage patterns
- **Reserved Capacity**: For predictable production workloads

## Multi-Region Deployment

The deployment scripts support multiple regions. Ensure:

1. **Service Availability**: Verify ECS is available in target region
2. **Account Permissions**: Check for service control policies
3. **Resource Limits**: Ensure account limits allow additional resources
4. **Compliance**: Consider data residency requirements

## Cleanup

To remove all resources:

```bash
# Delete ECS service and cluster
aws ecs update-service --cluster CLUSTER_NAME --service SERVICE_NAME --desired-count 0 --region REGION
aws ecs delete-service --cluster CLUSTER_NAME --service SERVICE_NAME --region REGION
aws ecs delete-cluster --cluster CLUSTER_NAME --region REGION

# Delete ALB and target group
aws elbv2 delete-load-balancer --load-balancer-arn ALB_ARN --region REGION
aws elbv2 delete-target-group --target-group-arn TG_ARN --region REGION

# Delete NAT Gateway and Elastic IP
aws ec2 delete-YOUR_NAT_GATEWAY_ID --YOUR_NAT_GATEWAY_ID-id NAT_GATEWAY_ID --region REGION
aws ec2 release-address --allocation-id EIP_ALLOCATION_ID --region REGION

# Delete subnets and security groups
aws ec2 delete-subnet --YOUR_SUBNET_ID SUBNET_ID --region REGION
aws ec2 delete-security-group --group-id SG_ID --region REGION
```

## Support

For issues or questions:

1. Check the troubleshooting section
2. Review AWS CloudWatch logs
3. Verify security group and network configuration
4. Ensure all prerequisites are met

## Version History

- **v1.0**: Initial private subnet architecture
- **v1.1**: Added multi-region deployment support
- **v1.2**: Enhanced security with dedicated security groups
