variable "database_name" {}
variable "database_password" {}
variable "database_user" {}
variable "region" {}
variable "shared_credentials_file" {}
variable "ami" {}
variable "AZ1" {}
variable "AZ2" {}
variable "AZ3" {}
variable "AZ4" {}
variable "instance_type" {}
variable "instance_class" {}
variable "USER" {}
variable "PUBLIC_KEY_PATH" {}
variable "PRIV_KEY_PATH" {}
variable "COUNT" {}
variable "custom_vpc" {
  description = "VPC for testing environment"
  type        = string
  default     = "10.0.0.0/16"
}