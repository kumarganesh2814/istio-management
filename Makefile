.PHONY: istio

istio:
	@curl -f -s -L https://git.io/getLatestIstio | ISTIO_VERSION=$(ISTIO_VERSION) sh -
	@mkdir -p generated-manifests
	@$(PWD)/istio-$(ISTIO_VERSION)/bin/istioctl manifest generate -f istio-operator.yaml > generated-manifests/istio-manifest.yaml
	@$(PWD)/istio-$(ISTIO_VERSION)/bin/istioctl manifest generate -f istio-operator-ha.yaml > generated-manifests/istio-manifest-ha.yaml