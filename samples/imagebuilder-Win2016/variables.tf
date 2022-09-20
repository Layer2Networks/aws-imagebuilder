

variable "bastion_hosts_distribution_account_ids" {
  description = "bastion user account"
  default = "arn:aws:iam::1234567890:user/user"
  type        = string
}

variable "windows_version" {
  description = "type Windows version to deploy"
  type        = string
}