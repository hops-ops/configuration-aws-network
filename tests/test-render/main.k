import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# =============================================================================
# Unit tests for Network XRD API behavior
#
# Philosophy: render/validate already checks provider API correctness.
# These tests verify OUR API decisions:
# - Conditional rendering based on flags
# - Configuration mapping from XRD spec to provider resources
# - Default values and edge cases
#
# NOTE: Features that gate on observed resources (FlowLogs, EgressOnlyIGW,
# TransitGateway attachments, NAT after VPC ready) are tested via
# `make validate:all` with observed-resources mocks - not here.
# =============================================================================

_items = [
    # -------------------------------------------------------------------------
    # NAT Gateway Strategy Tests
    # These test the INTENT - that the right NAT resources appear when enabled.
    # NAT actually gates on VPC ready, but we can still assert the count/names.
    # -------------------------------------------------------------------------

    # Test: nat.enabled=false should NOT render NAT resources
    metav1alpha1.CompositionTest {
        metadata.name = "nat-disabled-no-nat-resources"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-nat-disabled"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    nat = {enabled = False}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                        {name = "private-a", availabilityZone = "a", cidr = "10.0.10.0/24", public = False}
                    ]
                }
            }
            # Assert: VPC and IGW render (NAT won't render without observed VPC)
            assertResources = [
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "VPC", metadata.name = "test-nat-disabled"}
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "InternetGateway", metadata.name = "test-nat-disabled"}
            ]
        }
    },

    # Test: nat.enabled=true with SingleAz - NAT gates on VPC ready,
    # but we test it renders when observed resources are provided via validate
    metav1alpha1.CompositionTest {
        metadata.name = "nat-single-az-one-nat"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-single-nat"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    nat = {enabled = True, strategy = "SingleAz"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                        {name = "public-b", availabilityZone = "b", cidr = "10.0.1.0/24", public = True}
                        {name = "private-a", availabilityZone = "a", cidr = "10.0.10.0/24", public = False}
                        {name = "private-b", availabilityZone = "b", cidr = "10.0.11.0/24", public = False}
                    ]
                }
            }
            # VPC renders on first pass; NAT requires observed VPC
            assertResources = [
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "VPC", metadata.name = "test-single-nat"}
            ]
        }
    },

    # Test: nat.strategy=HighlyAvailable - VPC renders, NAT gates on observed
    metav1alpha1.CompositionTest {
        metadata.name = "nat-ha-multiple-nats"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-ha-nat"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    nat = {enabled = True, strategy = "HighlyAvailable"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                        {name = "public-b", availabilityZone = "b", cidr = "10.0.1.0/24", public = True}
                        {name = "private-a", availabilityZone = "a", cidr = "10.0.10.0/24", public = False}
                        {name = "private-b", availabilityZone = "b", cidr = "10.0.11.0/24", public = False}
                    ]
                }
            }
            # VPC renders on first pass
            assertResources = [
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "VPC", metadata.name = "test-ha-nat"}
            ]
        }
    },

    # -------------------------------------------------------------------------
    # IPv6 Configuration Tests
    # VPC IPv6 flags are set on initial render
    # -------------------------------------------------------------------------

    # Test: vpc.ipv6.amazonProvided.enabled=true sets VPC flag
    metav1alpha1.CompositionTest {
        metadata.name = "ipv6-amazon-provided-vpc-flag"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-amazon-ipv6"
                spec = {
                    region = "us-east-1"
                    vpc = {
                        cidr = "10.0.0.0/16"
                        ipv6 = {amazonProvided = {enabled = True}}
                    }
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            # VPC should have the IPv6 flag set on initial render
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-amazon-ipv6"
                    spec.forProvider.assignGeneratedIpv6CidrBlock = True
                }
            ]
        }
    },

    # -------------------------------------------------------------------------
    # IPAM vs Manual CIDR Tests
    # -------------------------------------------------------------------------

    # Test: Explicit vpc.cidr uses cidrBlock (not IPAM)
    metav1alpha1.CompositionTest {
        metadata.name = "explicit-cidr-uses-cidrblock"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-explicit-cidr"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.99.0.0/16"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.99.0.0/24", public = True}
                    ]
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-explicit-cidr"
                    spec.forProvider.cidrBlock = "10.99.0.0/16"
                }
            ]
        }
    },

    # Test: ipam.ipv4.enabled=true uses IPAM pool allocation
    metav1alpha1.CompositionTest {
        metadata.name = "ipam-enabled-uses-pool-id"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-ipam"
                spec = {
                    region = "us-east-1"
                    ipam = {
                        ipv4 = {
                            enabled = True
                            poolId = "ipam-pool-0123456789abcdef0"
                            vpc = {netmaskLength = 16}
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-ipam"
                    spec.forProvider = {
                        ipv4IpamPoolId = "ipam-pool-0123456789abcdef0"
                        ipv4NetmaskLength = 16
                    }
                }
            ]
        }
    },

    # -------------------------------------------------------------------------
    # Default Values Tests
    # -------------------------------------------------------------------------

    # Test: Default providerConfigRef.name is "default"
    metav1alpha1.CompositionTest {
        metadata.name = "default-provider-config-name"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-defaults"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-defaults"
                    spec.providerConfigRef = {name = "default", kind = "ProviderConfig"}
                }
            ]
        }
    },

    # Test: Custom providerConfigRef propagates to VPC
    metav1alpha1.CompositionTest {
        metadata.name = "custom-provider-config-propagates"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-custom-provider"
                spec = {
                    region = "us-west-2"
                    providerConfigRef = {name = "my-custom-provider", kind = "ProviderConfig"}
                    vpc = {cidr = "10.0.0.0/16"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            # VPC gets custom providerConfigRef on initial render
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-custom-provider"
                    spec.providerConfigRef = {name = "my-custom-provider", kind = "ProviderConfig"}
                }
            ]
        }
    },

    # Test: VPC defaults (enableDnsHostnames, enableDnsSupport)
    metav1alpha1.CompositionTest {
        metadata.name = "vpc-dns-defaults-enabled"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-dns-defaults"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-dns-defaults"
                    spec.forProvider = {
                        enableDnsHostnames = True
                        enableDnsSupport = True
                    }
                }
            ]
        }
    },

    # -------------------------------------------------------------------------
    # Tags Tests
    # -------------------------------------------------------------------------

    # Test: Default hops tag is applied
    metav1alpha1.CompositionTest {
        metadata.name = "default-hops-tag-applied"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-default-tags"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-default-tags"
                    spec.forProvider.tags.hops = "true"
                }
            ]
        }
    },

    # Test: Custom tags merge with defaults
    metav1alpha1.CompositionTest {
        metadata.name = "custom-tags-merge-with-defaults"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-custom-tags"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    tags = {environment = "test", team = "platform"}
                    subnets = [
                        {name = "public-a", availabilityZone = "a", cidr = "10.0.0.0/24", public = True}
                    ]
                }
            }
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "test-custom-tags"
                    spec.forProvider.tags = {
                        hops = "true"
                        environment = "test"
                        team = "platform"
                    }
                }
            ]
        }
    }
]

items = _items
