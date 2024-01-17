#!/bin/bash
#Shell Script to perform Istio Downgrade to version 1.20.2
set -euo pipefail
production=false
datapath_rollback=false
TO_ISTIO_VERSION=1.20.2
namespace=$1
while getopts ":c:pdh" opt; do
  case ${opt} in
  c)
    CONTEXT=${OPTARG}
    ;;
  p)
    production=true
    ;;
  d)
    datapath_rollback=true
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
echo "Downloading Istio Binary for $TO_ISTIO_VERSION"
if [ -e "istio-${TO_ISTIO_VERSION}/bin/istioctl" ]; then
  echo "Binary Already Present wont download Istio ${TO_ISTIO_VERSION}"
else
curl -s -L https://git.io/getLatestIstio | ISTIO_VERSION=$TO_ISTIO_VERSION sh -

if [ $? -ne 0 ]
then
  echo "**Istioctl download/install failed"
  exit 1
fi
fi
DATAPLANE_ROLLBACK(){
TO_ISTIO_VERSION=$1
echo " "
echo "==== UPDATING DATAPLANE TO $TO_ISTIO_VERSION ===="

if [ "$datapath_rollback" = true ]
then
  kubectl --context="$CONTEXT" rollout restart statefulset -n $namespace
  if [ $? -eq 0 ]
  then
    echo "**Rolledout pods/statefullset sts in $namespace Namespace"
  else
    echo "**Failed for rolling  pods/statefullset sts in $namespace Namespace"
    exit 1
  fi
  kubectl --context="$CONTEXT" rollout restart deployment -n $namespace
  if [ $? -eq 0 ]
  then
    echo "**Rolledout deployment in $namespace Namespace"
  else
    echo "**Failed for rolling  deployment in $namespace Namespace"
    exit 1
  fi

  kubectl --context="$CONTEXT" wait --for=condition=available --timeout=180s --all deployments -n $namespace
  if [ $? -eq 0 ]
  then
    echo "** Pods are ready for $namespace namespace"
  else
    echo "**Timed Out for waiting for  pods in $namespace namespace"
    exit 1
  fi


  kubectl --context="$CONTEXT"  wait --for=condition=ready pod --timeout=180s -n $namespace

  if [ $? -eq 0 ]
  then
    echo "**Rolledout pods to rollover istio proxies for  $namespace namespace"
  else
    echo "**Failed for rolling out pods to rollover istio proxies for  $namespace namespace"
    exit 1
  fi

  ns=namespace
  for namespace in $ns
  do
  kubectl --context="$CONTEXT" rollout restart deployment -n  "$namespace"
    if [ $? -eq 0 ]
  then
    echo "**Rolledout pods to rollover istio proxies for $namespace Namespace "
  else
    echo "**Failed for rolling out pods to rollover istio proxies for $namespace Namespace"
    exit 1
  fi
  kubectl --context="$CONTEXT" rollout restart statefulset  -n "$namespace"

  if [ $? -eq 0 ]
  then
    echo "**Rolledout istio proxies pods for $namespace"
  else
    echo "**Failed for rolling out pods to rollover istio proxies for $namespace Namespace"
    exit 1
  fi

  kubectl --context="$CONTEXT" wait --for=condition=available --timeout=180s --all deployments -n "$namespace"
  
     if [ $? -eq 0 ]
  then
    echo "** Pods are Ready  for $namespace after rollover"
  else
    echo "**Timed Out waiting for Pods  for $namespace"
    exit 1
  fi
  kubectl --context="$CONTEXT" wait  --for=condition=ready pod --timeout=180s -n "$namespace"
  kubectl --context="$CONTEXT" wait  --for=condition=ready pod --timeout=180s -n "$namespace"
     if [ $? -eq 0 ]
  then
    echo "**All Pods is in ready State after rollover $namespace Namespace **"
  else
    echo "**All Pods is in  not ready State after rollover $namespace  Namespace **"
    exit 1
  fi

  done
  sleep 30

  istio-"$TO_ISTIO_VERSION"/bin/istioctl proxy-status --context "$CONTEXT"
fi
}
ISTIOCTL_PATH="istio-$TO_ISTIO_VERSION/bin"
cluster_istio_version=$("$ISTIOCTL_PATH"/istioctl version --context="$CONTEXT" | grep "control plane version"|cut -d "-" -f1| awk 'NF>1{print $NF}')
FROM_ISTIO_VERSION=$cluster_istio_version
  if [ "$TO_ISTIO_VERSION" == "1.20.2" ] && [ "$FROM_ISTIO_VERSION" == "1.20.2" ]
  then
    echo " Initiated Rollback to $TO_ISTIO_VERSION from  $cluster_istio_version"
    if [ $production == false ]
    then
      echo "** Rollback with $TO_ISTIO_VERSION **"
      ISTIOCTL_PATH="istio-1.20.2/bin"
      kubectl --context="$CONTEXT" delete -f extra/istio-manifest-no-crd-no-ingress-svc-v1.20.2.yaml
      sleep 30
      $ISTIOCTL_PATH/istioctl  --context="$CONTEXT" install -f extra/istio-operator-1.20.2.yaml --skip-confirmation
      sleep 30
      DATAPLANE_ROLLBACK "$TO_ISTIO_VERSION"
    else
      echo "** Rollback 1.20.2 HA control plane **"
      ISTIOCTL_PATH="istio-1.20.2/bin"
      kubectl --context="$CONTEXT" delete -f extra/istio-manifest-ha-no-crd-no-ingress-svc-v1.20.2.yaml
      sleep 30
      $ISTIOCTL_PATH/istioctl  --context="$CONTEXT" install -f extra/istio-operator-ha-1.20.2.yaml --skip-confirmation
      sleep 30
      DATAPLANE_ROLLBACK "$TO_ISTIO_VERSION"
    fi
  else
    echo "Please Choose Correct Version for Rollback Istio"
  fi