# Makefile — Kind-based integration environment for the kcp MCP stack:
# contrib-access-virtual-workspace + contrib-mcp-virtual-workspace behind
# kcp's front-proxy.
#
# Usage:
#   make setup-infra     # one-time: kind + metallb + cert-manager + keycloak + kcp
#   tilt up              # dev loop: builds & deploys both VWs, redeploys on change
#   make seed            # per-user workspaces, APIBinding, RBAC (after first tilt up)
#   make scar USER=alice # test SCAR through the front-proxy
#   make mcp-smoke       # test MCP through the front-proxy
#   make teardown        # delete Kind cluster
#
# Prerequisites: kind, kubectl (+ ws plugin), helm, tilt, jq, curl, docker, mkcert
#
# Host requirements (once): /etc/hosts entries
#   127.0.0.1  keycloak.kcp.example root.kcp.example

SHELL := /bin/bash
.DEFAULT_GOAL := help
CLUSTER_NAME     ?= mcp-integration
KIND_KUBECONFIG  ?= $(HOME)/.kube/config
SCRIPT_DIR       := $(shell pwd)

ACCESS_VW_REPO ?= ../contrib-access-virtual-workspace
MCP_VW_REPO    ?= ../contrib-mcp-virtual-workspace


CERT_MANAGER_VERSION ?= v1.20.2
METALLB_VERSION      ?= v0.15.3

KCP_NS      := kcp-system
KEYCLOAK_NS := keycloak
USER ?= alice
SCAR_GROUP := access.contrib.kcp.io
KC := kubectl --kubeconfig $(KIND_KUBECONFIG) --context kind-$(CLUSTER_NAME)

# ── Helpers ──────────────────────────────────────────────────────────────────

define wait-for-deployment
	@echo "==> Waiting for deployment $(2) in $(1)..."
	@$(KC) rollout status deployment/$(2) -n $(1) --timeout=$(or $(3),300s)
endef

define wait-for-crd
	@echo "==> Waiting for CRD $(1)..."
	@for i in $$(seq 1 60); do $(KC) get crd $(1) &>/dev/null && break || sleep 2; done
endef

info  = @echo "==> $(1)"

.PHONY: help
help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Cluster lifecycle ────────────────────────────────────────────────────────

.PHONY: kind-create
kind-create: ## Create Kind cluster
	$(call info,Creating Kind cluster '$(CLUSTER_NAME)')
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "⚠️  Cluster '$(CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml; \
	fi

.PHONY: teardown
teardown: ## Delete Kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

# ── DNS inside the cluster ───────────────────────────────────────────────────
# Pods (VWs, kcp, front-proxy) resolve the demo hostnames to the in-cluster
# Services via a CoreDNS rewrite, so no per-Deployment hostAliases patches are
# needed and Tilt can redeploy freely.

.PHONY: coredns-rewrite
coredns-rewrite: ## Apply Corefile with root.kcp.example / keycloak.kcp.example rewrites
	$(call info,Applying CoreDNS config with demo hostname rewrites)
	@$(KC) apply -f manifests/coredns/coredns-configmap.yaml
	@$(KC) rollout restart deployment/coredns -n kube-system
	@$(KC) rollout status deployment/coredns -n kube-system --timeout=60s

.PHONY: install-metallb
install-metallb: ## Install MetalLB for LoadBalancer IPs
	$(call info,Installing MetalLB $(METALLB_VERSION))
	@$(KC) apply -f "https://raw.githubusercontent.com/metallb/metallb/$(METALLB_VERSION)/config/manifests/metallb-native.yaml"
	$(call wait-for-deployment,metallb-system,controller,120s)
	@$(KC) get secret -n metallb-system memberlist --no-headers --ignore-not-found -o name | \
		grep -q . || $(KC) create secret generic -n metallb-system memberlist \
		--from-literal=secretkey="$$(openssl rand -base64 128)"
	@echo "==> Waiting for MetalLB webhooks..."
	@sleep 5
	@for i in 1 2 3 4 5; do \
		$(KC) apply -k manifests/metallb 2>/dev/null && break; \
		echo "==> MetalLB webhook not ready, retrying ($$i/5)..."; sleep 5; \
	done

.PHONY: install-cert-manager
install-cert-manager: ## Install cert-manager
	$(call info,Installing cert-manager $(CERT_MANAGER_VERSION))
	@$(KC) apply -f "https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml"
	@$(KC) wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
	@$(KC) wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s
	@echo "==> Waiting for cert-manager webhook..."
	@sleep 10

.PHONY: install-keycloak
install-keycloak: ## Install Keycloak (helm + TLS + configure realm)
	$(call info,Creating Keycloak TLS certificate via mkcert)
	@scripts/create-keycloak-certs.sh
	$(call info,Installing Keycloak via Helm)
	@helm repo add codecentric https://codecentric.github.io/helm-charts 2>/dev/null || true
	@helm repo update codecentric
	@helm upgrade --install keycloak codecentric/keycloakx \
		--namespace $(KEYCLOAK_NS) \
		-f helm/keycloak-values.yaml \
		--wait --timeout 300s
	$(call info,Configuring Keycloak OIDC clients and users)
	@scripts/configure-keycloak.sh

