

variable "bastion_hosts_distribution_account_ids" {
  description = "bastion user account"
  default = "arn:aws:iam::187773437170:user/epitty"
  type        = string
}

variable "windows_version" {
  description = "type Windows version to deploy"
  type        = string
}