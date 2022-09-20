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
# Windows Imagebuilder
###################################################
resource "aws_key_pair" "windows" {
  key_name   = "windows-${var.windows_version}-key"
  public_key = "ssh-rsa localhost keyxxxxxxxxxxxxreplace with you public key here to create key pair"
}

# Get latest Windows Server 2019 AMI
data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base*"]
  }
}

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

resource "aws_imagebuilder_distribution_configuration" "windows" {
  name        = "Windows-${var.windows_version}-host-distribution"
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
    }
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "windows" {
  name                  = "windows-${var.windows_version}"
  description           = "Windows${var.windows_version}"
  instance_profile_name = aws_iam_instance_profile.windows.name
  instance_types        = ["t3a.small"]
  key_pair              = aws_key_pair.windows.key_name

  terminate_instance_on_failure = true
}

resource "aws_imagebuilder_component" "mysql_workbench" {
  name        = "mysql-workbench_forWin${var.windows_version}"
  description = "Install MySQL Workbench"
  platform    = "Windows"
  version     = "1.0.0"
  data = yamlencode({
    phases = [{
      name = "build"
      steps = [{
        name   = "InstallMySQLWorkbench"
        action = "ExecutePowerShell"
        inputs = {
          commands = ["C:\\ProgramData\\chocolatey\\bin\\choco.exe install mysql.workbench -y"]
        }

        onFailure = "Abort"
      }]
    }]
    schemaVersion = 1.0
  })
}

resource "aws_imagebuilder_image_recipe" "windows" {
  name         = "Windows${var.windows_version}"
  description  = "Windows${var.windows_version} machine with MySQL Workbench, SSMS, pgadmin and Google Chrome installed"
  version      = "1.0.0"
  parent_image = data.aws_ami.windows_2019.id

  component {
    component_arn = "arn:aws:imagebuilder:us-east-1:aws:component/aws-cli-version-2-windows/1.0.0/1"
  }
  component {
    component_arn = "arn:aws:imagebuilder:us-east-1:aws:component/chocolatey/1.0.0/1"
  }
  component {
    component_arn = aws_imagebuilder_component.mysql_workbench.arn
  }
}

resource "aws_imagebuilder_image_pipeline" "windows" {
  name                             = "windows-${var.windows_version}-ami-pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.windows.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.windows.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.windows.arn

  schedule {
    schedule_expression = "cron(0 0 1 * ? *)" # At midnight on the 1st of each month
  }
}