.PHONY: install-kcp
install-kcp: ## Install kcp-operator + etcd + RootShard + FrontProxy
	$(call info,Deploying kcp-operator)
	@$(KC) create namespace $(KCP_NS) --dry-run=client -o yaml | $(KC) apply -f -
	@$(KC) apply -k manifests/kcp-operator
	$(call wait-for-deployment,kcp-operator-system,kcp-operator-controller-manager,120s)
	$(call wait-for-crd,rootshards.operator.kcp.io)
	$(call wait-for-crd,frontproxies.operator.kcp.io)
	$(call info,Applying kcp manifests)
	@$(KC) apply -k manifests/kcp
	$(call wait-for-deployment,$(KCP_NS),etcd,120s)
	$(call info,Waiting for RootShard)
	@$(KC) wait --for=condition=Available rootshard/root -n $(KCP_NS) --timeout=300s
	$(call info,Waiting for FrontProxy)
	@$(KC) wait --for=condition=Available frontproxy/frontproxy -n $(KCP_NS) --timeout=300s
	$(call wait-for-deployment,$(KCP_NS),root-kcp,120s)
	# Restart kcp components to pick up OIDC discovery (Keycloak must be up,
	# CoreDNS rewrites must be in place)
	$(call info,Restarting kcp for OIDC discovery)
	@$(KC) rollout restart deployment/root-kcp -n $(KCP_NS)
	@$(KC) rollout restart deployment/frontproxy-front-proxy -n $(KCP_NS)
	$(call wait-for-deployment,$(KCP_NS),root-kcp,120s)
	$(call wait-for-deployment,$(KCP_NS),frontproxy-front-proxy,120s)
	# Extract admin kubeconfig for host-side use (seed, kubectl ws)
	$(call info,Extracting admin kubeconfig)
	@$(KC) wait --for=jsonpath='{.status.phase}'=Ready kubeconfig/kcp-admin-kubeconfig \
		-n $(KCP_NS) --timeout=120s
	@$(KC) get secret kcp-admin-kubeconfig -n $(KCP_NS) \
		-o jsonpath='{.data.kubeconfig}' | base64 -d > admin.kubeconfig
	@sed -i.bak 's|https://root-kcp.kcp-system.svc.cluster.local:6443|https://root.kcp.example:6443|g' admin.kubeconfig
	@rm -f admin.kubeconfig.bak
	@KUBECONFIG=admin.kubeconfig kubectl config set-cluster base --insecure-skip-tls-verify=true 2>/dev/null || true
	@KUBECONFIG=admin.kubeconfig kubectl config set-cluster default --insecure-skip-tls-verify=true 2>/dev/null || true
	$(call info,Admin kubeconfig saved to $(SCRIPT_DIR)/admin.kubeconfig)

.PHONY: setup-infra
setup-infra: ## One-time infra: kind + coredns + metallb + cert-manager + keycloak + kcp
	@$(MAKE) kind-create
	@$(MAKE) coredns-rewrite
	@$(MAKE) install-metallb
	@$(MAKE) install-cert-manager
	@$(MAKE) install-keycloak
	@$(MAKE) install-kcp
	$(call info,Infra ready — run 'tilt up' to build and deploy the VWs)

.PHONY: seed
seed: ## Create per-user workspaces, APIBinding, RBAC, mcp-vw impersonation rights
	$(call info,Seeding user workspaces and RBAC)
	@export KUBECONFIG=$(SCRIPT_DIR)/admin.kubeconfig; \
	kubectl ws use ':root'; \
	for user in alice bob; do \
		ws="$${user}-workspace"; \
		kubectl ws create "$${ws}" --type universal --enter 2>/dev/null || kubectl ws use "root:$${ws}"; \
		kubectl apply -f manifests/seed/apibinding-consumer.yaml; \
		kubectl apply -f manifests/seed/seed-rbac-$${user}.yaml; \
		kubectl apply -f manifests/seed/mcp-impersonator.yaml; \
		kubectl ws use ':root'; \
	done
	$(call info,Seed complete)

.PHONY: get-token
get-token: ## Print an OIDC token for USER (default: alice)
	@scripts/get-oidc-token.sh $(USER)

.PHONY: scar
scar: ## Test SCAR through the front-proxy for USER (default: alice)
	@TOKEN=$$(scripts/get-oidc-token.sh $(USER)); \
	if [ -z "$$TOKEN" ]; then echo "❌ could not get OIDC token for $(USER)"; exit 1; fi; \
	echo "==> SCAR as $(USER):"; \
	curl -sk -X POST -H "Authorization: Bearer $$TOKEN" \
		-H "Content-Type: application/json" -d '{}' \
		"https://root.kcp.example:6443/services/access/apis/$(SCAR_GROUP)/v1alpha1/selfclusteraccessreviews" | jq .

.PHONY: mcp-smoke
mcp-smoke: ## Test MCP initialize + tools/list through the front-proxy for USER
	@TOKEN=$$(scripts/get-oidc-token.sh $(USER)); \
	if [ -z "$$TOKEN" ]; then echo "❌ could not get OIDC token for $(USER)"; exit 1; fi; \
	echo "==> MCP initialize as $(USER):"; \
	curl -sk -X POST "https://root.kcp.example:6443/services/mcp" \
		-H "Authorization: Bearer $$TOKEN" \
		-H "Content-Type: application/json" \
		-H "Accept: application/json, text/event-stream" \
		-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
		| sed -n 's/^data: //p' | jq -r '.result.serverInfo // .error'; \
	echo "==> MCP tools/list as $(USER):"; \
	curl -sk -X POST "https://root.kcp.example:6443/services/mcp" \
		-H "Authorization: Bearer $$TOKEN" \
		-H "Content-Type: application/json" \
		-H "Accept: application/json, text/event-stream" \
		-d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
		| sed -n 's/^data: //p' | jq -r '.result.tools[]?.name // .error'

.PHONY: status
status: ## Show component status
	@echo "── kcp-system ──"; $(KC) get pods -n $(KCP_NS)
	@echo "── endpoints ──"
	@echo "  SCAR: https://root.kcp.example:6443/services/access/apis/$(SCAR_GROUP)/v1alpha1/selfclusteraccessreviews"
	@echo "  MCP:  https://root.kcp.example:6443/services/mcp"
