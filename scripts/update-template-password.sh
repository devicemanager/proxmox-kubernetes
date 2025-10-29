#!/bin/bash
# Update existing template with root password

TEMPLATE_ID="9000"
ROOT_PASSWORD='$y$j9T$eHbdTPK0hVFCjdHhTew7S.$nf/NOyA8YPNXsMFWbJEyfLOyHlqqhjjPkrCYW7qGZJ4'

# Source secrets from .env
if [ -f .env ]; then
    source .env
fi

echo "Updating template ${TEMPLATE_ID} with root password..."

ssh root@192.168.20.40 << EOF
# Check if template exists
if ! qm status ${TEMPLATE_ID} &>/dev/null; then
    echo "Error: Template ${TEMPLATE_ID} not found!"
    exit 1
fi

# Convert template back to VM temporarily
echo "Converting template to VM..."
qm set ${TEMPLATE_ID} --template 0

# Set the cloud-init password
echo "Setting root password..."
qm set ${TEMPLATE_ID} --cipassword "${ROOT_PASSWORD}"

# Convert back to template
echo "Converting back to template..."
qm template ${TEMPLATE_ID}

echo "Template updated successfully!"
echo "Root password is now set for console access"
EOF
