import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

_items = [
    # Test minimal network rendering
    metav1alpha1.CompositionTest {
        metadata.name: "test-network-minimal"
        spec: {
            compositionPath: "apis/networks/composition.yaml"
            xrPath: "examples/networks/minimal.yaml"
            xrdPath: "apis/networks/definition.yaml"
            timeoutSeconds: 60
            validate: True
            assertResources: [
                # VPC should be created
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "VPC"
                    metadata: {
                        name: "minimal"
                    }
                    spec: {
                        forProvider: {
                            region: "us-east-1"
                            cidrBlock: "10.1.0.0/16"
                            enableDnsHostnames: True
                            enableDnsSupport: True
                        }
                        providerConfigRef: {
                            name: "default"
                            kind: "ProviderConfig"
                        }
                    }
                }
                # Internet Gateway for public subnets
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "InternetGateway"
                    metadata: {
                        name: "minimal"
                    }
                }
                # Public route table
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "RouteTable"
                    metadata: {
                        name: "minimal-public"
                    }
                }
                # Private route tables
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "RouteTable"
                    metadata: {
                        name: "minimal-private-rt-a"
                    }
                }
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "RouteTable"
                    metadata: {
                        name: "minimal-private-rt-b"
                    }
                }
            ]
        }
    },
    # Test standard network with NAT
    metav1alpha1.CompositionTest {
        metadata.name: "test-network-standard"
        spec: {
            compositionPath: "apis/networks/composition.yaml"
            xrPath: "examples/networks/standard.yaml"
            xrdPath: "apis/networks/definition.yaml"
            timeoutSeconds: 60
            validate: True
            assertResources: [
                # VPC should be created
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "VPC"
                    metadata: {
                        name: "standard"
                    }
                    spec: {
                        forProvider: {
                            region: "us-east-1"
                            cidrBlock: "10.2.0.0/16"
                        }
                    }
                }
                # NAT Gateway (SingleAz)
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "NATGateway"
                    metadata: {
                        name: "standard-nat-a"
                    }
                }
                # EIP for NAT
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EIP"
                    metadata: {
                        name: "standard-nat-eip-a"
                    }
                }
            ]
        }
    },
    # Test dual-stack with ULA IPv6
    metav1alpha1.CompositionTest {
        metadata.name: "test-network-dual-stack-ula"
        spec: {
            compositionPath: "apis/networks/composition.yaml"
            xrPath: "examples/networks/dual-stack-ula.yaml"
            xrdPath: "apis/networks/definition.yaml"
            timeoutSeconds: 60
            validate: True
            assertResources: [
                # VPC
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "VPC"
                    metadata: {
                        name: "dual-stack"
                    }
                    spec: {
                        forProvider: {
                            cidrBlock: "10.3.0.0/16"
                        }
                    }
                }
                # Egress-only IGW for IPv6 private egress
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EgressOnlyInternetGateway"
                    metadata: {
                        name: "dual-stack"
                    }
                }
                # NAT Gateway
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "NATGateway"
                    metadata: {
                        name: "dual-stack-nat-a"
                    }
                }
            ]
        }
    },
    # Test dual-stack with Amazon-provided IPv6
    metav1alpha1.CompositionTest {
        metadata.name: "test-network-dual-stack-amazon"
        spec: {
            compositionPath: "apis/networks/composition.yaml"
            xrPath: "examples/networks/dual-stack-amazon.yaml"
            xrdPath: "apis/networks/definition.yaml"
            timeoutSeconds: 60
            validate: True
            assertResources: [
                # VPC with Amazon IPv6 enabled
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "VPC"
                    metadata: {
                        name: "dual-stack-amazon"
                    }
                    spec: {
                        forProvider: {
                            cidrBlock: "10.4.0.0/16"
                            assignGeneratedIpv6CidrBlock: True
                        }
                    }
                }
                # Egress-only IGW for IPv6 private egress
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EgressOnlyInternetGateway"
                    metadata: {
                        name: "dual-stack-amazon"
                    }
                }
            ]
        }
    },
    # Test high-availability network with HA NAT
    metav1alpha1.CompositionTest {
        metadata.name: "test-network-high-availability"
        spec: {
            compositionPath: "apis/networks/composition.yaml"
            xrPath: "examples/networks/high-availability.yaml"
            xrdPath: "apis/networks/definition.yaml"
            timeoutSeconds: 60
            validate: True
            assertResources: [
                # VPC
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "VPC"
                    metadata: {
                        name: "high-availability"
                    }
                    spec: {
                        forProvider: {
                            cidrBlock: "10.5.0.0/16"
                        }
                    }
                }
                # HA NAT (3 gateways for 3 AZs)
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "NATGateway"
                    metadata: {
                        name: "high-availability-nat-a"
                    }
                }
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "NATGateway"
                    metadata: {
                        name: "high-availability-nat-b"
                    }
                }
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "NATGateway"
                    metadata: {
                        name: "high-availability-nat-c"
                    }
                }
                # 3 EIPs for HA NAT
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EIP"
                    metadata: {
                        name: "high-availability-nat-eip-a"
                    }
                }
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EIP"
                    metadata: {
                        name: "high-availability-nat-eip-b"
                    }
                }
                {
                    apiVersion: "ec2.aws.m.upbound.io/v1beta1"
                    kind: "EIP"
                    metadata: {
                        name: "high-availability-nat-eip-c"
                    }
                }
            ]
        }
    }
]

items = _items
