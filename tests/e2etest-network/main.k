# e2etest-network - AWS Network E2E Test
# =======================================
# Tests network creation with IPAM and optional import cycle.
#
# Import Cycle Testing:
# 1. First run: Create network with empty externalNames (creates new resources)
# 2. Get resource IDs after creation (see commands below)
# 3. Update externalNames + set managementPolicies to orphan (remove Delete)
# 4. Run again to verify import works
# 5. Delete claim - resources are orphaned in AWS
#
# Per-Resource managementPolicies:
# - Top-level managementPolicies is the default for all resources
# - Each resource type can override with its own managementPolicies:
#   - vpc.managementPolicies, internetGateway.managementPolicies
#   - subnetLayout.managementPolicies, routeTables.managementPolicies
#   - nat.managementPolicies, egressOnlyInternetGateway.managementPolicies
#
# Get resource IDs after first run:
#   kubectl get vpc e2etest-network -o jsonpath='{.status.atProvider.id}'
#   kubectl get internetgateway e2etest-network -o jsonpath='{.status.atProvider.id}'
#   kubectl get egressonlyinternetgateway e2etest-network -o jsonpath='{.status.atProvider.id}'
#   kubectl get subnet -l crossplane.io/composite=e2etest-network \
#     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.atProvider.id}{"\n"}{end}'
#   kubectl get routetable -l crossplane.io/composite=e2etest-network \
#     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.atProvider.id}{"\n"}{end}'
#   kubectl get routetableassociation -l crossplane.io/composite=e2etest-network \
#     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.atProvider.id}{"\n"}{end}'

import base64
import file
import datetime
import math
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.ai.com.ops.hops.aws.v1alpha1 as hops

_creds = file.read("secrets/aws-creds")
_base64_creds = base64.encode(_creds)

# =============================================================================
# Persistent infrastructure - update these if re-creating the test environment
# =============================================================================
# IPAM Pools - from aws-ipam e2e test
# Get pool IDs: aws ec2 describe-ipam-pools --query 'IpamPools[*].[IpamPoolId,AddressFamily,Description]' --output table
_ipv4_private_pool_id = "ipam-pool-0607416fa3707147a"
_ipv6_private_pool_id = "ipam-pool-0ca730678e463dbfc"

# Orphan policy - no Delete means resources persist in AWS after claim deletion
_orphan = ["Create", "Observe", "Update", "LateInitialize"]

# External names for import (leave empty for create, populate for import)
# VPC: vpc-08b36c3876f7483c6
_vpc_external_name = "vpc-08b36c3876f7483c6"

# Internet Gateway: igw-03a2b57e7564cda9f
_igw_external_name = "igw-03a2b57e7564cda9f"

# Egress-Only Internet Gateway: eigw-0509f3b2bd1be9138
_eigw_external_name = "eigw-0509f3b2bd1be9138"

# Subnets
_subnet_external_names = {
    "private-b": "subnet-0cbb443a464822732"
    "public-c": "subnet-057c84f314a39d68d"
    "public-a": "subnet-02ff76c2c4176f37f"
    "private-c": "subnet-00973c5fd791f6037"
    "private-a": "subnet-0020e9ba5ee42afee"
    "public-b": "subnet-07b28779d3b08cb9f"
}

# Route Tables
_route_table_external_names = {
    "private-a": "rtb-06f5dfc79be8adde5"
    "public": "rtb-0ab0e4783e8f1f95c"
    "private-c": "rtb-099239ef54186f902"
    "private-b": "rtb-091712a660e70b8c8"
}

# Route Table Associations
_rta_external_names = {
    "private-a": "rtbassoc-06f73a87e5e6aa1e3"
    "public-b": "rtbassoc-04fda70b1c1b457a0"
    "public-c": "rtbassoc-0ebd2d46928315951"
    "public-a": "rtbassoc-0b77df963c53e1207"
    "private-c": "rtbassoc-001ec41949a17ebdc"
    "private-b": "rtbassoc-09ec129f2661a33c7"
}

# NAT Gateways
_nat_external_names = {}
_eip_external_names = {}

