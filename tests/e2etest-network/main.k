import base64
import datetime
import file
import math
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.ai.com.ops.hops.aws.v1alpha1 as hops

_now = str(int(math.floor(datetime.ticks())))

_creds = file.read("secrets/aws-creds")
_base64_creds = base64.encode(_creds)

# =============================================================================
# Persistent infrastructure - update these if re-creating the test environment
# =============================================================================
#
# IPAM Pools - persistent infrastructure from aws-ipam e2e test
# To get pool IDs, run:
#   aws ec2 describe-ipam-pools --query 'IpamPools[*].[IpamPoolId,AddressFamily,Description]' --output table
#
_ipv4_private_pool_id = "ipam-pool-0607416fa3707147a"
_ipv6_private_pool_id = "ipam-pool-0ca730678e463dbfc"

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
                # Network XR - using typed model
                hops.Network{
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
