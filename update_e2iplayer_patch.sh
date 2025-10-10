#!/bin/sh
# ============================================================
#  E2iPlayer Patch Updater by M. Nasr
# ============================================================
#  - Checks for IPTVPlayer installation
#  - Downloads and extracts patch
#  - Adds or updates hosts
#  - Updates aliases.txt, list.txt, and hostgroups.txt (Arabic)
#  - Updates urlparser.py hostMap section (inserted lines)
# ============================================================
##setup command=wget -q "--no-check-certificate" https://github.com/popking159/mye2iplayer/raw/main/update_e2iplayer_patch.sh -O - | /bin/sh
# ============================================================
PLUGIN_DIR="/usr/lib/enigma2/python/Plugins/Extensions/IPTVPlayer"
TMP_FILE="/tmp/mnasr_e2iplayer_patch.tar.gz"
HOSTS_DIR="$PLUGIN_DIR/hosts"
LOG_FILE="/tmp/update_e2iplayer_patch.log"
URLPARSER_FILE="$PLUGIN_DIR/libs/urlparser.py"

# --------------------------
# 1️⃣ Edit these sections only
# --------------------------

# Hosts to update or add (with "host" prefix)
NEW_HOSTS_NAMES="hosttopcinema hosttuktukcam hostarabseed"

# Host → domain mapping for aliases.txt (edit here only)
HOSTS_DOMAINS="
hosttopcinema=https://topcinema.buzz/
hosttuktukcam=https://tuk.cam/
hostarabseed=https://a.asd.homes/
"

# Lines to add into urlparser.py under self.hostMap = {
URLPARSER_LINES="
'pqham.com': self.pp.parserJWPLAYER,
'mivalyo.com': self.pp.parserJWPLAYER,
'vidshare.space': self.pp.parserJWPLAYER
"
# --------------------------

echo "============================================================" > "$LOG_FILE"
echo " E2iPlayer Patch Update Log - $(date)" >> "$LOG_FILE"
echo "============================================================" >> "$LOG_FILE"

# Helper: backup file with timestamp
backup_file() {
    f="$1"
    if [ -f "$f" ]; then
        cp -a "$f" "${f}.bak.$(date +%s)"
        echo "📦 Backup created: ${f}.bak.$(date +%s)" | tee -a "$LOG_FILE"
    fi
}

# Step 1: Check plugin folder
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "❌ IPTVPlayer folder not found at: $PLUGIN_DIR" | tee -a "$LOG_FILE"
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

backup_file "$ALIASES_FILE"
backup_file "$LIST_FILE"
backup_file "$GROUPS_FILE"

echo "📝 Updating aliases.txt..." | tee -a "$LOG_FILE"
echo "$HOSTS_DOMAINS" | sed '/^[[:space:]]*$/d' | while IFS='=' read -r host domain; do
    [ -z "$host" ] && continue
    formatted="'$host': '$domain',"
    if ! grep -q "'$host':" "$ALIASES_FILE"; then
        sed -i "/^{/a $formatted" "$ALIASES_FILE"
        echo "➕ Added alias for $host → $domain" | tee -a "$LOG_FILE"
    else
        echo "ℹ️  Alias for $host already exists." | tee -a "$LOG_FILE"
    fi
done
echo "✅ aliases.txt updated." | tee -a "$LOG_FILE"

echo "📝 Updating list.txt..." | tee -a "$LOG_FILE"
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "^$host$" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
        echo "➕ Added $host to list.txt" | tee -a "$LOG_FILE"
    else
        echo "ℹ️  $host already exists in list.txt" | tee -a "$LOG_FILE"
    fi
done
echo "✅ list.txt updated." | tee -a "$LOG_FILE"

