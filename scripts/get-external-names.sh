#!/bin/bash
# get-external-names.sh - Extract AWS resource IDs for import
# Usage: ./scripts/get-external-names.sh <network-name> [region]
#
# Queries AWS for all resources associated with a network and outputs
# the external names in KCL format ready for the e2e test.

set -euo pipefail

NETWORK_NAME="${1:-}"
REGION="${2:-us-east-2}"

if [[ -z "$NETWORK_NAME" ]]; then
    echo "Usage: $0 <network-name> [region]"
    echo "Example: $0 e2etest-network us-east-2"
    exit 1
fi

echo "# Fetching AWS resources for network: $NETWORK_NAME in $REGION"
echo ""

# Find VPC by Name tag
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$NETWORK_NAME" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "None")

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
    echo "# ERROR: VPC not found with Name tag '$NETWORK_NAME'"
    exit 1
fi

echo "# VPC: $VPC_ID"
echo "_vpc_external_name = \"$VPC_ID\""
echo ""

# Find Internet Gateway attached to VPC
IGW_ID=$(aws ec2 describe-internet-gateways \
    --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text 2>/dev/null || echo "None")

if [[ "$IGW_ID" != "None" && -n "$IGW_ID" ]]; then
    echo "# Internet Gateway: $IGW_ID"
    echo "_igw_external_name = \"$IGW_ID\""
else
    echo "# No Internet Gateway found"
    echo "_igw_external_name = \"\""
fi
echo ""

# Find Egress-Only Internet Gateway
EIGW_ID=$(aws ec2 describe-egress-only-internet-gateways \
    --region "$REGION" \
    --query "EgressOnlyInternetGateways[?Attachments[?VpcId=='$VPC_ID']].EgressOnlyInternetGatewayId | [0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$EIGW_ID" != "None" && -n "$EIGW_ID" ]]; then
    echo "# Egress-Only Internet Gateway: $EIGW_ID"
    echo "_eigw_external_name = \"$EIGW_ID\""
else
    echo "# No Egress-Only Internet Gateway found"
    echo "_eigw_external_name = \"\""
fi
echo ""

# Find Subnets
echo "# Subnets"
echo "_subnet_external_names = {"

aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].[Tags[?Key==`Name`].Value | [0], SubnetId, AvailabilityZone, Tags[?Key==`hops.ops.com.ai/tier`].Value | [0]]' \
    --output text 2>/dev/null | while read -r name subnet_id az tier; do
    if [[ -n "$name" && -n "$subnet_id" ]]; then
        # Extract AZ suffix (last char)
        az_suffix="${az: -1}"
        # Build key from tier and az
        if [[ -n "$tier" ]]; then
            key="${tier}-${az_suffix}"
        else
            # Fallback: try to parse from name (e.g., network-public-a)
            if [[ "$name" =~ -public-([a-z])$ ]]; then
                key="public-${BASH_REMATCH[1]}"
            elif [[ "$name" =~ -private-([a-z])$ ]]; then
                key="private-${BASH_REMATCH[1]}"
            else
                key="unknown-${az_suffix}"
            fi
        fi
        echo "    \"$key\": \"$subnet_id\""
    fi
done

echo "}"
echo ""

# Find Route Tables
echo "# Route Tables"
echo "_route_table_external_names = {"

aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[*].[Tags[?Key==`Name`].Value | [0], RouteTableId, Tags[?Key==`hops.ops.com.ai/tier`].Value | [0], Tags[?Key==`hops.ops.com.ai/az`].Value | [0]]' \
    --output text 2>/dev/null | while read -r name rt_id tier az; do
    if [[ -n "$name" && -n "$rt_id" ]]; then
        # Skip main route table (no Name tag usually)
        if [[ "$name" == "None" ]]; then
            continue
        fi
        # Build key from tier and az
        if [[ "$tier" == "public" ]]; then
            key="public"
        elif [[ "$tier" == "private" && -n "$az" && "$az" != "None" ]]; then
            key="private-${az}"
        else
            # Fallback: try to parse from name
            if [[ "$name" =~ -public$ ]]; then
                key="public"
            elif [[ "$name" =~ -private-rt-([a-z])$ ]]; then
                key="private-${BASH_REMATCH[1]}"
            else
                continue
            fi
        fi
        echo "    \"$key\": \"$rt_id\""
    fi
