# AWS Network Configuration

Create production-ready AWS VPCs with IPAM-backed CIDR allocation, dual-stack IPv6 support, and flexible NAT strategies. Designed to grow from individual projects to enterprise deployments.

## Quick Start

We recommend starting with **IPAM + dual-stack IPv6** from day one. This simplifies CIDR management and prepares your network for EKS Auto Mode and modern IPv6 workloads.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: my-network
  namespace: dev
spec:
  clusterName: my-cluster
  aws:
    config:
      region: us-east-1
  cidr:
    ipv4:
      ipam:
        globalPoolName: sandbox
    ipv6:
      enabled: true
      amazonProvided: true
    mode: dual-stack
```

**Cost: ~$32/mo** (SingleAz NAT) | **Created: VPC, 6 subnets, IGW, NAT, Egress-Only IGW, routes**

## Why Start with IPAM + IPv6?

### IPAM Benefits
- **No CIDR planning** - Automatic allocation from centrally managed pools
- **No conflicts** - IPAM prevents overlapping ranges across VPCs
- **Multi-account ready** - Share pools via RAM when you scale

### IPv6 Benefits
- **EKS Auto Mode** - IPv6 prevents IP exhaustion when scaling with EKS Auto Mode
- **Future-proof** - Native dual-stack from day one
- **Cost savings** - Egress-Only IGW is free (vs $32/mo NAT per AZ for IPv4)

## Understanding NAT Gateways

### What is NAT and Why Do You Need It?

**NAT (Network Address Translation)** allows resources in private subnets to initiate outbound connections to the internet while remaining unreachable from the internet. Private subnets don't have public IP addresses, so without NAT, they can't reach external services.

**Common use cases requiring outbound internet access:**
- Pulling container images from Docker Hub, ECR, or other registries
- Calling external APIs (payment processors, SaaS services, webhooks)
- Downloading OS updates and security patches
- Sending logs/metrics to external observability platforms
- Connecting to external databases or services

### NAT Gateway Costs

NAT Gateways are one of the most expensive components in AWS networking:

| Component | Cost |
|-----------|------|
| NAT Gateway (per hour) | ~$0.045/hr (~$32/mo) |
| Data processing | $0.045/GB |

**This is per NAT Gateway.** With HighlyAvailable (one per AZ), you're paying 3x the base cost.

### NAT Strategies Explained

| Strategy | NAT Gateways | Monthly Cost | Use Case |
|----------|--------------|--------------|----------|
| **None** | 0 | $0 | Isolated workloads, no internet needed |
| **SingleAz** | 1 | ~$32 | Dev/test, cost-sensitive, can tolerate brief outages |
| **HighlyAvailable** | 1 per AZ (3) | ~$96 | Production, uptime-critical IPv4 egress |

**SingleAz tradeoffs:**
- All private subnets route through one NAT Gateway in AZ-a
- If AZ-a has an outage, private subnets in AZ-b and AZ-c lose IPv4 internet access
- Workloads continue running, but can't pull new images or call external APIs
- Cross-AZ data transfer costs apply (~$0.01/GB between AZs)

**HighlyAvailable tradeoffs:**
- Each AZ has its own NAT Gateway
- No cross-AZ dependency for egress
- 3x the base cost
- No cross-AZ data transfer for egress traffic

### IPv6 Changes Everything

With dual-stack networking, IPv6 traffic uses an **Egress-Only Internet Gateway** instead of NAT:

| Feature | NAT Gateway (IPv4) | Egress-Only IGW (IPv6) |
|---------|-------------------|------------------------|
| Hourly cost | ~$0.045/hr | **Free** |
| Data processing | $0.045/GB | **Free** |
| HA requirement | 1 per AZ | 1 total (regional) |
| Inbound blocked | Yes | Yes |

**This is why we recommend dual-stack from day one.** As more services support IPv6, your egress costs drop to zero for that traffic. The Egress-Only IGW is automatically HA with no additional cost.

### When You Can Skip NAT Entirely

You don't need NAT if:

1. **IPv6-only workloads** - Use Egress-Only IGW (free, HA by default)
2. **VPC Endpoints** - Access AWS services (S3, ECR, etc.) via private endpoints instead of internet
3. **Isolated workloads** - No internet access needed (air-gapped, internal-only)
4. **Transit Gateway** - Route through a central egress VPC instead

**Example: ECR without NAT**

Instead of pulling images through NAT, create VPC endpoints for ECR:
- `com.amazonaws.region.ecr.api`
- `com.amazonaws.region.ecr.dkr`
- `com.amazonaws.region.s3` (for image layers)

This eliminates NAT dependency for container workloads and can significantly reduce costs.

## Use Cases: Individual to Enterprise

### Stage 1: Individual Developer (~$32/mo)

Starting out? Use the minimal configuration with SingleAz NAT.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: dev-vpc
spec:
  clusterName: dev
  aws:
    config:
      region: us-east-1
  cidr:
    ipv4:
      ipam:
        globalPoolName: sandbox
    ipv6:
      enabled: true
      amazonProvided: true
    mode: dual-stack
```

