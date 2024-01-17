#!/bin/bash
# Usage: ./istio-upgrade.sh -c CONTEXT [ -p -d]
#Shell Script to perform Istio Upgrade from version 1.19.6 to 1.20.2
set -euo pipefail
CONTEXT=""
production=false
TO_ISTIO_VERSION='1.20.2'
namespace=$1
while getopts "c:pdh" opt; do
  case ${opt} in
  c)
    CONTEXT=${OPTARG}
    ;;
  p)
    production=true
    ;;
  d)
    datapath_upgrade=true
    ;;
  h)
    echo "Usage: $0 -c CONTEXT [-p -d -v]"
    exit 0
    ;;
  *)
    echo "Usage: $0 -c CONTEXT [-p -d -v]"
    exit 0
    ;;
  esac
done
#Step 0 Download Istio Binary
echo "Downloading Istio Binary for $TO_ISTIO_VERSION"
if [ -e "istio-${TO_ISTIO_VERSION}/bin/istioctl" ]; then
  echo "Binary Already Present wont download Istio ${TO_ISTIO_VERSION}"
else
curl -s -L https://git.io/getLatestIstio | ISTIO_VERSION=$TO_ISTIO_VERSION sh -
fi
if [ $? -ne 0 ]
then
  echo "** Istioctl download failed **"
  exit 1
fi
CheckStat(){
   if [ $? -eq 0 ]
  then
    echo "** Successful **"
  else
    echo "** Failed to Verify **"
    exit 1
  fi
}
DATAPLANE_UPGRADE(){
TO_ISTIO_VERSION=$1
ISTIOCTL_PATH="istio-${TO_ISTIO_VERSION}/bin"
cluster_istio_version=$("$ISTIOCTL_PATH"/istioctl version --context="$CONTEXT" | grep "control plane version"|cut -d "-" -f1| awk 'NF>1{print $NF}')
if [ "$cluster_istio_version" != "$TO_ISTIO_VERSION" ]
then
  echo "Incorrect version  of Control Plane"
  exit 1
fi

echo " "
echo "==== UPDATING DATAPLANE TO $TO_ISTIO_VERSION ===="
#datapath_upgrade=true
if [ "$datapath_upgrade" = true ]
then
  echo " "


  kubectl --context="$CONTEXT" rollout restart statefulset neo4j -n $namespace
CheckStat

  kubectl wait --for=condition=ready pod --timeout=180s -n $namespace

CheckStat

  kubectl --context="$CONTEXT" rollout restart deployment -n $namespace

CheckStat

  kubectl --context="$CONTEXT" wait --for=condition=available --timeout=180s --all deployments -n $namespace
CheckStat

  ns=namespace
  if [ $? -eq 0 ]
  then
  echo "Namespace to be updated are as 
  ::
  $ns
  "
  else
  echo "No Tenant namespace"
  exit 1
  fi
  for namespaces in $ns
  do
  kubectl --context="$CONTEXT" rollout restart deployment -n  "$namespaces"

 CheckStat

  kubectl --context="$CONTEXT" rollout restart statefulset  -n "$namespaces"
CheckStat
  kubectl --context="$CONTEXT" wait --for=condition=ready pod --timeout=180s -n "$namespaces"
CheckStat

    kubectl --context="$CONTEXT" wait --for=condition=available --timeout=180s --all deployments -n "$namespaces"
CheckStat
  done
  sleep 30
  istio-"${TO_ISTIO_VERSION}"/bin/istioctl proxy-status --context "$CONTEXT"
fi

}


CONTROLPLANE_UPGRADE()
{
TO_ISTIO_VERSION=$1
ISTIOCTL_PATH="istio-${TO_ISTIO_VERSION}/bin"

cluster_istio_version=$("$ISTIOCTL_PATH"/istioctl version --context="$CONTEXT" | grep "control plane version"|cut -d "-" -f1|awk 'NF>1{print $NF}')
FROM_ISTIO_VERSION=$cluster_istio_version

if [[ "$cluster_istio_version" = "$TO_ISTIO_VERSION" ]]
then
  echo "Already Upgraded ISTIO WITH $TO_ISTIO_VERSION VERSION"
else
  echo "Upgrading Istio with $TO_ISTIO_VERSION VERSION"
if [ "$production" = false ]
then
kubectl --context="$CONTEXT" delete -f extra/istio-manifest-no-crd-no-ingress-svc-v"${FROM_ISTIO_VERSION}".yaml
sleep 30
"$ISTIOCTL_PATH"/istioctl  --context="$CONTEXT" install -f istio-operator.yaml --skip-confirmation
else
echo "** Install $TO_ISTIO_VERSION HA control plane"
kubectl --context="$CONTEXT" delete -f extra/istio-manifest-ha-no-crd-no-ingress-svc-v"${FROM_ISTIO_VERSION}".yaml
sleep 30
"$ISTIOCTL_PATH"/istioctl  --context="$CONTEXT" install -f istio-operator-ha.yaml --skip-confirmation
fi
if [ $? -ne 0 ]
then
echo "** Istio upgrade failed **"
exit 1
fi
sleep 30
kubectl --context="$CONTEXT" wait --for=condition=available --timeout=180s --all deployments -n istio-system
CheckStat
if [ "$production" = false ]
then
"$ISTIOCTL_PATH"/istioctl  --context="$CONTEXT" verify-install -f generated-manifests/istio-manifest.yaml
else
"$ISTIOCTL_PATH"/istioctl  --context="$CONTEXT" verify-install -f generated-manifests/istio-manifest-ha.yaml
fi
  if [ $? -ne 0 ]
  then
  echo "** Verifiying Istio upgrade failed **"
  exit 1
  fi
DATAPLANE_UPGRADE "$TO_ISTIO_VERSION"
fi
}

TO_ISTIO_VERSION=1.20.2
ISTIOCTL_PATH="istio-${TO_ISTIO_VERSION}/bin"
cluster_istio_version=$($ISTIOCTL_PATH/istioctl version --context="$CONTEXT" | grep "control plane version"|cut -d "-" -f1| awk 'NF>1{print $NF}')
echo " Cluster is Running $cluster_istio_version Istio Version"
if [ "$cluster_istio_version" = "1.20.2" ]
then
echo "Already Running ISTIO WITH 1.20.2 VERSION"
elif [[ "$cluster_istio_version" == "1.19.6" ]]
then
CONTROLPLANE_UPGRADE 1.20.2
else
echo "No Suitable version to Upgrade"
fi



