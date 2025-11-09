# Security Configuration Guide

## 🔒 Security Features Overview

This WordPress deployment implements multiple layers of security:

### 1. Network Security
- **CloudFront-Only Access**: Direct ALB access blocked
- **Security Groups**: Restrictive ingress rules
- **VPC**: Isolated network environment

### 2. Application Security
- **WAF Protection**: OWASP Top 10 coverage
- **Rate Limiting**: DDoS protection
- **HTTPS Enforcement**: All traffic encrypted

### 3. Container Security
- **Health Checks**: Container monitoring
- **Least Privilege**: Minimal IAM permissions
- **Log Monitoring**: CloudWatch integration

## 🛡️ Security Configuration Steps

### Step 1: Configure CloudFront-Only Access

```bash
# Get CloudFront prefix list ID
PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
  --query "PrefixLists[0].PrefixListId" --output text --region us-east-1)

# Remove public access from security group
aws ec2 revoke-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1

# Allow CloudFront access only
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --ip-permissions "[{\"IpProtocol\":\"tcp\",\"PrefixListIds\":[{\"PrefixListId\":\"$PREFIX_LIST_ID\"}],\"FromPort\":80,\"ToPort\":80}]" \
  --region us-east-1
```

### Step 2: Allow ALB Health Checks

```bash
# Get subnet CIDR blocks for ALB
SUBNET_CIDRS=$(aws ec2 describe-subnets \
  --YOUR_SUBNET_ID $SUBNET_ID_1 $SUBNET_ID_2 \
  --query "Subnets[].CidrBlock" --output text --region us-east-1)

# Allow health checks from ALB subnets
for CIDR in $SUBNET_CIDRS; do
  aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"IpRanges\":[{\"CidrIp\":\"$CIDR\",\"Description\":\"ALB health checks\"}]}]" \
    --region us-east-1
done
```

### Step 3: Verify Security Configuration

```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP_ID \
  --region us-east-1

# Test direct ALB access (should timeout)
curl -I --connect-timeout 10 http://$ALB_DNS_NAME

# Test CloudFront access (should work)
curl -I https://$CLOUDFRONT_DOMAIN
```

## 🚨 Security Checklist

### Pre-Deployment
- [ ] Change default passwords in task definition
- [ ] Review IAM role permissions
- [ ] Validate VPC and subnet configuration
- [ ] Configure CloudWatch log retention

### Post-Deployment
- [ ] Verify CloudFront-only access
- [ ] Test WAF rules
- [ ] Monitor CloudWatch logs
- [ ] Set up security alerts

### Production Hardening
- [ ] Use AWS Secrets Manager for credentials
- [ ] Implement RDS instead of container MySQL
- [ ] Add custom SSL certificate
- [ ] Configure backup strategy
- [ ] Set up monitoring and alerting

## 🔍 Security Monitoring

### CloudWatch Metrics to Monitor
- WAF blocked requests
- ALB target health
- ECS task health
- CloudFront error rates

### Recommended Alarms
```bash
# WAF blocked requests alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "WAF-High-Blocked-Requests" \
  --alarm-description "High number of blocked requests" \
  --metric-name "BlockedRequests" \
  --namespace "AWS/WAFV2" \
  --statistic Sum \
  --period 300 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2

# ALB unhealthy targets alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "ALB-Unhealthy-Targets" \
  --alarm-description "ALB has unhealthy targets" \
  --metric-name "UnHealthyHostCount" \
  --namespace "AWS/ApplicationELB" \
  --statistic Average \
  --period 60 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## 🛠️ Incident Response

### Common Security Issues

1. **High WAF Block Rate**
   - Check WAF logs for patterns
   - Adjust rules if false positives
   - Investigate source IPs

2. **Direct ALB Access Attempts**
   - Verify security group configuration
   - Check CloudTrail for configuration changes
   - Monitor for reconnaissance attempts

3. **Container Compromise**
   - Review CloudWatch logs
   - Check for unusual network activity
   - Rotate credentials immediately

### Emergency Procedures

1. **Block Malicious Traffic**
   ```bash
   # Add IP to WAF block list
   aws wafv2 update-ip-set \
     --scope CLOUDFRONT \
     --id $IP_SET_ID \
     --addresses $MALICIOUS_IP/32
   ```

2. **Disable Service**
   ```bash
   # Scale service to 0
   aws ecs update-service \
     --cluster $CLUSTER_NAME \
     --service $SERVICE_NAME \
     --desired-count 0
   ```

3. **Enable Maintenance Mode**
   - Update CloudFront to serve maintenance page
   - Investigate and remediate issues
   - Restore service when secure

## 📋 Compliance Considerations

### Data Protection
- WordPress data stored in containers (ephemeral)
- Database credentials in environment variables
- Consider encryption at rest for production

### Access Logging
- CloudFront access logs available
- ALB access logs can be enabled
- WAF logs available in CloudWatch

### Audit Trail
- CloudTrail logs all API calls
- ECS task state changes logged
- Security group changes tracked

## 🔗 Security Resources

- [AWS Security Best Practices](https://aws.amazon.com/security/security-resources/)
- [ECS Security Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security.html)
- [CloudFront Security](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/security.html)
- [WAF Security](https://docs.aws.amazon.com/waf/latest/developerguide/security.html)