**What you get:**
- VPC with IPv4 (from IPAM) + IPv6 (Amazon-provided /56)
- 3 public + 3 private subnets across AZs a, b, c (HA from day one)
- Single NAT Gateway in AZ-a (handles all IPv4 private egress)
- Egress-Only IGW for IPv6 private traffic (free, no single point of failure)
- Ready for EKS Auto Mode

### Stage 2: Small Team (~$32/mo)

Same cost, but customize for your team's needs.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: team-vpc
spec:
  clusterName: team-prod
  aws:
    config:
      region: us-west-2
      tags:
        team: platform
        environment: production
  cidr:
    ipv4:
      ipam:
        globalPoolName: team-pool
    ipv6:
      enabled: true
      amazonProvided: true
    mode: dual-stack
  subnets:
    netmaskLength: 21  # /21 = 2048 IPs per subnet (default 3 AZs)
```

### Stage 3: Growing Startup (~$96/mo)

Add NAT redundancy when IPv4 egress uptime matters.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: prod-vpc
spec:
  clusterName: prod
  aws:
    config:
      region: us-east-1
      tags:
        environment: production
        cost-center: engineering
  cidr:
    ipv4:
      ipam:
        globalPoolName: production
    ipv6:
      enabled: true
      ipam:
        globalPoolName: ipv6-public  # Use IPAM for IPv6 too
    mode: dual-stack
  subnets:
    availabilityZones: [a, b, c]
    netmaskLength: 19  # /19 = 8192 IPs per subnet
  nat:
    strategy: HighlyAvailable  # NAT per AZ - no single point of failure
```

**What changes:**
- HighlyAvailable NAT = 3 NAT Gateways (one per AZ) - no single point of failure for IPv4 egress
- Larger subnets for growth (/19 = 8192 IPs per subnet)
- IPv6 from IPAM for centralized management across VPCs

### Stage 4: Enterprise (~$150/mo+)

Full featured with Transit Gateway, Flow Logs, and compliance-ready configuration.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: enterprise-vpc
  namespace: acme-prod
spec:
  clusterName: acme-prod
  aws:
    providerConfig: acme-aws-prod
    config:
      region: us-east-1
      accountId: "123456789012"
      tags:
        environment: production
        compliance: soc2
        cost-center: "12345"
        data-classification: confidential
  cidr:
    ipv4:
      ipam:
        globalPoolName: enterprise-prod
    ipv6:
      enabled: true
      ipam:
        globalPoolName: ipv6-enterprise
    mode: dual-stack
  subnets:
    availabilityZones: [a, b, c]
    netmaskLength: 18  # /18 = 16384 IPs per subnet
  nat:
    strategy: HighlyAvailable
  transitGateway:
    enabled: true
    config:
      tgwId: tgw-abc123
      routeTablePropagation: true
  flowLogs:
    enabled: true
    config:
      destination: s3
      logDestinationArn: arn:aws:s3:::acme-vpc-flow-logs
      trafficType: ALL
```

**Enterprise features:**
- Transit Gateway for hub-and-spoke networking
- VPC Flow Logs for security monitoring and compliance
- Larger subnets for enterprise workloads
- Full tagging for cost allocation

## Special Cases

### Private-Only Network ($0/mo)

For isolated workloads that don't need internet access.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: isolated-vpc
spec:
  clusterName: isolated
  aws:
    config:
      region: us-east-1
  cidr:
    ipv4:
      ipam:
        poolRef:
          name: isolated-pool
  subnets:
    types: [private]  # No public subnets
  nat:
    enabled: false    # No internet egress
```

### Manual CIDR (No IPAM)

