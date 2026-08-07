## mcp-integration local setup

Integration and verification environment for the kcp MCP stack. It stands up a
local [Kind](https://kind.sigs.k8s.io/) cluster running kcp (via
[kcp-operator](https://github.com/kcp-dev/kcp-operator)), Keycloak (OIDC), and
the two virtual workspaces:

- [contrib-access-virtual-workspace](https://github.com/kcp-dev/contrib-access-virtual-workspace) —
  the SCAR API (`SelfClusterAccessReview`), answering "which workspaces can
  this user access?"
- [contrib-mcp-virtual-workspace](https://github.com/kcp-dev/contrib-mcp-virtual-workspace) —
  an MCP server exposed as a kcp virtual workspace, scoping AI-agent access to
  exactly the workspaces SCAR returns.

Both are exposed through kcp's front-proxy:

```
AI client ──OIDC──▶ front-proxy ──▶ /services/mcp    ──▶ mcp-vw ──▶ access-vw (SCAR)
                                 └▶ /services/access ──▶ access-vw          │
                                                        workspaces ◀────────┘
                                                        (impersonation)
```

## Requirements and Setup

Prerequisites: `docker`, `kind`, `kubectl` (+ [ws plugin](https://github.com/kcp-dev/kcp/tree/main/cli)),
`helm`, `tilt`, `mkcert`, `jq`, `curl`, and sibling checkouts of the two
contrib repos next to this one.

Add to `/etc/hosts`:

```
127.0.0.1  keycloak.kcp.example root.kcp.example
```

Then:

```sh
make setup-infra   # one-time: kind + metallb + cert-manager + keycloak + kcp
tilt up            # builds both VW images from sibling repos and deploys them
make seed          # per-user workspaces, APIBinding, RBAC (after first tilt up)
```

> Note: on the very first `tilt up`, the access-vw init container crash-loops
> until `make seed` runs — kcp only publishes APIExportEndpointSlice URLs once
> at least one workspace binds the export. It recovers on its own.

Verify:

```sh
make scar USER=alice    # SCAR through the front-proxy
make mcp-smoke          # MCP initialize + tools/list through the front-proxy
make status
```

Tear down with `make teardown`. See `make help` for all targets.

## Support, Feedback, Contributing

This project is open to feature requests/suggestions, bug reports etc. via [GitHub issues](https://github.com/platform-mesh/mcp-integration/issues). Contribution and feedback are encouraged and always welcome. For more information about how to contribute, the project structure, as well as additional contribution information, see our [Contribution Guidelines](CONTRIBUTING.md).

## Security / Disclosure
If you find any bug that may be a security problem, please follow our instructions at [in our security policy](https://github.com/platform-mesh/mcp-integration/security/policy) on how to report it. Please do not create GitHub issues for security-related doubts or problems.

## Code of Conduct

Please refer to our [Code of Conduct](https://github.com/platform-mesh/.github/blob/main/CODE_OF_CONDUCT.md) for information on the expected conduct for contributing to Platform Mesh.

<p align="center"><img alt="Bundesministerium für Wirtschaft und Energie (BMWE)-EU funding logo" src="https://apeirora.eu/assets/img/BMWK-EU.png" width="400"/></p>
