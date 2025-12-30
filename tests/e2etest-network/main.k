import base64
import datetime
import file
import math
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

_now = str(int(math.floor(datetime.ticks())))

_creds = file.read("secrets/aws-creds")
_base64_creds = base64.encode(_creds)

# =============================================================================
# Persistent infrastructure - update these if re-creating the test environment
# =============================================================================
#
# IPAM Pools and Scopes - persistent infrastructure from aws-ipam e2e test
# To get scope IDs, run:
#   aws ec2 describe-ipam-scopes --query 'IpamScopes[*].[IpamScopeId,IpamScopeType]' --output table
#
# Per-network child pools require scopeId when subnetPool.enabled is true
_ipam_private_scope_id = "ipam-scope-0ba795a6462cbb518"  # Private scope for IPv4 and IPv6 ULA

_ipv4_private_pool_id = "ipam-pool-0607416fa3707147a"
_ipv6_private_pool_id = "ipam-pool-0769c239ba0259975"

# =============================================================================
# Dynamic test resources - timestamped to allow concurrent test runs
# =============================================================================
_test_network_name = "e2etest-network-" + _now

_items = [
    metav1alpha1.E2ETest{
        metadata.name: ""
        spec: {
            crossplane.autoUpgrade.channel: "Rapid"
            defaultConditions: ["Ready"]
            manifests: [
                # Network XR - uses untyped dict to avoid KCL schema issues with pass-through fields
                {
                    apiVersion: "aws.hops.ops.com.ai/v1alpha1"
                    kind: "Network"
                    metadata: {
                        name: _test_network_name
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
                        # Use networkAllocations to auto-allocate CIDRs from IPAM
                        networkAllocations: {
                            ipv4: {
                                enabled: True
                                regionalPoolId: _ipv4_private_pool_id
                                scopeId: _ipam_private_scope_id
                                vpc: {
                                    netmaskLength: 16
                                }
                                subnets: {
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
                            }
                            ipv6Ula: {
                                enabled: True
                                regionalPoolId: _ipv6_private_pool_id
                                scopeId: _ipam_private_scope_id
                                vpc: {
                                    netmaskLength: 48
                                }
                                subnets: {
                                    availabilityZones: ["a", "b"]
                                    public: {
                                        enabled: True
                                        netmaskLength: 64
                                    }
                                    private: {
                                        enabled: True
                                        netmaskLength: 64
                                    }
                                }
                            }
                        }
                        # No NAT gateway (costs money) - use IPv6 egress-only IGW instead
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
            timeoutSeconds: 1200  # 20 minutes - dual-stack VPC with public/private subnets
        }
    }
]
items = _items
