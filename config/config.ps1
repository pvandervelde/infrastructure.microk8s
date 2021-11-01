[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------ Functions -------------------------------------

function Get-LoadBalancerIPRanges
{
    [CmdletBinding()]
    param()

    $multipassVmInfo = & multipass list --format json | ConvertFrom-Json

    $microk8sVmInfo = $multipassVmInfo.list | Where-Object { $_.name -eq 'microk8s-vm' }
    $nodeIPAddresses = $microk8sVmInfo.ipv4

    # Grab the internal IP address which starts with 172.x.y.z
    $nodeIPAddress = $nodeIPAddresses | Where-Object { $_.StartsWith('172') }

    $octets = $nodeIPAddress -split "\."
    $octets[3] = '240'

    $internalRange = ($octets -join ".")  + '/28'

    # Grab the 'external' IP address which stars with 192.168.x.y
    $nodeIPAddress = $nodeIPAddresses | Where-Object { $_.StartsWith('192.168') }

    $octets = $nodeIPAddress -split "\."
    $octets[3] = '240'

    $externalRange = ($octets -join ".")  + '/28'


    return @($internalRange, $externalRange)
}

function Install-Dashboard
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Install dashboard ..."
    & kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.2.0/aio/deploy/recommended.yaml

    # Connect to the dashboard via ingress
    # Write-Output "Add an ingress for the k8s dashboard ..."
    # & kubectl apply -f ./dashboard/ingress.yaml

    Write-Output "Add a load balancer for the k8s dashboard ..."
    & kubectl apply -f ./dashboard/loadbalancer.yaml

    Write-Output "Assign admin rights to the dashboard user ..."
    & kubectl apply -f ./dashboard/dashboard-admin.yaml

    Write-Output "Store dashboard token ..."
    $dashboardSecret = & kubectl -n kubernetes-dashboard get secret |
        Select-String dashboard-admin |
        ForEach-Object { $_ -Split '\s+' } |
        Select-Object -First 1
    $dashboardToken = & kubectl -n kubernetes-dashboard describe secret $dashboardSecret

    Write-Output $dashboardToken
}

function Install-Ingress
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Install Traefik ..."
    & kubectl apply -f ./traefik/custom-resource.yaml
    & kubectl apply -k ./traefik/base

    # link longhorn to Traefik (see: https://forums.rancher.com/t/longhorn-ui-with-traefik/16742/2)
    # Write-Output "Attach Longhorn to Traefik ..."
    # & kubectl delete service longhorn-frontend -n longhorn-system
    # & kubectl apply -f ./longhorn/longhorn-service.yaml
    # & kubectl apply -f ./longhorn/longhorn-ingress.yaml
}

function Install-Loadbalancer
{
    [CmdletBinding()]
    param(
        [string] $tempDir
    )

    $metallbVersion = '0.9.5'

    Set-LogSection

    # metallb
    Write-Output "Set the MetalLB namespace ..."
    kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/v$metallbVersion/manifests/namespace.yaml"

    Write-Output "Set the MetalLB items ..."
    kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/v$metallbVersion/manifests/metallb.yaml"

    # On first install only
    $createMetallbSecret = $false
    try
    {
        $output = & kubectl get secret --namespace metallb-system --output json | ConvertFrom-Json
        $memberList = $output.items | Where-Object { $_.metadata.name -eq 'memberlist' }
        $createMetallbSecret = ($null -eq $memberList)

        Write-Output "Not setting the MetalLB memberlist secret. It already exists."
    }
    catch
    {
        # The secret does not exist
        $createMetallbSecret = $true
    }

    if ($createMetallbSecret)
    {
        Write-Output "Setting the MetalLB memberlist secret ..."
        kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
    }

    $ipRanges = Get-LoadBalancerIPRanges


    $configPath = Join-Path $tempDir 'config.yaml'
@"
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: cluster-pool
      protocol: layer2
      addresses:
      - $($ipRanges[0])
      - $($ipRanges[1])
"@ | Out-File -FilePath $configPath

    Write-Output "Setting the MetalLB IP range to $($ipRanges[0]) and $($ipRanges[1]) ..."
    kubectl apply -f $configPath
}

function Set-Authentication
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Enable RBAC ..."
    & microk8s enable rbac
}

function Set-Dns
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Enable CoreDNS ..."
    & microk8s enable dns
}

function Set-KubeConfig
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Updating ~/.kube/config to have the microk8s config ..."
    & microk8s config > ~/.kube/config
}

function Set-LogSection
{
    [CmdletBinding()]
    param()

    Write-Output ""
    Write-Output "--"
    Write-Output ""

}

function Set-Storage
{
    [CmdletBinding()]
    param()

    Set-LogSection

    Write-Output "Install Longhorn..."
    & kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.1.0/deploy/longhorn.yaml

    # Set the replica count for Longhorn to 1 because we only have one node
    & kubectl delete storageclass longhorn
    & kubectl apply -f ./longhorn/configmap-storageclass.yaml

    #& kubectl delete service longhorn-frontend -n longhorn-system
    #& kubectl apply -f ./longhorn/service.yaml
    & kubectl apply -f ./longhorn/ingress.yaml
}

function Set-TempDir
{
    [CmdletBinding()]
    param()

    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'tmp'
    if (-not (Test-Path $path))
    {
        New-Item -Path $path -ItemType Directory | Out-Null
    }

    return $path
}

# ------------------------------ Functions -------------------------------------

# Verify that microk8s is installed
$command = Get-Command microk8s -ErrorAction SilentlyContinue
if ($null -eq $command)
{
    throw "MicroK8s is not on the PATH. Please add MicroK8s to the PATH before continueing."
}

$tempDir = Set-TempDir

# Make sure the normal kubectl has the same config as microk8s config
Set-KubeConfig

# enable features
Write-Output "Enabling features ..."

Set-Authentication

Set-Dns

Install-Loadbalancer -tempDir $tempDir

Set-Storage

# registry
# Write-Output "Enable registry ..."
# & microk8s enable registry

Install-Ingress

Install-Dashboard



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
