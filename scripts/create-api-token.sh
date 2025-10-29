
# On Proxmox server, create API token for Terraform
TOKEN_OUTPUT=$(pveum user token add root@pam terraform --privsep=0)
echo "$TOKEN_OUTPUT"

# Extract token value and append to .env
TOKEN_ID=$(echo "$TOKEN_OUTPUT" | grep 'full-tokenid' | awk '{print $3}')
TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep 'value ' | awk '{print $3}')
if [ -n "$TOKEN_ID" ] && [ -n "$TOKEN_SECRET" ]; then
	echo "PROXMOX_API_TOKEN=\"$TOKEN_ID=$TOKEN_SECRET\"" >> .env
	echo "Appended PROXMOX_API_TOKEN to .env"
else
	echo "Could not extract token, please add manually to .env"
fi
