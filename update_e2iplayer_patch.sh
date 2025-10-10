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
LOG_FILE="/tmp/update_e2iplayer_patch.log"

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

echo "============================================================" > "$LOG_FILE"
echo " E2iPlayer Patch Update Log - $(date)" >> "$LOG_FILE"
echo "============================================================" >> "$LOG_FILE"

# Step 1: Check plugin folder
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "❌ IPTVPlayer folder not found at: $PLUGIN_DIR"
    echo "Aborting update." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Found IPTVPlayer at: $PLUGIN_DIR" | tee -a "$LOG_FILE"

# Step 2: Download patch
echo "⬇️  Downloading patch file..." | tee -a "$LOG_FILE"
wget -q -O "$TMP_FILE" "https://github.com/popking159/mye2iplayer/raw/refs/heads/main/mnasr_e2iplayer_patch.tar.gz"
if [ $? -ne 0 ]; then
    echo "❌ Download failed. Please check your connection." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Patch downloaded." | tee -a "$LOG_FILE"

# Step 3: Extract patch
echo "📦 Extracting patch..." | tee -a "$LOG_FILE"
tar -xzf "$TMP_FILE" -C /
if [ $? -ne 0 ]; then
    echo "❌ Extraction failed." | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi
rm -f "$TMP_FILE"
echo "✅ Extraction done." | tee -a "$LOG_FILE"

# Step 4: Add or update host files
echo "🔧 Checking host files..." | tee -a "$LOG_FILE"
ADDED=""
UPDATED=""
FAILED=""
for host in $NEW_HOSTS_NAMES; do
    host_file="$HOSTS_DIR/${host}.py"
    url="https://raw.githubusercontent.com/popking159/mye2iplayer/refs/heads/main/${host}.py"

    if [ -f "$host_file" ]; then
        echo "🔁 Updating existing host: $host" | tee -a "$LOG_FILE"
        UPDATED="$UPDATED $host"
    else
        echo "🆕 Adding new host: $host" | tee -a "$LOG_FILE"
        ADDED="$ADDED $host"
    fi

    wget -q -O "$host_file" "$url"
    if [ $? -eq 0 ]; then
        echo "✅ $host file downloaded successfully." | tee -a "$LOG_FILE"
    else
        echo "⚠️  Failed to download $host from $url" | tee -a "$LOG_FILE"
        FAILED="$FAILED $host"
    fi
done

# Step 5: Update aliases.txt, list.txt, and hostgroups.txt
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

echo "📝 Updating aliases.txt..." | tee -a "$LOG_FILE"
for line in $(echo "$NEW_HOSTS_ALIAS" | tr ',' '\n'); do
    host=$(echo "$line" | grep -o "'host[^']*'" | tr -d "'")
    if [ -n "$host" ] && ! grep -q "$host" "$ALIASES_FILE"; then
        sed -i "/^{/a $line," "$ALIASES_FILE"
        echo "➕ Added alias for $host" | tee -a "$LOG_FILE"
    fi
done
echo "✅ aliases.txt updated." | tee -a "$LOG_FILE"

echo "📝 Updating list.txt..." | tee -a "$LOG_FILE"
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "$host" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
        echo "➕ Added $host to list.txt" | tee -a "$LOG_FILE"
    fi
done
echo "✅ list.txt updated." | tee -a "$LOG_FILE"

# Step 6: Update Arabic section neatly
echo "📝 Updating Arabic section in hostgroups.txt..." | tee -a "$LOG_FILE"
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "\"$host\"" "$GROUPS_FILE"; then
        sed -i "/\"arabic\"[[:space:]]*:/,/]/ {
            /]/ i\    \"$host\",
        }" "$GROUPS_FILE"
        echo "➕ Added $host to Arabic category" | tee -a "$LOG_FILE"
    fi
done
echo "✅ hostgroups.txt updated (Arabic section)." | tee -a "$LOG_FILE"

# Step 7: Summary
echo "" | tee -a "$LOG_FILE"
echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "📋 Summary:" | tee -a "$LOG_FILE"
[ -n "$ADDED" ]   && echo "🆕 Added hosts:   $ADDED"   | tee -a "$LOG_FILE"
[ -n "$UPDATED" ] && echo "🔁 Updated hosts: $UPDATED" | tee -a "$LOG_FILE"
[ -n "$FAILED" ]  && echo "⚠️  Failed hosts:  $FAILED"  | tee -a "$LOG_FILE"
echo "------------------------------------------------------------" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "🎉 All updates completed successfully!" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
echo "------------------------------------------------------------"
