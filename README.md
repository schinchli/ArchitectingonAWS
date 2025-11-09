# ArchitectingonAWS

> **Production-ready AWS Architecture Projects**

This repository contains enterprise-grade AWS architecture implementations with comprehensive security features and deployment automation.

## 🚀 Projects

### [WordPress on ECS with Enhanced Security](./wordpress-ecs-amazonq/)

A complete production-ready WordPress deployment on AWS ECS Fargate with comprehensive security features:

- **🏗️ Architecture**: ECS Fargate + Private Subnets + NAT Gateway + ALB
- **🔒 Security**: Private subnet isolation, dedicated security groups, least privilege access
- **📚 Documentation**: Complete deployment guide with troubleshooting

**Key Features:**
- Multi-container WordPress + MySQL setup in private subnets
- Enhanced security with no public IP addresses for containers
- NAT Gateway for controlled internet access
- Auto-scaling and health monitoring
- Production security best practices

[**→ View Project**](./wordpress-ecs-amazonq/)

## 🎯 Learning Objectives

These projects are designed to teach:

1. **Modern AWS Architecture Patterns**
   - Containerized applications with ECS Fargate
   - Global content delivery with CloudFront
   - Application security with WAF

2. **Security Best Practices**
   - Defense in depth strategies
   - Network isolation and access control
   - Monitoring and incident response

3. **Infrastructure Automation**
   - AWS CLI deployment scripts
   - Infrastructure as Code principles
   - Automated testing and validation

## 🛠️ Prerequisites

To use these projects, you'll need:

- AWS CLI configured with appropriate permissions
- Basic understanding of AWS services
- Git for cloning repositories

## 📚 Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/schinchli/ArchitectingonAWS.git
   cd ArchitectingonAWS
   ```

2. **Choose a project**
   ```bash
   cd wordpress-ecs-amazonq
   ```

3. **Follow the deployment guide**
   - Each project includes detailed README with step-by-step instructions
   - All configuration files are provided and sanitized
   - Security best practices are documented

## 🔒 Security Notice

All projects in this repository:
- ✅ **No AWS credentials exposed** - All sensitive data sanitized
- ✅ **Production-ready security** - Best practices implemented
- ✅ **Template-based configs** - Easy customization for your environment
- ✅ **Security documentation** - Comprehensive security guides included

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow existing documentation patterns
4. Ensure no sensitive data is committed
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Resources

- [AWS Architecture Center](https://aws.amazon.com/architecture/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-resources/)

---

**Built with ❤️ and AWS best practices**
