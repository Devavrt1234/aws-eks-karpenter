#terraform {
# required_version = ">= 0.13"
#
#  required_providers {
#    aws        = ">= 5.61.0"
#    helm       = ">= 1.0, < 3.0"
#    kubernetes = ">= 1.10.0, < 3.0.0"
#  }
#}


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 1.0, < 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 1.10.0, < 3.0.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14, < 2.0"
    }
  }
}
