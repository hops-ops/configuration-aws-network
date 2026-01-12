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
_vpc_external_name = ""

# Internet Gateway: igw-03a2b57e7564cda9f
_igw_external_name = ""

# Egress-Only Internet Gateway: eigw-0509f3b2bd1be9138
_eigw_external_name = ""


_subnet_external_names = {}
_route_table_external_names = {}
_rta_external_names = {}
# # Subnets
# _subnet_external_names = {
#     "private-b": ""
#     "public-c": ""
#     "public-a": ""
#     "private-c": ""
#     "private-a": ""
#     "public-b": ""
# }

# # Route Tables
# _route_table_external_names = {
#     "private-a": ""
#     "public": ""
#     "private-c": ""
#     "private-b": ""
# }

# # Route Table Associations
# _rta_external_names = {
#     "private-a": ""
#     "public-b": ""
#     "public-c": ""
#     "public-a": ""
#     "private-c": ""
#     "private-b": ""
# }

# NAT Gateways
_nat_external_names = {}
_eip_external_names = {}

# =============================================================================
# Test Network
# =============================================================================
_test_network_name = "hops-test"

_now = str(int(math.floor(datetime.ticks())))

_ephemeral_test_network_name =  "e2etest-aws-network-ephemeral" + _now

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
                            "hops.ops.com.ai/test-repo": "https://github.com/hops-ops/aws-network"
                            "hops.ops.com.ai/test-run-time": _now
                            "hops.ops.com.ai/ephemeral": "true"
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
                            "hops.ops.com.ai/test-repo": "https://github.com/hops-ops/aws-network"
                            "hops.ops.com.ai/test-run-time": _now
                            "hops.ops.com.ai/persistent": "true"
                        }
                        vpc: {
                            if _vpc_external_name:
                                externalName: _vpc_external_name
                        }
                        internetGateway: {
                            if _igw_external_name:
                                externalName: _igw_external_name
                        }
                        egressOnlyInternetGateway: {
                            if _eigw_external_name:
                                externalName: _eigw_external_name
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
                        }
                        routeTables: {
                            if _route_table_external_names:
                                externalNames: _route_table_external_names
                            if _rta_external_names:
                                associationExternalNames: _rta_external_names
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
