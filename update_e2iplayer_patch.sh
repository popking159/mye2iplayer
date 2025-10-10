#!/bin/sh
# ============================================================
#  E2iPlayer Patch Updater by M. Nasr
# ============================================================
#  This script updates the IPTVPlayer plugin by:
#   1. Checking for plugin folder existence
#   2. Downloading and extracting patch file
#   3. Adding new hosts to aliases.txt, list.txt, and hostgroups.txt
# ============================================================

PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/IPTVPlayer"
TMP_FILE="/tmp/mnasr_e2iplayer_patch.tar.gz"

# --------------------------
# New hosts to be added
# --------------------------
# Edit this section to add more hosts easily later
NEW_HOSTS_NAMES="host9anime hostaflaam"
NEW_HOSTS_ALIAS="
'host9anime': 'https://9anime.com.ro',
'hostaflaam': 'https://aflaam.com/',
"
NEW_HOSTS_JSON='"host9anime", "hostaflaam"'

# --------------------------
# Step 1: Check plugin folder
# --------------------------
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "❌ IPTVPlayer folder not found at: $PLUGIN_DIR"
    echo "Aborting update."
    exit 1
fi
echo "✅ Found IPTVPlayer at: $PLUGIN_DIR"

# --------------------------
# Step 2: Download patch
# --------------------------
echo "⬇️  Downloading patch file..."
wget -q -O "$TMP_FILE" "http://YOUR_SERVER/mnasr_e2iplayer_patch.tar.gz"
if [ $? -ne 0 ]; then
    echo "❌ Download failed. Please check your URL or connection."
    exit 1
fi
echo "✅ Download complete."

# --------------------------
# Step 3: Extract patch
# --------------------------
echo "📦 Extracting patch..."
tar -xzf "$TMP_FILE" -C /
if [ $? -ne 0 ]; then
    echo "❌ Extraction failed."
    rm -f "$TMP_FILE"
    exit 1
fi
echo "✅ Extraction successful."

# --------------------------
# Step 4: Clean up
# --------------------------
rm -f "$TMP_FILE"
echo "🧹 Temporary files cleaned."

# --------------------------
# Step 5: Update host files
# --------------------------
HOSTS_DIR="$PLUGIN_DIR/hosts"
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

echo "📝 Updating hosts files..."

# --- Update aliases.txt ---
if ! grep -q "host9anime" "$ALIASES_FILE"; then
    echo "🔧 Adding new aliases..."
    sed -i "/^{/a $NEW_HOSTS_ALIAS" "$ALIASES_FILE"
    echo "✅ aliases.txt updated."
else
    echo "ℹ️  Hosts already exist in aliases.txt"
fi

# --- Update list.txt ---
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
    fi
done
echo "✅ list.txt updated."

# --- Update hostgroups.txt ---
# Insert new hosts under "arabic" group
if ! grep -q "host9anime" "$GROUPS_FILE"; then
    echo "🔧 Updating Arabic category in hostgroups.txt..."
    sed -i "/\"arabic\"[[:space:]]*:/,/]/ s/]/, $NEW_HOSTS_JSON]/" "$GROUPS_FILE"
    echo "✅ hostgroups.txt updated."
else
    echo "ℹ️  Arabic group already contains these hosts."
fi

echo ""
echo "🎉 Update completed successfully!"
echo "Your IPTVPlayer is now patched and new hosts are available."
echo "------------------------------------------------------------"
