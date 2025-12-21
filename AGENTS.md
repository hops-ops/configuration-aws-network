# Network Config Agent Guide

This repository publishes the `Network` configuration package. Use this guide when updating schemas, templates, or automation for AWS VPC networks.

## Repository Layout

- `apis/`: CRDs, definitions, and composition for `Network`. Treat these files as source of truth for the released package.
- `examples/`: Renderable composite examples demonstrating minimal, dual-stack, enterprise, and IPAM-based specs. Keep them in sync with the schema.
- `examples/observed-resources/`: Multi-step reconciliation fixtures for testing gated resource creation.
- `functions/render/`: Go-template pipeline. Files execute in lexical order (`00-`, `10-`, `20-`), so leave numeric gaps to simplify future inserts.
- `tests/test*`: KCL-based regression tests executed via `up test`.
- `tests/e2etest*`: KCL-based E2E tests executed via `up test` with `--e2e` flag. Expects `aws-creds` file to exist (but gitignored).
- `.github/`: GitHub workflows.
- `.gitops/`: GitOps automation usage.
- `_output/`, `.up/`: Generated artefacts. Remove with `make clean` when needed.

## Rendering Guidelines

- Declare every reused value in `00-desired-values.yaml.gotmpl` with sensible defaults. Avoid direct field access in later templates.
- Split large XRDs into per-provider or per-feature files (`01-desired-values-cidr.yaml.gotmpl`, `01-desired-values-subnets.yaml.gotmpl`).
- Use `10-observed-values.yaml.gotmpl` to extract Ready conditions and observed ARNs/IDs from observed resources.
- Stick to simple string concatenation. Keep templates legible and compatible with Renovate.
- Resource templates must reference only previously declared variables. If you add new variables, hoist them into the `00-` or `01-` files.
- Default AWS tags to `{"hops": "true"}` and merge caller-provided tags afterwards.
- Gate resources that depend on parent resources being Ready (e.g., subnets wait for VPC CIDR allocation).
- Favour readability over micro-templating.

## Resource Naming

Avoid redundant type suffixes. The `kind` already tells you what the resource is:

```yaml
# Good - clean name
metadata:
  name: {{ $networkName }}  # "my-vpc" - Kind tells you it's a VPC

# Bad - redundant suffix
metadata:
  name: {{ $networkName }}-vpc  # "my-vpc-vpc"
```

Suffixes are appropriate when disambiguating multiple resources of the same kind.

## Testing

- Regression tests live in `tests/test-render/main.k` and cover:
  - Minimal example: VPC with IPAM, dual-stack IPv6, no NAT
  - Private-only example: No public subnets, no IGW, no NAT
  - Dual-stack example: IPv6 with Amazon-provided CIDR, NAT gateway
  - Manual CIDR example: No IPAM required, explicit CIDR blocks
  - Enterprise example: Transit Gateway, Flow Logs, HA NAT
- Use `assertResources` to lock the behaviour you care about. Provide only the fields under test so future changes remain flexible elsewhere.
- Run `make test` (or `up test run tests/*`) after touching templates or examples.

## E2E Testing

- Tests live under `tests/e2etest-network` and are invoked through `up test ... --e2e`.
- Provide real AWS credentials via `tests/e2etest-network/secrets/aws-creds` (gitignored). The file must contain a `[default]` profile:

  ```ini
  [default]
  aws_access_key_id = <access key>
  aws_secret_access_key = <secret key>
  ```

- **Persistent infrastructure** (from aws-ipam e2e test):
  - IPv4 pool: `ipam-pool-0a82c73b97dc0dabb` (PRIVATE scope, 10.0.0.0/8)
  - IPv6 pool: `ipam-pool-0decd6c5216660c74` (PRIVATE scope ULA)
- **Test configuration**: Dual-stack (IPv4 + IPv6 both via IPAM), public+private subnets, subnet IPAM enabled.
- Run `make e2e` (or `up test run tests/e2etest-network --e2e`) to execute the suite.
- The spec sets `skipDelete: false`, so resources are cleaned up automatically. Double-check for any leaked VPCs, subnets, or NAT gateways if the test aborts early.
- Never commit the `aws-creds` file.

## Multi-Step Reconciliation

This XRD uses observed-state gating for resources that depend on parent resources:

1. **VPC creation**: VPC renders immediately with IPAM pool selector
2. **CIDR allocation**: Subnet CIDRs allocate from IPAM after VPC is Ready
3. **Subnet creation**: Subnets render after CIDR allocations are Ready

Test this flow using observed-resources fixtures:
```bash
make render:example-ipam-subnets-ondemand  # Initial render (no subnets)
up composition render --xrd=... --observed-resources=examples/observed-resources/.../steps/1/
```

## Development Workflow

- `make render` – render all examples.
- `make validate` – run schema validation against the XRD and examples.
- `make test` – execute the regression suite.
- `make e2e` – execute E2E tests.
- `make render:example-minimal` – render a single example.
- `make validate:example-minimal` – validate a single example.

Document behavioural changes in `README.md` and refresh `examples/` whenever the schema shifts.

## Key Architecture Decisions

1. **IPAM-First Design**: Supports IPAM pools with fallback to manual CIDR
2. **On-Demand Subnet Pools**: Creates child IPAM pools dynamically when `subnets.ipam.enabled`
3. **IPv6 Native**: Dual-stack with Amazon-provided or IPAM /56 blocks
4. **No NAT by Default**: Encourages IPv6 egress + load balancers instead of NAT cost
5. **Flexible NAT Strategies**: SingleAz (dev/test), HighlyAvailable (production), None
