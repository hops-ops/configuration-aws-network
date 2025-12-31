# AWS Network Configuration

Create production-ready AWS VPCs with IPAM-backed CIDR allocation, dual-stack IPv6 support, and flexible NAT strategies. Designed to grow from individual projects to enterprise deployments.

## Quick Start

### Minimal Network (Manual CIDRs)

The simplest configuration with explicit CIDR blocks:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: my-network
  namespace: dev
spec:
  region: us-east-1
  providerConfigRef:
    name: default
  vpc:
    cidr: "10.1.0.0/16"
  subnets:
    - name: my-network-public-a
      cidr: "10.1.0.0/24"
      availabilityZone: a
      public: true
    - name: my-network-public-b
      cidr: "10.1.1.0/24"
      availabilityZone: b
      public: true
    - name: my-network-private-a
      cidr: "10.1.16.0/20"
      availabilityZone: a
    - name: my-network-private-b
      cidr: "10.1.32.0/20"
      availabilityZone: b
```

**Cost: ~$0/mo** | **Created: VPC, 4 subnets, IGW, route tables**

### IPAM + Dual-Stack (Recommended)

For enterprise deployments, use IPAM for automatic CIDR allocation:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: my-network
  namespace: dev
spec:
  region: us-east-1
  providerConfigRef:
    name: default
  ipam:
    ipv4:
      enabled: true
      poolId: ipam-pool-0123456789abcdef0
      scopeId: ipam-scope-0123456789abcdef0
      vpc:
        netmaskLength: 16
      subnets:
        availabilityZones: [a, b, c]
        public:
          enabled: true
          netmaskLength: 24
        private:
          enabled: true
          netmaskLength: 20
    ipv6Ula:
      enabled: true
      poolId: ipam-pool-0fedcba9876543210
      scopeId: ipam-scope-0fedcba9876543210
      vpc:
        netmaskLength: 56
      subnets:
        availabilityZones: [a, b, c]
        public:
          enabled: true
          netmaskLength: 64
        private:
          enabled: true
          netmaskLength: 64
  vpc: {}
  nat:
    enabled: false
```

**Cost: ~$0/mo** | **Created: VPC, 6 subnets, IPAM pools, IGW, Egress-Only IGW, routes**

### Why No NAT by Default?

For Kubernetes workloads, NAT Gateways are often unnecessary:

1. **Public ingress via Load Balancers** - The platform handles external traffic to your services
2. **IPv6 egress is free** - Pods use the Egress-Only Internet Gateway for outbound IPv6 traffic
3. **VPC Endpoints for AWS services** - Access ECR, S3 via private endpoints

This saves ~$32/mo. Add NAT later if you need IPv4 egress to external services.

## Why Start with IPAM + IPv6?

### IPAM Benefits
- **No CIDR planning** - Automatic allocation from centrally managed pools
- **No conflicts** - IPAM prevents overlapping ranges across VPCs
- **Multi-account ready** - Share pools via RAM when you scale

### IPv6 Benefits
- **EKS Auto Mode** - IPv6 prevents IP exhaustion when scaling
- **Future-proof** - Native dual-stack from day one
- **Cost savings** - Egress-Only IGW is free (vs $32/mo NAT per AZ for IPv4)

## Understanding NAT Gateways

### What is NAT and Why Do You Need It?

**NAT (Network Address Translation)** allows resources in private subnets to initiate outbound connections to the internet while remaining unreachable from the internet.

**Common use cases requiring outbound internet access:**
- Pulling container images from Docker Hub or external registries
- Calling external APIs (payment processors, SaaS services)
- Downloading OS updates and security patches
- Sending logs/metrics to external platforms

### NAT Gateway Costs

| Component | Cost |
|-----------|------|
| NAT Gateway (per hour) | ~$0.045/hr (~$32/mo) |
| Data processing | $0.045/GB |

**This is per NAT Gateway.** With HighlyAvailable (one per AZ), you're paying 3x the base cost.

### NAT Strategies Explained

| Strategy | NAT Gateways | Monthly Cost | Use Case |
|----------|--------------|--------------|----------|
| **None** | 0 | $0 | Isolated workloads, no internet needed |
| **SingleAz** | 1 | ~$32 | Dev/test, cost-sensitive |
| **HighlyAvailable** | 1 per AZ (3) | ~$96 | Production, uptime-critical |

### IPv6 Changes Everything

With dual-stack networking, IPv6 traffic uses an **Egress-Only Internet Gateway** instead of NAT:

| Feature | NAT Gateway (IPv4) | Egress-Only IGW (IPv6) |
|---------|-------------------|------------------------|
| Hourly cost | ~$0.045/hr | **Free** |
| Data processing | $0.045/GB | **Free** |
| HA requirement | 1 per AZ | 1 total (regional) |

## Use Cases

### Stage 1: Individual Developer (~$0/mo)

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: dev-vpc
spec:
  region: us-east-1
  providerConfigRef:
    name: default
  vpc:
    cidr: "10.1.0.0/16"
  subnets:
    - name: dev-public-a
      cidr: "10.1.0.0/24"
      availabilityZone: a
      public: true
    - name: dev-public-b
      cidr: "10.1.1.0/24"
      availabilityZone: b
      public: true
    - name: dev-private-a
      cidr: "10.1.16.0/20"
      availabilityZone: a
    - name: dev-private-b
      cidr: "10.1.32.0/20"
      availabilityZone: b