For legacy environments or when IPAM isn't available.

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: legacy-vpc
spec:
  clusterName: legacy
  aws:
    config:
      region: eu-west-1
  cidr:
    ipv4:
      manual:
        vpcCidr: 172.16.0.0/16
        subnets:
          public:
            - cidr: 172.16.0.0/20
              availabilityZone: a
            - cidr: 172.16.16.0/20
              availabilityZone: b
            - cidr: 172.16.32.0/20
              availabilityZone: c
          private:
            - cidr: 172.16.128.0/20
              availabilityZone: a
            - cidr: 172.16.144.0/20
              availabilityZone: b
            - cidr: 172.16.160.0/20
              availabilityZone: c
```

## Cost Summary

| Configuration | NAT Strategy | Monthly Cost |
|--------------|--------------|--------------|
| Private Only | None | $0 |
| Individual (SingleAz) | SingleAz | ~$32 |
| Team (2 AZ, SingleAz) | SingleAz | ~$32 |
| Production (HA NAT) | HighlyAvailable | ~$96 |
| Enterprise (HA + TGW) | HighlyAvailable | ~$132 |
| Enterprise (Full) | HighlyAvailable | ~$150+ |

**Note:** IPv6 egress via Egress-Only IGW is free. Only IPv4 NAT Gateways cost money.

## Prerequisites

### IPAM Setup

Before creating networks, set up an IPAM with pools:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: IPAM
metadata:
  name: my-ipam
spec:
  scope: private  # or global-organization for multi-account
  homeRegion: us-east-1
  pools:
    - name: sandbox
      cidr: 10.0.0.0/8
      labels:
        hops.ops.com.ai/global-pool: sandbox
    - name: ipv6-public
      addressFamily: ipv6
      scope: public
      amazonProvidedIpv6CidrBlock: true
      netmaskLength: 52
      labels:
        hops.ops.com.ai/global-pool: ipv6-public
```

### EKS Auto Mode Compatibility

If you plan to use EKS Auto Mode, your network is already configured correctly with dual-stack:
- **Dual-stack enabled** - `cidr.mode: dual-stack`
- **IPv6 configured** - Either `amazonProvided: true` or IPAM IPv6 pool
- **Proper subnet tags** - Automatically added: `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`

## API Reference

### spec.aws

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `providerConfig` | string | clusterName | AWS ProviderConfig name |
| `config.region` | string | required | AWS region |
| `config.accountId` | string | - | AWS account ID (for tagging) |
| `config.tags` | object | - | Additional AWS tags |

### spec.cidr

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ipv4.ipam.globalPoolName` | string | - | Global IPAM pool name |
| `ipv4.ipam.poolRef.name` | string | - | Direct IPAM pool reference |
| `ipv4.manual.vpcCidr` | string | - | Manual VPC CIDR |
| `ipv6.enabled` | boolean | false | Enable IPv6 |
| `ipv6.amazonProvided` | boolean | false | Use Amazon-provided /56 |
| `mode` | string | ipv4-only | `ipv4-only`, `dual-stack`, `ipv6-only` |

### spec.subnets

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `availabilityZones` | []string | [a, b, c] | AZ suffixes |
| `netmaskLength` | int | 20 | IPv4 subnet size |
| `types` | []string | [public, private] | Subnet types |

### spec.nat

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | true | Enable NAT Gateways |
| `strategy` | string | SingleAz | `SingleAz`, `HighlyAvailable`, `None` |

### spec.transitGateway

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | false | Enable TGW attachment |
| `config.tgwId` | string | - | Transit Gateway ID |
| `config.routeTablePropagation` | boolean | true | Enable route propagation |

### spec.flowLogs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | false | Enable VPC Flow Logs |
| `config.destination` | string | cloudwatch | `cloudwatch` or `s3` |
| `config.logDestinationArn` | string | - | Destination ARN |
| `config.trafficType` | string | ALL | `ALL`, `ACCEPT`, `REJECT` |

## Status

The Network exposes observed state in `status.network`:

```yaml
status:
  ready: true
  network:
    vpcId: vpc-abc123
    cidr:
      ipv4: 10.100.0.0/16
      ipv6: 2600:1f18:abc::/56
    subnets:
      public:
        - name: my-vpc-public-a
          id: subnet-pub-a
          ipv4CidrBlock: 10.100.0.0/20
          ipv6CidrBlock: 2600:1f18:abc:0::/64
      private:
        - name: my-vpc-private-a
          id: subnet-priv-a
          ipv4CidrBlock: 10.100.128.0/20
          ipv6CidrBlock: 2600:1f18:abc:8000::/64
    natGateways:
      - name: my-vpc-nat-a
        id: nat-abc123
    internetGateway:
      id: igw-abc123
    egressOnlyInternetGateway:
      id: eigw-abc123
```

## License

Apache-2.0
