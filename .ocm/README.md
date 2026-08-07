# OCM packaging

The two kcp virtual workspaces are packaged as [OCM](https://ocm.software)
components following the platform-mesh three-tier convention:

```
github.com/platform-mesh/<name>                    service component
  ├─ chart → github.com/platform-mesh/helm-charts/<name>   (helmChart, ociArtifact)
  └─ image → github.com/platform-mesh/images/<name>        (ociImage, ociArtifact)
```

for `<name>` in `access-vw`, `mcp-vw`.

The image sub-components reference the **canonical kcp-dev images**
(`ghcr.io/kcp-dev/contrib-access-vw`, `ghcr.io/kcp-dev/contrib-mcp-vw`)
with `relation: local`, so `ocm transfer` mirrors the image content into
the target OCM registry — images are never rebuilt here. `Chart.yaml
.appVersion` must therefore be an image tag released by the kcp-dev
contrib repos.

## Layout

| Path | Purpose |
|------|---------|
| `charts/access-vw`, `charts/mcp-vw` | Helm charts (converted from the local-setup kustomize manifests) |
| `.ocm/component-constructor.yaml` | Templated constructor shared by both services |
| `Makefile` | Build/publish pipeline |

Versioning follows platform-mesh: `Chart.yaml .version` is the chart/component
version, `.appVersion` the image tag. Bump `.version` on every chart change —
published component versions are immutable.

## Publishing

```sh
# everything: charts + OCM components + transfer
make publish

# or step by step
make charts       # helm package+push  → ghcr.io/.../mcp-integration/charts/<name>:<version>
make components   # ocm add components → .ocm/transport-<name>.ctf
make transfer     # ocm transfer ctf   → ghcr.io/platform-mesh
```

Order matters: `ocm add components` resolves the digests of the referenced
chart/image OCI artifacts, so the chart must be pushed (and the kcp-dev
image tag published) before the component is built.

Overridable variables: `REGISTRY`, `OCM_REPO`, `ACCESS_VW_IMAGE`,
`MCP_VW_IMAGE`.

Requires: `helm`, `ocm`, `yq`, and a `helm registry login` for ghcr.io.

## Deployment expectations

Both charts assume a kcp control plane managed by
[kcp-operator](https://github.com/kcp-dev/kcp-operator) in the release
namespace: they mint their kcp identities via `Kubeconfig` CRs targeting the
`root` RootShard and mount operator-managed CA secrets (configurable under
`.Values.kcp`). Serving certs are issued by cert-manager from the kcp server
CA issuer. See `local-setup/` (branch `local-tests`) for a complete working
environment.
