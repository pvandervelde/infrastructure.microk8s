[CmdletBinding()]
param()

# Make sure the normal kubectl has the same config as microk8s config
Write-Output "Updating .kube/config to have the microk8s config ..."
& microk8s config > ~/.kube/config

# enable features
Write-Output "Enabling features ..."
Write-Output "Enable RBAC ..."
& microk8s enable rbac

Write-Output "Enable CoreDNS ..."
& microk8s enable dns

Write-Output "Enable dashboard ..."
& microk8s enable dashboard

Write-Output "Store dashboard token ..."
& kubectl apply -f ./dashboard/create-user.yaml
& kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | sls admin-user | ForEach-Object { $_ -Split '\s+' } | Select -First 1)

Write-Output "Enable Helm3 ..."
& microk8s enable helm3

# storage
Write-Output "Enable storage ..."
& microk8s enable storage

# registry
Write-Output "Enable registry ..."
& microk8s enable registry

# metallb
Write-Output "Enable metallb on range 172.17.35.0/24 ..."
& microk8s enable metallb 172.17.35.0/24

# Add Traefik
Write-Output "Install Traefik using Helm 3..."
& helm repo add traefik https://helm.traefik.io/traefik
& helm repo update

# It looks like 9.12.1 introduced an issue that results in the following error message
#   Error: failed to install CRD crds/ingressroute.yaml: CustomResourceDefinition.apiextensions.k8s.io
#     "ingressroutes.traefik.containo.us" is invalid: [spec.versions: Invalid value:
#     []apiextensions.CustomResourceDefinitionVersion(nil): must have exactly one version marked as
#     storage version, status.storedVersions: Invalid value: []string(nil): must have at least one
#     stored version]
& helm install `
  -f ./traefik/config.yaml `
  traefik `
  traefik/traefik `
  --version 9.12.0 `
  --set service.type=NodePort

# Connect to the dashboard via ingress
Write-Output "Add an ingress for the k8s dashboard ..."
& kubectl apply -f ./dashboard/ingress.yaml

# Add longhorn for storage
# Write-Output "Install Longhorn using Helm 3..."
# & helm repo add longhorn https://charts.longhorn.ios
# & helm repo update
# & kubectl create namespace longhorn-system
# & helm install longhorn longhorn/longhorn --namespace longhorn-system

# link longhorn to Traefik (see: https://forums.rancher.com/t/longhorn-ui-with-traefik/16742/2)
# Write-Output "Attach Longhorn to Traefik ..."
# & kubectl delete service longhorn-frontend -n longhorn-system
# & kubectl apply -f ./longhorn/longhorn-service.yaml
# & kubectl apply -f ./longhorn/longhorn-ingress.yaml

# Add harbor
# Write-Output "Install Harbor using Helm 3"
# & helm repo add harbor https://helm.goharbor.io

# Add prometheus
# Write-Output "Enable Prometheus ..."
# & microk8s enable prometheus

# Add (LOGGING)
# Write-Output "Enable Elasticsearch and FluentD ..."
# & microk8s enable fluentd

# Add Jaeger
# Write-Output "Enable Jaeger ..."
# & microk8s enable jaeger
