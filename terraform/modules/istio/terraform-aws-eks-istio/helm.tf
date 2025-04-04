          
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
