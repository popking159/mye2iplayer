#!/bin/sh
# ============================================================
#  E2iPlayer Patch Updater by M. Nasr
# ============================================================
#  - Checks for IPTVPlayer installation
#  - Downloads and extracts patch
#  - Adds or updates hosts
#  - Updates aliases.txt, list.txt, and hostgroups.txt (Arabic)
#  - Updates urlparser.py hostMap section
#  - Works with CRLF/LF endings and keeps files sorted
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

# Host → domain mapping for aliases.txt
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

# --------------------------
# Helper functions
# --------------------------

backup_file() {
    f="$1"
    [ -f "$f" ] || return
    cp -a "$f" "${f}.bak.$(date +%s)"
    echo "📦 Backup created: ${f}.bak.$(date +%s)" | tee -a "$LOG_FILE"
}

normalize_file() {
    f="$1"
    [ -f "$f" ] || return

    # Fix CRLF → LF and remove trailing spaces
    sed -i 's/\r$//' "$f"
    sed -i 's/[[:space:]]\+$//' "$f"

    # Remove empty lines at the start
    sed -i '/./,$!d' "$f"

    # Ensure final newline
    sed -i -e '$a\' "$f"
}

sort_list_file() {
    f="$1"
    normalize_file "$f"

    # Remove blank lines and sort alphabetically (unique)
    grep -v '^[[:space:]]*$' "$f" | sort -u > "${f}.tmp"
    mv "${f}.tmp" "$f"

    # Remove blank lines again just in case
    sed -i '/^[[:space:]]*$/d' "$f"

    # Ensure no leading blank lines
    sed -i '/./,$!d' "$f"
}

sort_aliases_file() {
    f="$1"
    normalize_file "$f"

    # Clean header/footer and sort dictionary body
    awk '
        BEGIN { inblock=0 }
        /^\{/ { print; inblock=1; next }
        /^\}/ { close("sort"); inblock=0; print; next }
        inblock { print | "sort" }
        !inblock && !/^[{}]/ { print }
    ' "$f" > "${f}.tmp"

    mv "${f}.tmp" "$f"

    # Ensure file starts directly with '{'
    sed -i '/./,$!d' "$f"
}

sort_arabic_group() {
    f="$1"
    normalize_file "$f"
    ln_start=$(grep -n "\"arabic\"" "$f" | head -n1 | cut -d: -f1)
    [ -z "$ln_start" ] && return
    ln_end=$(awk "NR>$ln_start && /^\s*]/ {print NR; exit}" "$f")
    [ -z "$ln_end" ] && return

    # Build a temp file with the sorted Arabic section
    head -n "$ln_start" "$f" > "${f}.tmp"

    # Extract, clean, and sort all entries inside "arabic": [
    entries=$(sed -n "$((ln_start+1)),$((ln_end-1))p" "$f" | \
        sed -n 's/^[[:space:]]*"\(.*\)".*/\1/p' | sort -u)

    # Write each line with commas except for the last
    total=$(echo "$entries" | wc -l | tr -d ' ')
    idx=0
    echo "$entries" | while IFS= read -r h; do
        idx=$((idx+1))
        [ -z "$h" ] && continue
        if [ "$idx" -lt "$total" ]; then
            echo "  \"$h\"," >> "${f}.tmp"
        else
            echo "  \"$h\"" >> "${f}.tmp"
        fi
    done

    # Append the rest of the file
    tail -n +"$ln_end" "$f" >> "${f}.tmp"

    # Replace atomically
    mv "${f}.tmp" "$f"

    # Normalize and clean again
    normalize_file "$f"

    echo "✅ Arabic group sorted and last comma removed." | tee -a "$LOG_FILE"
}

# --------------------------
# 2️⃣ Begin process
# --------------------------

# Step 1: Check plugin folder
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "❌ IPTVPlayer folder not found at: $PLUGIN_DIR" | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Found IPTVPlayer at: $PLUGIN_DIR" | tee -a "$LOG_FILE"

# Step 2: Download patch
echo "⬇️  Downloading patch file..." | tee -a "$LOG_FILE"
wget -q -O "$TMP_FILE" "https://github.com/popking159/mye2iplayer/raw/refs/heads/main/mnasr_e2iplayer_patch.tar.gz"
if [ $? -ne 0 ]; then
    echo "❌ Download failed." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✅ Patch downloaded." | tee -a "$LOG_FILE"

# Step 3: Extract patch
echo "📦 Extracting patch..." | tee -a "$LOG_FILE"
tar -xzf "$TMP_FILE" -C /
rm -f "$TMP_FILE"
echo "✅ Extraction done." | tee -a "$LOG_FILE"

