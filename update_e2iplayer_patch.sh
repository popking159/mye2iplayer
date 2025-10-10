#!/bin/sh
# ============================================================
#  E2iPlayer Patch Updater by M. Nasr
# ============================================================
#  - Checks for IPTVPlayer installation
#  - Downloads and extracts patch
#  - Updates or installs new hosts automatically
#  - Updates aliases.txt, list.txt, and hostgroups.txt
# ============================================================
##setup command=wget -q "--no-check-certificate" https://github.com/popking159/mye2iplayer/raw/main/update_e2iplayer_patch.sh -O - | /bin/sh
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/IPTVPlayer"
TMP_FILE="/tmp/mnasr_e2iplayer_patch.tar.gz"
HOSTS_DIR="$PLUGIN_DIR/hosts"

# --------------------------
# EDIT THIS LINE ONLY
# --------------------------
NEW_HOSTS_NAMES="hosttopcinema hosttuktukcam hostarabseed"
# --------------------------

# Automatically generate alias URLs and JSON list
NEW_HOSTS_ALIAS=""
NEW_HOSTS_JSON=""
for host in $NEW_HOSTS_NAMES; do
    site=$(echo "$host" | sed 's/^host//')
    NEW_HOSTS_ALIAS="${NEW_HOSTS_ALIAS}'${host}': 'https://${site}.com/',\n"
    if [ -z "$NEW_HOSTS_JSON" ]; then
        NEW_HOSTS_JSON="\"${host}\""
    else
        NEW_HOSTS_JSON="${NEW_HOSTS_JSON}, \"${host}\""
    fi
done

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
wget -q -O "$TMP_FILE" "https://github.com/popking159/mye2iplayer/raw/refs/heads/main/mnasr_e2iplayer_patch.tar.gz"
if [ $? -ne 0 ]; then
    echo "❌ Download failed. Please check your connection or URL."
    exit 1
fi
echo "✅ Patch downloaded."

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
rm -f "$TMP_FILE"
echo "✅ Extraction done and cleaned."

# --------------------------
# Step 4: Update or add host files
# --------------------------
echo "🔧 Checking and updating host files..."
for host in $NEW_HOSTS_NAMES; do
    host_file="$HOSTS_DIR/${host}.py"
    url="https://raw.githubusercontent.com/popking159/mye2iplayer/refs/heads/main/${host}.py"

    if [ -f "$host_file" ]; then
        echo "🔁 Updating existing host: $host"
    else
        echo "🆕 Adding new host: $host"
    fi

    wget -q -O "$host_file" "$url"
    if [ $? -eq 0 ]; then
        echo "✅ $host file updated successfully."
    else
        echo "⚠️  Failed to download $host from $url"
    fi
done

# --------------------------
# Step 5: Update host metadata files
# --------------------------
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

echo "📝 Updating aliases.txt, list.txt, and hostgroups.txt..."

# Update aliases.txt
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$ALIASES_FILE"; then
        echo "Adding alias for $host"
        sed -i "/^{/a '${host}': 'https://${host#host}.com/'," "$ALIASES_FILE"
    fi
done

# Update list.txt
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
    fi
done

# Update hostgroups.txt (arabic category)
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$GROUPS_FILE"; then
        sed -i "/\"arabic\"[[:space:]]*:/,/]/ s/]/, \"${host}\"]/" "$GROUPS_FILE"
    fi
done

echo ""
echo "🎉 All updates completed successfully!"
echo "✅ New or updated hosts are now active in IPTVPlayer."
echo "------------------------------------------------------------"
