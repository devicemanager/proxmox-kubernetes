#!/bin/bash
# Investigate Debian cloud images

echo "=== Investigating Debian Cloud Images ==="

# Check what's available for Debian 13 (Trixie)
echo "Checking Debian cloud image sources..."

# Official Debian cloud images
echo -e "\n1. Official Debian Cloud Images:"
echo "   https://cloud.debian.org/"
echo "   https://cdimage.debian.org/images/cloud/"

# Check current testing/trixie status
curl -s https://cloud.debian.org/images/cloud/ | grep -i "trixie\|testing" || echo "No trixie found in main directory"

# Check testing directory
echo -e "\n2. Debian Testing (Trixie) Cloud Images:"
curl -s https://cloud.debian.org/images/cloud/testing/ | grep -E "href|daily" | head -10

# The correct URL structure for Debian cloud images
echo -e "\n3. Correct Debian Cloud Image URLs:"
echo "   Daily builds: https://cloud.debian.org/images/cloud/trixie/daily/"
echo "   Latest: https://cloud.debian.org/images/cloud/trixie/latest/"