# Step 4: Add or update host files
echo "🔧 Checking host files..." | tee -a "$LOG_FILE"
for host in $NEW_HOSTS_NAMES; do
    host_file="$HOSTS_DIR/${host}.py"
    url="https://raw.githubusercontent.com/popking159/mye2iplayer/refs/heads/main/${host}.py"
    if wget -q -O "$host_file" "$url"; then
        echo "✅ Updated $host" | tee -a "$LOG_FILE"
    else
        echo "⚠️  Failed to download $host" | tee -a "$LOG_FILE"
    fi
done

# Step 5: Update aliases.txt and list.txt
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

backup_file "$ALIASES_FILE"
backup_file "$LIST_FILE"
backup_file "$GROUPS_FILE"

# aliases.txt
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

# list.txt
echo "📝 Updating list.txt..." | tee -a "$LOG_FILE"
normalize_file "$LIST_FILE"
for host in $NEW_HOSTS_NAMES; do
    clean_host=$(echo "$host" | tr -d '\r' | xargs)
    if grep -xqF "$clean_host" "$LIST_FILE"; then
        echo "ℹ️  $clean_host already exists in list.txt — skipping" | tee -a "$LOG_FILE"
    else
        echo "$clean_host" >> "$LIST_FILE"
        echo "➕ Added $clean_host to list.txt" | tee -a "$LOG_FILE"
    fi
done
sort_list_file "$LIST_FILE"
echo "✅ list.txt updated safely (sorted)." | tee -a "$LOG_FILE"

# Step 6: Update Arabic section in hostgroups.txt
if [ -f "$GROUPS_FILE" ]; then
    echo "📝 Updating Arabic section in hostgroups.txt..." | tee -a "$LOG_FILE"
    for host in $NEW_HOSTS_NAMES; do
        short=$(echo "$host" | sed 's/^host//')
        if ! grep -q "\"$short\"" "$GROUPS_FILE"; then
            sed -i "/\"arabic\"[[:space:]]*:[[:space:]]*\[/a\  \"$short\"," "$GROUPS_FILE"
            echo "➕ Inserted $short under Arabic category" | tee -a "$LOG_FILE"
        else
            echo "ℹ️  $short already exists in Arabic section" | tee -a "$LOG_FILE"
        fi
    done
    sort_arabic_group "$GROUPS_FILE"
    echo "✅ hostgroups.txt updated and sorted (Arabic section)." | tee -a "$LOG_FILE"
else
    echo "⚠️  hostgroups.txt not found at: $GROUPS_FILE" | tee -a "$LOG_FILE"
fi

# Step 7: Update urlparser.py hostMap
if [ -f "$URLPARSER_FILE" ]; then
    echo "🧩 Updating urlparser.py hostMap section..." | tee -a "$LOG_FILE"
    backup_file "$URLPARSER_FILE"
    map_ln=$(grep -n "self\.hostMap[[:space:]]*=" "$URLPARSER_FILE" | head -n1 | cut -d: -f1)
    if [ -n "$map_ln" ]; then
        echo "$URLPARSER_LINES" | sed '/^[[:space:]]*$/d' | while IFS= read -r line; do
            domain=$(echo "$line" | sed -n "s/^[[:space:]]*'\([^']*\)'.*/\1/p")
            [ -z "$domain" ] && continue
            if grep -qF "'$domain':" "$URLPARSER_FILE"; then
                echo "ℹ️  $domain already exists in urlparser.py" | tee -a "$LOG_FILE"
            else
                formatted_line=$(echo "$line" | sed 's/,\{0,1\}$/,/' )
                sed -i "${map_ln}a\            ${formatted_line}" "$URLPARSER_FILE"
                echo "➕ Added $domain to urlparser.py" | tee -a "$LOG_FILE"
            fi
        done
        normalize_file "$URLPARSER_FILE"
        echo "✅ urlparser.py updated (with indentation + commas)." | tee -a "$LOG_FILE"
    else
        echo "⚠️  hostMap section not found; skipped urlparser update." | tee -a "$LOG_FILE"
    fi
else
    echo "⚠️  urlparser.py not found at: $URLPARSER_FILE" | tee -a "$LOG_FILE"
fi

# Step 8: Final cleanup and sorting
echo "🧹 Normalizing and sorting files..." | tee -a "$LOG_FILE"
normalize_file "$ALIASES_FILE"
normalize_file "$LIST_FILE"
normalize_file "$GROUPS_FILE"
sort_aliases_file "$ALIASES_FILE"
sort_list_file "$LIST_FILE"
sort_arabic_group "$GROUPS_FILE"
echo "✅ All files normalized and alphabetically sorted." | tee -a "$LOG_FILE"

# Step 9: Summary
echo "" | tee -a "$LOG_FILE"
echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
echo "🎉 Update completed successfully!" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "------------------------------------------------------------"
