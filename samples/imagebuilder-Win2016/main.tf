# ----------------------------------------------------------------------------------------------------
# Terraform Backend  - required
# 
# ----------------------------------------------------------------------------------------------------
# required
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}


# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

###################################################
# dynamic data inputs
###################################################
# Get latest Windows Server 2016 AMI
data "aws_ami" "windows_2016" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2016-English-Full-Base*"]
  }
}

#######----------------------------------------------------
#resources
#
######### Security Group
#
resource "aws_security_group" "this" {
  name        = "Security Group to Deploy Image"
  description = "Allow  443 port"
  vpc_id      = var.vpc_id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ImageBuilder for windows-${var.windows_version} SecurityGroup"
  }
}

######### Instance Profile
#
resource "aws_iam_instance_profile" "windows" {
  name = "windows-${var.windows_version}"
  role = aws_iam_role.windows.name
}

resource "aws_iam_role" "windows" {
  name = "windows-${var.windows_version}-role"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
  ]
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}
######### AWS ImageBuilder

# Image Builder Distribution
resource "aws_imagebuilder_distribution_configuration" "windows" {
  name        = "Windows-${var.windows_version}-distribution"
  description = "Windows host image distribution"

  distribution {
    region = "us-east-1"
    ami_distribution_configuration {
      name     = "Windows${var.windows_version}-{{ imagebuilder:buildDate }}"
      ami_tags = {
        CostCenter = "IT"
        Owner = "Someone"
      }

      launch_permission {
        #user_ids = var.bastion_hosts_distribution_account_ids # an array of account IDs
      }
      #target_account_ids = ["123456789002", "123456789003"]
      #}
      #region = region.value
    }
  }
}

# Image Builder Infrastructure Configuration
resource "aws_imagebuilder_infrastructure_configuration" "windows" {
  name                  = "windows-${var.windows_version}-infrastructure"
  description           = "Windows${var.windows_version}"
  instance_profile_name = aws_iam_instance_profile.windows.name
  instance_types        = ["t2.nano", "t3.micro"]
  key_pair              = var.key-pair
  security_group_ids    = [aws_security_group.this.id]
  #sns_topic_arn         = aws_sns_topic.example.arn
  subnet_id             = var.subnetid
  terminate_instance_on_failure = true

  #logging {
  #  s3_logs {
  #    s3_bucket_name = aws_s3_bucket.example.bucket
  #    s3_key_prefix  = "logs"
  #  }
  #}

  tags = {
    Name = "ImageBuilder for windows-${var.windows_version} Infrastructure Configuration"
  }
}

# Image Builder Components
resource "aws_imagebuilder_component" "WindowsFeatures" {
  name        = "windows-webserver-ndetframework-webmgmt-windows${var.windows_version}"
  description = "Run Windows2016 with IIS .NET and Web Management Tools"
  platform    = "Windows"
  version     = "1.0.0"
  data = yamlencode({
    phases = [{
      name = "build"
      steps = [{
        name   = "WindowsDefenderATP"
        action = "ExecutePowerShell"
        inputs = {
          commands = [
          "Install-WindowsFeature -Name Web-Server,NET-Framework-45-ASPNET,Web-Asp-Net45,Web-Net-Ext45,Web-Mgmt-Tools"  
          ]
        }

        onFailure = "Abort"
      }]
    }]
    schemaVersion = 1.0
  })
}

# Image Builder Recipe
resource "aws_imagebuilder_image_recipe" "windows" {
  name         = "Windows${var.windows_version}-recipe"
  description  = "Windows${var.windows_version} machine with Web-Server,NET-Framework-45-ASPNET,Web-Asp-Net45,Web-Net-Ext45,Web-Mgmt-Tools, AWS-cli"
  version      = "1.0.0"
  parent_image = data.aws_ami.windows_2016.id

  component {
    component_arn = "arn:aws:imagebuilder:us-east-1:aws:component/aws-cli-version-2-windows/1.0.0/1"
  }
  component {
    component_arn = aws_imagebuilder_component.WindowsFeatures.arn
  }
}

# Image Builder Pipeline
resource "aws_imagebuilder_image_pipeline" "windows" {
  name                             = "windows-${var.windows_version}-ami-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.windows.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.windows.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.windows.arn
  status                           = "ENABLED"
  description                      = "Creates a Windows${var.windows_version} AMI"
  schedule {
    schedule_expression = "cron(0 0 1 * ? *)" # At midnight on the 1st of each month
  }
# Test the image after build
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }

  tags = {
    "Name" = "windows-${var.windows_version}-ami-pipeline"
  }
}  
######### end
#