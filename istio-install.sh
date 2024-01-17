#!/usr/bin/env bash
#Shell Script to perform Istio Install  

set -euo pipefail

production=false
ISTIO_VERSION=1.20.2
while getopts "c:phd" opt; do
  case ${opt} in
  c)
    CONTEXT=${OPTARG}
    ;;
  p)
    production=true
    ;;
  h)
    echo "Usage: $0 -c CONTEXT [-p -d]"
    exit 0
    ;;
  *)
    echo "Usage: $0 -c CONTEXT [-p -d -v]"
    exit 0
    ;;
  esac
done
#STEP 0  - Download 1.20.2 istio and install istioctl
binary=1.20.2
ISTIOCTL_PATH="istio-${binary}/bin"
echo "Downloading Istio Binary for $binary"
if [ -e "istio-${binary}/bin/istioctl" ]; then
  echo "Binary Already Present wont download Istio ${binary}"
else
  curl --fail -s -L https://git.io/getLatestIstio | ISTIO_VERSION=$binary sh -

  if [ $? -ne 0 ]; then
    echo "**Istioctl download failed"
    exit 1
  fi
fi

#STEP 1: Installing istio 1.20.2

echo "==== INSTALLING ISTIO $ISTIO_VERSION ===="

if [ "$production" = false ]; then
  $ISTIOCTL_PATH/istioctl --context="$CONTEXT" install -f istio-operator.yaml --skip-confirmation
else
  echo "** Install HA control plane - $ISTIO_VERSION"
  $ISTIOCTL_PATH/istioctl --context="$CONTEXT" install -f istio-operator-ha.yaml --skip-confirmation
fi

sleep 60

#STEP 2: Validate installation

echo "==== VALIDATING ISTIO INSTALLATION ===="

echo " "
kubectl --context="$CONTEXT" wait --for=condition=available --timeout=300s --all deployments -n istio-system
if [ $? -eq 0 ]; then
  echo "**All istio deployments are running"
else
  echo "**One or more istio deployments not ready"
  exit 1
fi

echo " "
if [ "$production" = false ]; then
  $ISTIOCTL_PATH/istioctl --context="$CONTEXT" verify-install -f generated-manifests/istio-manifest.yaml
else
  echo "** Check if HA control plane is installed - $ISTIO_VERSION"
  $ISTIOCTL_PATH/istioctl --context="$CONTEXT" verify-install -f generated-manifests/istio-manifest-ha.yaml
fi

if [ $? -eq 0 ]; then
  echo "** Istio $ISTIO_VERSION installation successful"
else
  echo "** Istio $ISTIO_VERSION installation failed"
  exit 1
fi