```

### Stage 2: Small Team with NAT (~$32/mo)

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: team-vpc
spec:
  region: us-west-2
  providerConfigRef:
    name: default
  tags:
    team: platform
    environment: production
  vpc:
    cidr: "10.2.0.0/16"
  subnets:
    - name: team-public-a
      cidr: "10.2.0.0/24"
      availabilityZone: a
      public: true
    - name: team-public-b
      cidr: "10.2.1.0/24"
      availabilityZone: b
      public: true
    - name: team-public-c
      cidr: "10.2.2.0/24"
      availabilityZone: c
      public: true
    - name: team-private-a
      cidr: "10.2.16.0/20"
      availabilityZone: a
    - name: team-private-b
      cidr: "10.2.32.0/20"
      availabilityZone: b
    - name: team-private-c
      cidr: "10.2.48.0/20"
      availabilityZone: c
  nat:
    enabled: true
    strategy: SingleAz
```

### Stage 3: Production with HA NAT (~$96/mo)

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: prod-vpc
spec:
  region: us-east-1
  providerConfigRef:
    name: aws-prod
  tags:
    environment: production
    cost-center: engineering
  vpc:
    cidr: "10.5.0.0/16"
  subnets:
    - name: ha-public-a
      cidr: "10.5.0.0/24"
      availabilityZone: a
      public: true
    - name: ha-public-b
      cidr: "10.5.1.0/24"
      availabilityZone: b
      public: true
    - name: ha-public-c
      cidr: "10.5.2.0/24"
      availabilityZone: c
      public: true
    - name: ha-private-a
      cidr: "10.5.16.0/20"
      availabilityZone: a
    - name: ha-private-b
      cidr: "10.5.32.0/20"
      availabilityZone: b
    - name: ha-private-c
      cidr: "10.5.48.0/20"
      availabilityZone: c
  nat:
    enabled: true
    strategy: HighlyAvailable
```

### Stage 4: Dual-Stack with ULA IPv6

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: dual-stack
spec:
  region: us-east-1
  providerConfigRef:
    name: default
  vpc:
    cidr: "10.3.0.0/16"
    ipv6:
      ula:
        enabled: true
        cidr: "fd00:dead:beef::/56"
        ipamPoolId: ipam-pool-0abc123
  subnets:
    - name: ds-public-a
      cidr: "10.3.0.0/24"
      availabilityZone: a
      public: true
      ipv6:
        ulaCidr: "fd00:dead:beef:0::/64"
    - name: ds-public-b
      cidr: "10.3.1.0/24"
      availabilityZone: b
      public: true
      ipv6:
        ulaCidr: "fd00:dead:beef:1::/64"
    - name: ds-private-a
      cidr: "10.3.16.0/20"
      availabilityZone: a
      ipv6:
        ulaCidr: "fd00:dead:beef:100::/64"
    - name: ds-private-b
      cidr: "10.3.32.0/20"
      availabilityZone: b
      ipv6:
        ulaCidr: "fd00:dead:beef:101::/64"
  nat:
    enabled: true
    strategy: SingleAz
```

### Stage 5: Dual-Stack with Amazon-Provided IPv6

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: dual-stack-amazon
spec:
  region: us-east-1
  providerConfigRef:
    name: default
  vpc:
    cidr: "10.4.0.0/16"
    ipv6:
      amazonProvided:
        enabled: true
  subnets:
    - name: dsa-public-a
      cidr: "10.4.0.0/24"
      availabilityZone: a
      public: true
    - name: dsa-public-b
      cidr: "10.4.1.0/24"
      availabilityZone: b
      public: true
    - name: dsa-private-a
      cidr: "10.4.16.0/20"
      availabilityZone: a
    - name: dsa-private-b
      cidr: "10.4.32.0/20"
      availabilityZone: b
  nat:
    enabled: true
    strategy: SingleAz
