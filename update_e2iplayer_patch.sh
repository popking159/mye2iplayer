#!/bin/sh
# ============================================================
#  E2iPlayer Patch Updater by M. Nasr
# ============================================================
#  - Checks for IPTVPlayer installation
#  - Downloads and extracts patch
#  - Adds or updates hosts
#  - Updates aliases.txt, list.txt, and hostgroups.txt (Arabic)
# ============================================================
##setup command=wget -q "--no-check-certificate" https://github.com/popking159/mye2iplayer/raw/main/update_e2iplayer_patch.sh -O - | /bin/sh
# ============================================================
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/IPTVPlayer"
TMP_FILE="/tmp/mnasr_e2iplayer_patch.tar.gz"
HOSTS_DIR="$PLUGIN_DIR/hosts"

# --------------------------
# 1️⃣ Edit this section only
# --------------------------
NEW_HOSTS_NAMES="hosttopcinema hosttuktukcam hostarabseed"
NEW_HOSTS_ALIAS="
'hosttopcinema': 'https://topcinema.buzz/',
'hosttuktukcam': 'https://tuk.cam/',
'hostarabseed': 'https://a.asd.homes/',
"
# --------------------------

# Step 1: Check plugin folder
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "❌ IPTVPlayer folder not found at: $PLUGIN_DIR"
    echo "Aborting update."
    exit 1
fi
echo "✅ Found IPTVPlayer at: $PLUGIN_DIR"

# Step 2: Download patch
echo "⬇️  Downloading patch file..."
wget -q -O "$TMP_FILE" "https://github.com/popking159/mye2iplayer/raw/refs/heads/main/mnasr_e2iplayer_patch.tar.gz"
if [ $? -ne 0 ]; then
    echo "❌ Download failed. Please check your connection."
    exit 1
fi
echo "✅ Patch downloaded."

# Step 3: Extract patch
echo "📦 Extracting patch..."
tar -xzf "$TMP_FILE" -C /
if [ $? -ne 0 ]; then
    echo "❌ Extraction failed."
    rm -f "$TMP_FILE"
    exit 1
fi
rm -f "$TMP_FILE"
echo "✅ Extraction done."

# Step 4: Add or update host files
echo "🔧 Checking host files..."
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

# Step 5: Update aliases.txt, list.txt, and hostgroups.txt
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

echo "📝 Updating aliases.txt..."
for line in $(echo "$NEW_HOSTS_ALIAS" | tr ',' '\n'); do
    host=$(echo "$line" | grep -o "'host[^']*'" | tr -d "'")
    if [ -n "$host" ] && ! grep -q "$host" "$ALIASES_FILE"; then
        sed -i "/^{/a $line," "$ALIASES_FILE"
    fi
done
echo "✅ aliases.txt updated."

echo "📝 Updating list.txt..."
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
    fi
done
echo "✅ list.txt updated."

# Step 6: Update Arabic section in hostgroups.txt neatly
echo "📝 Updating Arabic section in hostgroups.txt..."
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "\"$host\"" "$GROUPS_FILE"; then
        # Insert each host as a new line under "arabic"
        sed -i "/\"arabic\"[[:space:]]*:/,/]/ {
            /]/ i\    \"$host\",
        }" "$GROUPS_FILE"
    fi
done
echo "✅ hostgroups.txt updated (Arabic section)."

echo ""
echo "🎉 All updates completed successfully!"
echo "Your IPTVPlayer hosts are now up to date."
echo "------------------------------------------------------------"
