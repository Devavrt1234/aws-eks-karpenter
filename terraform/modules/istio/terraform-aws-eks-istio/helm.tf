          
data "external" "namespace_check" {
  program = ["bash", "-c", <<EOT
  if kubectl get namespace ${var.namespace} > /dev/null 2>&1; then
    echo '{"exists": "true"}'
  else
    echo '{"exists": "false"}'
  fi
  EOT
  ]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_groups = {
    karpenter = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5.large"]

      min_size     = 2
      max_size     = 10
      desired_size = 2

      taints = {
        # This Taint aims to keep just EKS Addons and Karpenter running on this MNG
        # The pods that do not tolerate this taint should run on nodes created by Karpenter
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  intra_subnets   = ["10.0.104.0/24", "10.0.105.0/24", "10.0.106.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = var.cluster_name
  }
}

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}


resource "kubernetes_namespace" "istio" {
  count = data.external.namespace_check.result["exists"] == "false" ? 1 : 0

   metadata {
    name = var.namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

output "namespace_message" {
  value = data.external.namespace_check.result["exists"] == "true" ?  "Namespace ${var.namespace} already exists, skipping creation.":"Namespace ${var.namespace} doe>
}

resource "helm_release" "istio_base" {
  depends_on = [kubernetes_namespace.istio]
  count      = var.enabled && var.base_enabled ? 1 : 0
  name       = "istio-base"
  repository = var.helm_chart_repo
  chart      = "base"
  version    = var.helm_chart_version
  namespace  = var.namespace

  values = [
    yamlencode(var.base_settings)
  ]

}

resource "helm_release" "istiod" {
  depends_on = [
    helm_release.istio_base
  ]
  count      = var.enabled && var.istiod_enabled ? 1 : 0
  name       = "istio-istiod"
  repository = var.helm_chart_repo
  chart      = "istiod"
  version    = var.helm_chart_version
  namespace  = var.namespace

  values = [
    yamlencode(merge(
      var.istiod_settings,
      {
        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
          }
        ]
      }
    ))
  ]

   timeout = 600 # Increase timeout to 10 minutes

}

resource "helm_release" "istio_ingressgateway" {
  depends_on = [
    helm_release.istiod
  ]
  count      = var.enabled && var.ingressgateway_enabled ? length(var.ingressgateway_settings) : 0
  name       = var.ingressgateway_settings[count.index].name
  repository = var.helm_chart_repo
  chart      = "gateway"
  version    = var.helm_chart_version
  namespace  = var.namespace

  set {
    name  = "securityContext.runAsUser"
    value = 1337
  }

  set {
    name  = "securityContext.runAsGroup"
    value = 1337
  }

  set {
    name  = "securityContext.runAsNonRoot"
    value = true
  }
}