done

echo "}"
echo ""

# Find Route Table Associations
echo "# Route Table Associations"
echo "_rta_external_names = {"

# Get all route tables with their associations
aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[*].Associations[?!Main].[RouteTableAssociationId, SubnetId]' \
    --output text 2>/dev/null | while read -r assoc_id subnet_id; do
    if [[ -n "$assoc_id" && -n "$subnet_id" && "$assoc_id" != "None" ]]; then
        # Look up subnet to get tier and az
        subnet_info=$(aws ec2 describe-subnets \
            --region "$REGION" \
            --subnet-ids "$subnet_id" \
            --query 'Subnets[0].[AvailabilityZone, Tags[?Key==`hops.ops.com.ai/tier`].Value | [0], Tags[?Key==`Name`].Value | [0]]' \
            --output text 2>/dev/null)

        az=$(echo "$subnet_info" | cut -f1)
        tier=$(echo "$subnet_info" | cut -f2)
        name=$(echo "$subnet_info" | cut -f3)

        az_suffix="${az: -1}"

        if [[ -n "$tier" && "$tier" != "None" ]]; then
            key="${tier}-${az_suffix}"
        elif [[ "$name" =~ -public-([a-z])$ ]]; then
            key="public-${BASH_REMATCH[1]}"
        elif [[ "$name" =~ -private-([a-z])$ ]]; then
            key="private-${BASH_REMATCH[1]}"
        else
            key="unknown-${az_suffix}"
        fi

        echo "    \"$key\": \"$assoc_id\""
    fi
done

echo "}"
echo ""

# Find NAT Gateways
echo "# NAT Gateways"
NAT_COUNT=$(aws ec2 describe-nat-gateways \
    --region "$REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
    --query 'length(NatGateways)' \
    --output text 2>/dev/null || echo "0")

if [[ "$NAT_COUNT" -gt 0 ]]; then
    echo "_nat_external_names = {"

    aws ec2 describe-nat-gateways \
        --region "$REGION" \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'NatGateways[*].[NatGatewayId, SubnetId]' \
        --output text 2>/dev/null | while read -r nat_id subnet_id; do
        if [[ -n "$nat_id" && -n "$subnet_id" ]]; then
            # Get subnet AZ
            az=$(aws ec2 describe-subnets \
                --region "$REGION" \
                --subnet-ids "$subnet_id" \
                --query 'Subnets[0].AvailabilityZone' \
                --output text 2>/dev/null)
            az_suffix="${az: -1}"
            echo "    \"$az_suffix\": \"$nat_id\""
        fi
    done

    echo "}"
    echo ""

    # Find EIPs associated with NAT Gateways
    echo "_eip_external_names = {"

    aws ec2 describe-nat-gateways \
        --region "$REGION" \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'NatGateways[*].[NatGatewayAddresses[0].AllocationId, SubnetId]' \
        --output text 2>/dev/null | while read -r alloc_id subnet_id; do
        if [[ -n "$alloc_id" && -n "$subnet_id" && "$alloc_id" != "None" ]]; then
            # Get subnet AZ
            az=$(aws ec2 describe-subnets \
                --region "$REGION" \
                --subnet-ids "$subnet_id" \
                --query 'Subnets[0].AvailabilityZone' \
                --output text 2>/dev/null)
            az_suffix="${az: -1}"
            echo "    \"$az_suffix\": \"$alloc_id\""
        fi
    done

    echo "}"
else
    echo "# No NAT Gateways found"
    echo "_nat_external_names = {}"
    echo "_eip_external_names = {}"
fi
echo ""

echo "# Done! Copy the above into your e2e test file."
