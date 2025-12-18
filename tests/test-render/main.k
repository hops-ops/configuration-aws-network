import dev.meta.v1 as meta

# Test minimal network rendering
test_network_minimal = meta.CompositionTest {
    metadata.name = "test-network-minimal"
    spec = {
        compositionPath = "../../apis/networks/composition.yaml"
        xrPath = "../../examples/networks/example-minimal.yaml"
        timeoutSeconds = 60
        assertResources = [
            # VPC should be created with IPAM pool selector
            {
                name = "vpc"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "VPC"
                    metadata.name = "my-vpc-vpc"
                    spec = {
                        forProvider = {
                            region = "us-east-1"
                            enableDnsHostnames = True
                            enableDnsSupport = True
                        }
                        providerConfigRef.name = "my-cluster"
                    }
                }
            }
            # Public subnet should be created
            {
                name = "subnet-public-a"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "Subnet"
                    spec = {
                        forProvider = {
                            region = "us-east-1"
                            mapPublicIpOnLaunch = True
                        }
                    }
                }
            }
            # Private subnet should be created
            {
                name = "subnet-private-a"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "Subnet"
                    spec = {
                        forProvider = {
                            region = "us-east-1"
                            mapPublicIpOnLaunch = False
                        }
                    }
                }
            }
            # Internet Gateway should be created
            {
                name = "internet-gateway"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "InternetGateway"
                }
            }
            # NAT Gateway should be created (SingleAz strategy)
            {
                name = "nat-a"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "NATGateway"
                }
            }
        ]
    }
}

# Test private-only network (no public subnets, no NAT)
test_network_private_only = meta.CompositionTest {
    metadata.name = "test-network-private-only"
    spec = {
        compositionPath = "../../apis/networks/composition.yaml"
        xrPath = "../../examples/networks/example-private-only.yaml"
        timeoutSeconds = 60
        assertResources = [
            # VPC should be created
            {
                name = "vpc"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "VPC"
                }
            }
            # Private subnet should be created
            {
                name = "subnet-private-a"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "Subnet"
                    spec = {
                        forProvider = {
                            mapPublicIpOnLaunch = False
                        }
                    }
                }
            }
        ]
        # These should NOT exist for private-only
        assertNotExist = [
            "internet-gateway"
            "nat-a"
            "subnet-public-a"
        ]
    }
}

# Test dual-stack network
test_network_dual_stack = meta.CompositionTest {
    metadata.name = "test-network-dual-stack"
    spec = {
        compositionPath = "../../apis/networks/composition.yaml"
        xrPath = "../../examples/networks/example-dual-stack.yaml"
        timeoutSeconds = 60
        assertResources = [
            # VPC should be created
            {
                name = "vpc"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "VPC"
                }
            }
            # IPv6 CIDR association should be created
            {
                name = "vpc-ipv6-cidr"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "VPCIpv6CIDRBlockAssociation"
                    spec = {
                        forProvider = {
                            amazonProvidedIpv6CidrBlock = True
                        }
                    }
                }
            }
            # Egress-only IGW should be created for IPv6 private subnets
            {
                name = "egress-only-igw"
                resource = {
                    apiVersion = "ec2.aws.upbound.io/v1beta1"
                    kind = "EgressOnlyInternetGateway"
                }
            }
        ]
    }
}
