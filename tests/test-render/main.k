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

    # Test: nat.enabled=true with SingleAz creates exactly 1 NAT gateway (with observed VPC)
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
            # Provide observed VPC so NAT can render
            observedResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata = {
                        name = "test-single-nat"
                        annotations = {"crossplane.io/composition-resource-name" = "vpc"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "vpc-test123", cidrBlock = "10.0.0.0/16"}
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "InternetGateway"
                    metadata = {
                        name = "test-single-nat"
                        annotations = {"crossplane.io/composition-resource-name" = "internet-gateway"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "igw-test123"}
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata = {
                        name = "test-single-nat-public-a"
                        annotations = {"crossplane.io/composition-resource-name" = "subnet-public-a"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "subnet-publica123", cidrBlock = "10.0.0.0/24", availabilityZone = "us-east-1a"}
                    }
                }
            ]
            # SingleAz = exactly 1 NAT, 1 EIP (in first AZ only)
            assertResources = [
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "NATGateway", metadata.name = "test-single-nat-nat-a"}
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "EIP", metadata.name = "test-single-nat-nat-eip-a"}
            ]
        }
    },

    # Test: nat.strategy=HighlyAvailable creates NAT per AZ (with observed VPC)
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
            # Provide observed VPC so NAT can render
            observedResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata = {
                        name = "test-ha-nat"
                        annotations = {"crossplane.io/composition-resource-name" = "vpc"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "vpc-test123", cidrBlock = "10.0.0.0/16"}
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "InternetGateway"
                    metadata = {
                        name = "test-ha-nat"
                        annotations = {"crossplane.io/composition-resource-name" = "internet-gateway"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "igw-test123"}
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata = {
                        name = "test-ha-nat-public-a"
                        annotations = {"crossplane.io/composition-resource-name" = "subnet-public-a"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "subnet-publica123", cidrBlock = "10.0.0.0/24", availabilityZone = "us-east-1a"}
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata = {
                        name = "test-ha-nat-public-b"
                        annotations = {"crossplane.io/composition-resource-name" = "subnet-public-b"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {id = "subnet-publicb123", cidrBlock = "10.0.1.0/24", availabilityZone = "us-east-1b"}
                    }
                }
            ]
            # HighlyAvailable = NAT + EIP in each AZ
            assertResources = [
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "NATGateway", metadata.name = "test-ha-nat-nat-a"}
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "NATGateway", metadata.name = "test-ha-nat-nat-b"}
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "EIP", metadata.name = "test-ha-nat-nat-eip-a"}
                {apiVersion = "ec2.aws.m.upbound.io/v1beta1", kind = "EIP", metadata.name = "test-ha-nat-nat-eip-b"}
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
    },

    # -------------------------------------------------------------------------
    # SubnetLayout CIDR Math Tests
    # Tests verify the automatic CIDR calculation from VPC CIDR + subnetLayout
    # -------------------------------------------------------------------------

    # Test: 3 AZ layout calculates correct public subnet CIDRs (/24)
    # Public: {octet1}.{octet2}.{azIndex}.0/24
    # AZ a (index 0) -> 10.0.0.0/24
    # AZ b (index 1) -> 10.0.1.0/24
    # AZ c (index 2) -> 10.0.2.0/24
    metav1alpha1.CompositionTest {
        metadata.name = "layout-3az-public-cidr-math"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-3az"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b", "c"]
                    }
                }
            }
            assertResources = [
                # Public subnets: index 0, 1, 2 -> third octet 0, 1, 2
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-3az-public-a"
                    spec.forProvider.cidrBlock = "10.0.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-3az-public-b"
                    spec.forProvider.cidrBlock = "10.0.1.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-3az-public-c"
                    spec.forProvider.cidrBlock = "10.0.2.0/24"
                }
            ]
        }
    },

    # Test: 3 AZ layout calculates correct private subnet CIDRs (/20)
    # Private: {octet1}.{octet2}.{(azIndex+1)*16}.0/20
    # AZ a (index 0) -> (0+1)*16 = 16 -> 10.0.16.0/20
    # AZ b (index 1) -> (1+1)*16 = 32 -> 10.0.32.0/20
    # AZ c (index 2) -> (2+1)*16 = 48 -> 10.0.48.0/20
    metav1alpha1.CompositionTest {
        metadata.name = "layout-3az-private-cidr-math"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-private"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b", "c"]
                    }
                }
            }
            assertResources = [
                # Private subnets: (index+1)*16 -> third octet 16, 32, 48
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-private-private-a"
                    spec.forProvider.cidrBlock = "10.0.16.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-private-private-b"
                    spec.forProvider.cidrBlock = "10.0.32.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-private-private-c"
                    spec.forProvider.cidrBlock = "10.0.48.0/20"
                }
            ]
        }
    },

    # Test: Different VPC base CIDR (172.16.0.0/16) - verifies octet parsing
    metav1alpha1.CompositionTest {
        metadata.name = "layout-different-vpc-cidr-172"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-172"
                spec = {
                    region = "us-west-2"
                    vpc = {cidr = "172.16.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            assertResources = [
                # VPC uses 172.16.x.x range
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-172-public-a"
                    spec.forProvider.cidrBlock = "172.16.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-172-public-b"
                    spec.forProvider.cidrBlock = "172.16.1.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-172-private-a"
                    spec.forProvider.cidrBlock = "172.16.16.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-172-private-b"
                    spec.forProvider.cidrBlock = "172.16.32.0/20"
                }
            ]
        }
    },

    # Test: Different VPC base CIDR (10.100.0.0/16) - verifies second octet preserved
    metav1alpha1.CompositionTest {
        metadata.name = "layout-different-vpc-cidr-10-100"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-10-100"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.100.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b", "c"]
                    }
                }
            }
            assertResources = [
                # Second octet (100) should be preserved
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-10-100-public-a"
                    spec.forProvider.cidrBlock = "10.100.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-10-100-private-a"
                    spec.forProvider.cidrBlock = "10.100.16.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-10-100-private-c"
                    spec.forProvider.cidrBlock = "10.100.48.0/20"
                }
            ]
        }
    },

    # Test: 2 AZ layout calculates correct CIDRs
    metav1alpha1.CompositionTest {
        metadata.name = "layout-2az-cidr-math"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-2az"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            assertResources = [
                # Only 2 AZs
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-2az-public-a"
                    spec.forProvider.cidrBlock = "10.0.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-2az-public-b"
                    spec.forProvider.cidrBlock = "10.0.1.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-2az-private-a"
                    spec.forProvider.cidrBlock = "10.0.16.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-2az-private-b"
                    spec.forProvider.cidrBlock = "10.0.32.0/20"
                }
            ]
        }
    },

    # Test: 4 AZ layout calculates correct CIDRs
    # AZ d (index 3) -> public: 10.0.3.0/24, private: (3+1)*16 = 64 -> 10.0.64.0/20
    metav1alpha1.CompositionTest {
        metadata.name = "layout-4az-cidr-math"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-4az"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b", "c", "d"]
                    }
                }
            }
            assertResources = [
                # 4th AZ (d) index 3
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-4az-public-d"
                    spec.forProvider.cidrBlock = "10.0.3.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-4az-private-d"
                    spec.forProvider.cidrBlock = "10.0.64.0/20"
                }
                # Also verify earlier AZs are correct
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-4az-public-a"
                    spec.forProvider.cidrBlock = "10.0.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-4az-private-c"
                    spec.forProvider.cidrBlock = "10.0.48.0/20"
                }
            ]
        }
    },

    # Test: Public-only layout (no private subnets)
    metav1alpha1.CompositionTest {
        metadata.name = "layout-public-only"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-public"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = False}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            assertResources = [
                # Only public subnets should render
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-public-public-a"
                    spec.forProvider.cidrBlock = "10.0.0.0/24"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-public-public-b"
                    spec.forProvider.cidrBlock = "10.0.1.0/24"
                }
            ]
        }
    },

    # Test: Private-only layout (no public subnets)
    metav1alpha1.CompositionTest {
        metadata.name = "layout-private-only"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-priv"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = False}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            assertResources = [
                # Only private subnets should render
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-priv-private-a"
                    spec.forProvider.cidrBlock = "10.0.16.0/20"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-priv-private-b"
                    spec.forProvider.cidrBlock = "10.0.32.0/20"
                }
            ]
        }
    },

    # Test: IPv6 ULA CIDR calculation with subnetLayout
    # When VPC has IPv6 CIDR observed, subnets should get ipv6CidrBlock set
    # Template uses: printf "%s%d::/64" (trimSuffix "::" $ipv6Base) $azIndex
    # For fd00:100:0::/56 -> fd00:100:00::/64, fd00:100:01::/64, etc.
    metav1alpha1.CompositionTest {
        metadata.name = "layout-ipv6-ula-cidr-math"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-layout-ipv6"
                spec = {
                    region = "us-east-1"
                    vpc = {
                        cidr = "10.0.0.0/16"
                        ipv6 = {ula = {enabled = True, cidr = "fd00:100:0::/56"}}
                    }
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            # Provide observed VPC with IPv6 CIDR so subnet IPv6 can render
            observedResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata = {
                        name = "test-layout-ipv6"
                        annotations = {"crossplane.io/composition-resource-name" = "vpc"}
                    }
                    status = {
                        conditions = [{type = "Ready", status = "True"}, {type = "Synced", status = "True"}]
                        atProvider = {
                            id = "vpc-test123"
                            cidrBlock = "10.0.0.0/16"
                            ipv6CidrBlock = "fd00:100:0::/56"
                        }
                    }
                }
            ]
            # Verify subnets get IPv6 CIDRs calculated from VPC IPv6 CIDR
            # Template: trimSuffix "::" "fd00:100:0::" = "fd00:100:0"
            # Public index 0: fd00:100:00::/64, index 1: fd00:100:01::/64
            # Private index 2: fd00:100:02::/64, index 3: fd00:100:03::/64
            assertResources = [
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-ipv6-public-a"
                    spec.forProvider.ipv6CidrBlock = "fd00:100:00::/64"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-ipv6-public-b"
                    spec.forProvider.ipv6CidrBlock = "fd00:100:01::/64"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-ipv6-private-a"
                    spec.forProvider.ipv6CidrBlock = "fd00:100:02::/64"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-layout-ipv6-private-b"
                    spec.forProvider.ipv6CidrBlock = "fd00:100:03::/64"
                }
            ]
        }
    },

    # Test: Subnet names follow pattern {network}-{tier}-{az}
    metav1alpha1.CompositionTest {
        metadata.name = "layout-subnet-naming-convention"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "my-network"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "b"]
                    }
                }
            }
            assertResources = [
                # Names follow {network-name}-{tier}-{az} pattern
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "my-network-public-a"
                    spec.forProvider.tags.Name = "my-network-public-a"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "my-network-private-b"
                    spec.forProvider.tags.Name = "my-network-private-b"
                }
            ]
        }
    },

    # Test: Subnet AZ is fully qualified (region + suffix)
    metav1alpha1.CompositionTest {
        metadata.name = "layout-subnet-az-fully-qualified"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-az-fq"
                spec = {
                    region = "eu-west-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a", "c"]
                    }
                }
            }
            assertResources = [
                # AZ should be eu-west-1a, not just "a"
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-az-fq-public-a"
                    spec.forProvider.availabilityZone = "eu-west-1a"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-az-fq-public-c"
                    spec.forProvider.availabilityZone = "eu-west-1c"
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-az-fq-private-a"
                    spec.forProvider.availabilityZone = "eu-west-1a"
                }
            ]
        }
    },

    # Test: Subnet tier tags are correctly set
    metav1alpha1.CompositionTest {
        metadata.name = "layout-subnet-tier-tags"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-tier-tags"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a"]
                    }
                }
            }
            assertResources = [
                # Public subnet gets public tier tag and elb role
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-tier-tags-public-a"
                    spec.forProvider.tags = {
                        "hops.ops.com.ai/tier" = "public"
                        "kubernetes.io/role/elb" = "1"
                    }
                }
                # Private subnet gets private tier tag and internal-elb role
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-tier-tags-private-a"
                    spec.forProvider.tags = {
                        "hops.ops.com.ai/tier" = "private"
                        "kubernetes.io/role/internal-elb" = "1"
                    }
                }
            ]
        }
    },

    # Test: Public subnets have mapPublicIpOnLaunch = true
    metav1alpha1.CompositionTest {
        metadata.name = "layout-public-map-ip-on-launch"
        spec = {
            compositionPath = "apis/networks/composition.yaml"
            xrdPath = "apis/networks/definition.yaml"
            timeoutSeconds = 60
            validate = True
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "Network"
                metadata.name = "test-map-ip"
                spec = {
                    region = "us-east-1"
                    vpc = {cidr = "10.0.0.0/16"}
                    subnetLayout = {
                        public = {enabled = True, netmaskLength = 24}
                        private = {enabled = True, netmaskLength = 20}
                        availabilityZones = ["a"]
                    }
                }
            }
            assertResources = [
                # Public subnet maps public IP
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-map-ip-public-a"
                    spec.forProvider.mapPublicIpOnLaunch = True
                }
                # Private subnet does not map public IP
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "Subnet"
                    metadata.name = "test-map-ip-private-a"
                    spec.forProvider.mapPublicIpOnLaunch = False
                }
            ]
        }
    }
]

items = _items
