# Build, package and publish the two kcp virtual workspaces (access-vw,
# mcp-vw) as platform-mesh OCM components.
#
# Images are NOT built here: the canonical images are published by the
# kcp-dev contrib repos (ghcr.io/kcp-dev/contrib-*). The OCM components
# reference them (relation: local), so `ocm transfer` mirrors the image
# content into the target OCM registry.
#
# Per service the pipeline is:
#   1. helm package + push (OCI)    → ghcr.io/.../mcp-integration/charts/<name>:<version>
#   2. ocm add components (CTF)     → .ocm/transport-<name>.ctf
#   3. ocm transfer ctf             → OCM_REPO
#
# Versions come from charts/<name>/Chart.yaml (.version / .appVersion),
# matching the platform-mesh convention. .appVersion must be an image tag
# released by the kcp-dev repos.

# Registry namespace the charts are published under.
REGISTRY        ?= ghcr.io/platform-mesh/mcp-integration
# OCM repository components are transferred to.
OCM_REPO        ?= ghcr.io/platform-mesh
CHART_REPO_URL  ?= https://github.com/platform-mesh/mcp-integration

# Canonical images (published by the kcp-dev contrib repos' CI).
ACCESS_VW_IMAGE ?= ghcr.io/kcp-dev/contrib-access-vw
MCP_VW_IMAGE    ?= ghcr.io/kcp-dev/contrib-mcp-vw

ACCESS_VW_IMAGE_REPO ?= https://github.com/kcp-dev/contrib-access-virtual-workspace
MCP_VW_IMAGE_REPO    ?= https://github.com/kcp-dev/contrib-mcp-virtual-workspace

COMMIT := $(shell git rev-parse HEAD)

# Per-chart version lookups (requires yq).
chart_version = $(shell yq '.version' charts/$(1)/Chart.yaml)
app_version   = $(shell yq '.appVersion' charts/$(1)/Chart.yaml)

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ── Helm charts (OCI) ────────────────────────────────────────────────────────

.PHONY: chart-access-vw
chart-access-vw: ## Package + push the access-vw chart
	helm package charts/access-vw -d .ocm/dist
	helm push .ocm/dist/access-vw-$(call chart_version,access-vw).tgz oci://$(REGISTRY)/charts

.PHONY: chart-mcp-vw
chart-mcp-vw: ## Package + push the mcp-vw chart
	helm package charts/mcp-vw -d .ocm/dist
	helm push .ocm/dist/mcp-vw-$(call chart_version,mcp-vw).tgz oci://$(REGISTRY)/charts

.PHONY: charts
charts: chart-access-vw chart-mcp-vw ## Package + push both charts

# ── OCM components ───────────────────────────────────────────────────────────

define ocm_component
	rm -rf .ocm/transport-$(1).ctf
	ocm add components -c --templater=go --file .ocm/transport-$(1).ctf \
		.ocm/component-constructor.yaml -- \
		NAME=$(1) \
		VERSION=$(call chart_version,$(1)) \
		APP_VERSION=$(call app_version,$(1)) \
		COMMIT=$(COMMIT) \
		CHART_REPO=$(CHART_REPO_URL) \
		CHART_OCI_PATH=$(REGISTRY)/charts/$(1) \
		IMAGE_NAME=$(2) \
		IMAGE_REPO=$(3) \
		IMAGE_REPO_SHA=$(shell git ls-remote $(3) HEAD | cut -f1)
endef

.PHONY: component-access-vw
component-access-vw: ## Build the access-vw OCM component (CTF)
	$(call ocm_component,access-vw,$(ACCESS_VW_IMAGE),$(ACCESS_VW_IMAGE_REPO))

.PHONY: component-mcp-vw
component-mcp-vw: ## Build the mcp-vw OCM component (CTF)
	$(call ocm_component,mcp-vw,$(MCP_VW_IMAGE),$(MCP_VW_IMAGE_REPO))

.PHONY: components
components: component-access-vw component-mcp-vw ## Build both OCM components

.PHONY: transfer
transfer: ## Transfer both CTFs to $(OCM_REPO)
	ocm transfer ctf .ocm/transport-access-vw.ctf $(OCM_REPO)
	ocm transfer ctf .ocm/transport-mcp-vw.ctf $(OCM_REPO)

.PHONY: publish
publish: charts components transfer ## Full pipeline: charts + components + transfer

.PHONY: clean
clean: ## Remove build artifacts
	rm -rf .ocm/dist .ocm/transport-*.ctf