```

### Stage 6: Enterprise with IPAM + TGW + Flow Logs

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: Network
metadata:
  name: enterprise-vpc
  namespace: acme-prod
spec:
  region: us-east-1
  providerConfigRef:
    name: acme-aws-prod
  tags:
    environment: production
    compliance: soc2
    cost-center: "12345"
  ipam:
    ipv4:
      enabled: true
      poolId: ipam-pool-enterprise123
      scopeId: ipam-scope-enterprise456
      vpc:
        netmaskLength: 16
      subnets:
        availabilityZones: [a, b, c]
        public:
          enabled: true
          netmaskLength: 24
        private:
          enabled: true
          netmaskLength: 18
    ipv6Ula:
      enabled: true
      poolId: ipam-pool-ipv6-enterprise
      scopeId: ipam-scope-ipv6-enterprise
      vpc:
        netmaskLength: 56
      subnets:
        availabilityZones: [a, b, c]
        public:
          enabled: true
          netmaskLength: 64
        private:
          enabled: true
          netmaskLength: 64
  vpc: {}
  nat:
    enabled: true
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

## Cost Summary

| Configuration | NAT Strategy | Monthly Cost |
|--------------|--------------|--------------|
| Minimal (no NAT) | None | $0 |
| With SingleAz NAT | SingleAz | ~$32 |
| Production (HA NAT) | HighlyAvailable | ~$96 |
| Enterprise (HA + TGW) | HighlyAvailable | ~$132+ |

**Note:** IPv6 egress via Egress-Only IGW is free. Only IPv4 NAT Gateways cost money.

## API Reference

### spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `region` | string | Yes | AWS region |
| `providerConfigRef.name` | string | No | AWS ProviderConfig name (default: "default") |
| `providerConfigRef.kind` | string | No | Provider config kind (default: "ProviderConfig") |
| `tags` | object | No | Additional AWS tags |
| `managementPolicies` | []string | No | Management policies (default: ["*"]) |

### spec.vpc

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `cidr` | string | No* | IPv4 CIDR block (e.g., "10.1.0.0/16") |
| `ipv6.ula.enabled` | boolean | No | Enable ULA IPv6 |
| `ipv6.ula.cidr` | string | No | ULA IPv6 CIDR (e.g., "fd00::/56") |
| `ipv6.ula.ipamPoolId` | string | No | IPAM pool ID for ULA IPv6 |
| `ipv6.amazonProvided.enabled` | boolean | No | Request Amazon-provided /56 IPv6 |
| `forProvider` | object | No | Pass-through for VPC forProvider fields |

*Required unless using `ipam.ipv4`

### spec.subnets[]

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Subnet name |
| `cidr` | string | No* | IPv4 CIDR block |
| `availabilityZone` | string | Yes | AZ suffix (a, b, c) |
| `public` | boolean | No | Public subnet (default: false) |
| `ipv6.ulaCidr` | string | No | ULA IPv6 CIDR for subnet |
| `ipv6.amazonProvidedCidr` | string | No | Amazon IPv6 CIDR for subnet |

*Required unless using `ipam.ipv4`

### spec.ipam

| Field | Type | Description |
|-------|------|-------------|
| `ipv4.enabled` | boolean | Enable IPv4 CIDR allocation from IPAM |
| `ipv4.poolId` | string | IPAM pool ID |
| `ipv4.scopeId` | string | IPAM scope ID |
| `ipv4.vpc.netmaskLength` | int | VPC netmask (default: 16) |
| `ipv4.subnets.availabilityZones` | []string | AZs for auto-generated subnets |
| `ipv4.subnets.public.enabled` | boolean | Create public subnets |
| `ipv4.subnets.public.netmaskLength` | int | Public subnet netmask |
| `ipv4.subnets.private.enabled` | boolean | Create private subnets |
| `ipv4.subnets.private.netmaskLength` | int | Private subnet netmask |
| `ipv6Ula.*` | | Same structure as ipv4 for IPv6 ULA |

### spec.nat

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | false | Enable NAT Gateways |
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
| `config.iamRoleArn` | string | - | IAM role for CloudWatch |

## Status

The Network exposes observed state in `status`:

```yaml
status:
  ready: true
  allocations:  # Only present when using ipam
    ipv4:
      ready: true
      cidr: "10.100.0.0/16"
      vpcPoolId: ipam-pool-xxx
      subnetPoolId: ipam-pool-yyy
      subnets:
        public-a: "10.100.0.0/24"
        private-a: "10.100.16.0/20"
    ipv6Ula:
      ready: true
      cidr: "fd00:dead:beef::/56"
      vpcPoolId: ipam-pool-ipv6-xxx
      subnetPoolId: ipam-pool-ipv6-yyy
      subnets:
        public-a: "fd00:dead:beef:0::/64"
        private-a: "fd00:dead:beef:100::/64"
  network:
    name: my-network
    region: us-east-1
    vpcId: vpc-abc123
    cidr:
      ipv4: "10.100.0.0/16"
      ipv6Ula: "fd00:dead:beef::/56"
    availabilityZones:
      - us-east-1a
      - us-east-1b
    subnets:
      public:
        - name: my-network-public-a
          id: subnet-pub-a
          availabilityZone: us-east-1a
          ipv4CidrBlock: "10.100.0.0/24"
          ipv6CidrBlock: "fd00:dead:beef:0::/64"
      private:
        - name: my-network-private-a
          id: subnet-priv-a
          availabilityZone: us-east-1a
          ipv4CidrBlock: "10.100.16.0/20"
          ipv6CidrBlock: "fd00:dead:beef:100::/64"
    routeTables:
      public:
        - name: my-network-public
          id: rtb-pub
      private:
        - name: my-network-private-rt-a
          id: rtb-priv-a
          availabilityZone: us-east-1a
    natGateways:
      - name: my-network-nat-a
        id: nat-abc123
        availabilityZone: us-east-1a
    internetGateway:
      id: igw-abc123
    egressOnlyInternetGateway:
      id: eigw-abc123
    transitGatewayAttachment:
      id: tgw-attach-abc123
      ready: true
```

## License

Apache-2.0
