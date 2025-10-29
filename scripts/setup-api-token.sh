#!/bin/bash
# Create API token for Terraform

echo "Creating Terraform API user and token..."

ssh root@192.168.20.40 << 'EOF'
# Create user
pveum user add terraform@pve-5 -comment "Terraform automation user"

# Set permissions
pveum aclmod / -user terraform@pve-5 -role Administrator

# Create token
TOKEN_OUTPUT=$(pveum user token add terraform@pve-5 terraform -privsep 0 -expire 0)
echo ""
echo "=== SAVE THIS TOKEN ==="
echo "$TOKEN_OUTPUT"
echo "====================="
echo ""
echo "Add to terraform.tfvars:"
echo 'api_token = "terraform@pve-5!terraform=<token-value>"'
EOF

TOKEN_ID=$(echo "$TOKEN_OUTPUT" | grep 'full-tokenid' | awk '{print $3}')
TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep 'value ' | awk '{print $3}')
if [ -n "$TOKEN_ID" ] && [ -n "$TOKEN_SECRET" ]; then
	echo "PROXMOX_API_TOKEN=\"$TOKEN_ID=$TOKEN_SECRET\"" >> .env
	echo "Appended PROXMOX_API_TOKEN to .env"
else
	echo "Could not extract token, please add manually to .env"
fi
echo "Add to terraform.tfvars:"
echo "api_token = \"$TOKEN_ID=$TOKEN_SECRET\""