# =============================================================================
# Test Network
# =============================================================================
_test_network_name = "e2etest-network"

_now = str(int(math.floor(datetime.ticks())))

_ephemeral_test_network_name = _test_network_name + "-" + _now

_items = [
    metav1alpha1.E2ETest{
        metadata.name: ""
        spec: {
            crossplane.autoUpgrade.channel: "Rapid"
            defaultConditions: ["Ready"]
            manifests: [
                hops.Network{
                    metadata: {
                        name: _ephemeral_test_network_name
                        namespace: "default"
                    }
                    spec: {
                        providerConfigRef: {
                            name: "default"
                        }
                        region: "us-east-2"
                        tags: {
                            "e2etest": "true"
                            "test-run": _now
                        }
                        # Use IPAM to auto-allocate VPC CIDRs
                        ipam: {
                            ipv4: {
                                enabled: True
                                poolId: _ipv4_private_pool_id
                                netmaskLength: 16
                            }
                            ipv6Ula: {
                                enabled: True
                                poolId: _ipv6_private_pool_id
                                netmaskLength: 56  # AWS requires /56 for VPC IPv6
                            }
                        }
                        # Subnet layout - CIDRs calculated from VPC CIDR
                        subnetLayout: {
                            availabilityZones: ["a", "b"]
                            public: {
                                enabled: True
                                netmaskLength: 24
                            }
                            private: {
                                enabled: True
                                netmaskLength: 20
                            }
                        }
                        # No NAT gateway (costs money) - use IPv6 egress-only IGW instead
                        nat: {
                            enabled: False
                        }
                    }
                },
                hops.Network{
                    metadata: {
                        name: _test_network_name
                        namespace: "default"
                    }
                    spec: {
                        managementPolicies: _orphan
                        providerConfigRef: {
                            name: "default"
                        }
                        region: "us-east-2"
                        tags: {
                            "e2etest": "true"
                            "hops.ops.com.ai/managed": "true"
                        }
                        vpc: {
                            if _vpc_external_name:
                                externalName: _vpc_external_name
                            managementPolicies: _orphan
                        }
                        internetGateway: {
                            if _igw_external_name:
                                externalName: _igw_external_name
                            managementPolicies: _orphan
                        }
                        egressOnlyInternetGateway: {
                            if _eigw_external_name:
                                externalName: _eigw_external_name
                            managementPolicies: _orphan
                        }
                        # Use IPAM to auto-allocate VPC CIDRs
                        ipam: {
                            ipv4: {
                                enabled: True
                                poolId: _ipv4_private_pool_id
                                netmaskLength: 16
                            }
                            ipv6Ula: {
                                enabled: True
                                poolId: _ipv6_private_pool_id
                                netmaskLength: 56
                            }
                        }
                        subnetLayout: {
                            availabilityZones: ["a", "b"]
                            public: {
                                enabled: True
                                netmaskLength: 24
                            }
                            private: {
                                enabled: True
                                netmaskLength: 20
                            }
                            if _subnet_external_names:
                                externalNames: _subnet_external_names
                            managementPolicies: _orphan
                        }
                        routeTables: {
                            if _route_table_external_names:
                                externalNames: _route_table_external_names
                            if _rta_external_names:
                                associationExternalNames: _rta_external_names
                            managementPolicies: _orphan
                        }
                        # No NAT gateway (costs money)
                        nat: {
                            enabled: False
                        }
                    }
                }
            ]
            extraResources: [
                {
                    apiVersion: "v1"
                    kind: "Secret"
                    metadata: {
                        name: "aws-creds"
                        namespace: "default"
                    }
                    data: {
                        creds: _base64_creds
                    }
                },
                {
                    apiVersion: "aws.m.upbound.io/v1beta1"
                    kind: "ProviderConfig"
                    metadata: {
                        name: "default"
                        namespace: "default"
                    }
                    spec: {
                        credentials: {
                            source: "Secret"
                            secretRef: {
                                namespace: "default"
                                name: "aws-creds"
                                key: "creds"
                            }
                        }
                    }
                }
            ]
            skipDelete: False
            timeoutSeconds: 1200  # 20 minutes
        }
    }
]
items = _items