# Step 6: Update Arabic section in hostgroups.txt
if [ -f "$GROUPS_FILE" ]; then
    echo "📝 Updating Arabic section in hostgroups.txt..." | tee -a "$LOG_FILE"
    backup_file "$GROUPS_FILE"
    ln_start=$(grep -n "\"arabic\"" "$GROUPS_FILE" | head -n1 | cut -d: -f1)
    [ -z "$ln_start" ] && echo "⚠️  Arabic section not found!" | tee -a "$LOG_FILE" && exit 0
    ln_end=$(awk "NR>$ln_start && /^\s*]/ {print NR; exit}" "$GROUPS_FILE")

    tmpf="$(mktemp)"
    head -n "$ln_start" "$GROUPS_FILE" > "$tmpf"
    echo "" >> "$tmpf"

    # get current items
    current=$(sed -n "$((ln_start+1)),$((ln_end-1))p" "$GROUPS_FILE" | sed -n 's/^[[:space:]]*"\(.*\)".*/\1/p')

    combined="$current"
    for host in $NEW_HOSTS_NAMES; do
        short=$(echo "$host" | sed 's/^host//')
        if ! echo "$combined" | grep -x -q "$short"; then
            combined="$combined
$short"
            echo "➕ Added $short to Arabic category" | tee -a "$LOG_FILE"
        else
            echo "ℹ️  $short already exists in Arabic group" | tee -a "$LOG_FILE"
        fi
    done

    cleaned=$(echo "$combined" | sed '/^[[:space:]]*$/d')
    total=$(echo "$cleaned" | wc -l | tr -d ' ')
    idx=0
    echo "$cleaned" | while IFS= read -r it; do
        idx=$((idx+1))
        [ -z "$it" ] && continue
        if [ "$idx" -lt "$total" ]; then
            printf "  \"%s\",\n" "$it" >> "$tmpf"
        else
            printf "  \"%s\"\n" "$it" >> "$tmpf"
        fi
    done

    tail -n +"$ln_end" "$GROUPS_FILE" >> "$tmpf"
    mv "$tmpf" "$GROUPS_FILE"
    echo "✅ hostgroups.txt updated (Arabic section, no trailing comma)." | tee -a "$LOG_FILE"
else
    echo "⚠️  hostgroups.txt not found at: $GROUPS_FILE" | tee -a "$LOG_FILE"
fi

# Step 7: Update urlparser.py hostMap
if [ -f "$URLPARSER_FILE" ]; then
    echo "🧩 Updating urlparser.py hostMap section..." | tee -a "$LOG_FILE"
    backup_file "$URLPARSER_FILE"
    map_ln=$(grep -n "self\.hostMap[[:space:]]*=" "$URLPARSER_FILE" | head -n1 | cut -d: -f1)
    [ -z "$map_ln" ] && echo "⚠️  hostMap not found; skipping" | tee -a "$LOG_FILE" && exit 0

    echo "$URLPARSER_LINES" | sed '/^[[:space:]]*$/d' | while IFS= read -r line; do
        domain=$(echo "$line" | sed -n "s/^[[:space:]]*'\([^']*\)'.*/\1/p")
        [ -z "$domain" ] && continue
        if grep -qF "'$domain':" "$URLPARSER_FILE"; then
            echo "ℹ️  $domain already in urlparser.py" | tee -a "$LOG_FILE"
        else
            sed -i "${map_ln}a\    $line" "$URLPARSER_FILE"
            echo "➕ Added $domain → urlparser.py" | tee -a "$LOG_FILE"
        fi
    done
    echo "✅ urlparser.py updated." | tee -a "$LOG_FILE"
else
    echo "⚠️  urlparser.py not found at: $URLPARSER_FILE" | tee -a "$LOG_FILE"
fi

# Step 8: Summary
echo "" | tee -a "$LOG_FILE"
echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "📋 Summary:" | tee -a "$LOG_FILE"
[ -n "$ADDED" ]   && echo "🆕 Added hosts:   $ADDED"   | tee -a "$LOG_FILE"
[ -n "$UPDATED" ] && echo "🔁 Updated hosts: $UPDATED" | tee -a "$LOG_FILE"
[ -n "$FAILED" ]  && echo "⚠️  Failed hosts:  $FAILED"  | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "------------------------------------------------------------"
