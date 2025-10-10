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
# 1️⃣ Edit this section only
# --------------------------
# host files (these are the file names under hosts/, keep the "host" prefix)
NEW_HOSTS_NAMES="hosttopcinema hosttuktukcam hostarabseed"

# manual aliases mapping (write them exactly as you want them to appear in aliases.txt)
# one entry per line, keep trailing comma if you want it to be separated (script will insert lines as-is)
NEW_HOSTS_ALIAS="
'hosttopcinema': 'https://topcinema.buzz/',
'hosttuktukcam': 'https://tuk.cam/',
'hostarabseed': 'https://a.asd.homes/',
"

# lines to add into urlparser.py under self.hostMap = {
# write them exactly as you want them inserted (trailing comma recommended)
URLPARSER_LINES="
'pqham.com': self.pp.parserJWPLAYER,
'mivalyo.com': self.pp.parserJWPLAYER,
'vidshare.space': self.pp.parserJWPLAYER
"
# --------------------------

echo "============================================================" > "$LOG_FILE"
echo " E2iPlayer Patch Update Log - $(date)" >> "$LOG_FILE"
echo "============================================================" >> "$LOG_FILE"

# helper to backup file with timestamp
backup_file() {
    f="$1"
    if [ -f "$f" ]; then
        cp -a "$f" "${f}.bak.$(date +%s)"
        echo "Backup: $f -> ${f}.bak.$(date +%s)" | tee -a "$LOG_FILE"
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

# Step 5: Update aliases.txt (line-by-line) and list.txt
ALIASES_FILE="$HOSTS_DIR/aliases.txt"
LIST_FILE="$HOSTS_DIR/list.txt"
GROUPS_FILE="$HOSTS_DIR/hostgroups.txt"

# Back up before editing
backup_file "$ALIASES_FILE"
backup_file "$LIST_FILE"
backup_file "$GROUPS_FILE"

echo "📝 Updating aliases.txt..." | tee -a "$LOG_FILE"
# iterate alias lines preserving formatting
echo "$NEW_HOSTS_ALIAS" | sed '/^[[:space:]]*$/d' | while IFS= read -r line; do
    # extract host key like hosttopcinema
    hostkey=$(echo "$line" | sed -n "s/^[[:space:]]*'\([^']*\)'.*/\1/p")
    if [ -n "$hostkey" ] && ! grep -qF "'$hostkey':" "$ALIASES_FILE"; then
        # insert after the opening '{' line
        sed -i "/^{/a $line" "$ALIASES_FILE"
        echo "➕ Added alias for $hostkey" | tee -a "$LOG_FILE"
    else
        echo "ℹ️  Alias already exists or could not parse: $line" | tee -a "$LOG_FILE"
    fi
done
echo "✅ aliases.txt updated." | tee -a "$LOG_FILE"

echo "📝 Updating list.txt..." | tee -a "$LOG_FILE"
for host in $NEW_HOSTS_NAMES; do
    if ! grep -q "^$host$" "$LIST_FILE"; then
        echo "$host" >> "$LIST_FILE"
        echo "➕ Added $host to list.txt" | tee -a "$LOG_FILE"
    else
        echo "ℹ️  $host already in list.txt" | tee -a "$LOG_FILE"
    fi
done
echo "✅ list.txt updated." | tee -a "$LOG_FILE"

# Step 6: Update Arabic section in hostgroups.txt (preserve indentation & avoid trailing comma)
if [ -f "$GROUPS_FILE" ]; then
    echo "📝 Updating Arabic section in hostgroups.txt..." | tee -a "$LOG_FILE"
    # backup already made above

    # find the line number for "arabic"
    ln_start=$(grep -n "\"arabic\"" "$GROUPS_FILE" | head -n1 | cut -d: -f1)
    if [ -z "$ln_start" ]; then
        echo "⚠️  Could not find \"arabic\" section in $GROUPS_FILE" | tee -a "$LOG_FILE"
    else
        # find the closing bracket ']' after arabic start
        ln_end=$(awk "NR>$ln_start && /^\s*]/ {print NR; exit}" "$GROUPS_FILE")
        if [ -z "$ln_end" ]; then
            echo "⚠️  Could not find closing ']' for Arabic section; skipping modification." | tee -a "$LOG_FILE"
        else
            # extract current items (one per line, without quotes)
            current_items=$(sed -n "$((ln_start+1)),$((ln_end-1))p" "$GROUPS_FILE" | sed -n 's/^[[:space:]]*"\(.*\)".*/\1/p')

            # build the combined list (original order, then append new ones)
            combined=""
            # keep original order
            for item in $(echo "$current_items"); do
                # empty-check (sed may produce empty lines)
                if [ -n "$item" ]; then
                    combined="$combined
$item"
                fi
            done

            # append new short names (host prefix removed) if not present
            for host in $NEW_HOSTS_NAMES; do
                short_name=$(echo "$host" | sed 's/^host//')
                # check exact match
                if ! echo "$combined" | grep -x -q "$short_name"; then
                    combined="$combined
$short_name"
                    echo "➕ Will add $short_name to Arabic category" | tee -a "$LOG_FILE"
                else
                    echo "ℹ️  $short_name already in Arabic category" | tee -a "$LOG_FILE"
                fi
            done

            # write a new file: header (up to ln_start), new items, then rest (from ln_end)
            tmpf="$(mktemp)"
            head -n "$ln_start" "$GROUPS_FILE" > "$tmpf"

            # print combined items with proper commas (no trailing comma after last)
            # clean combined (remove leading empty line)
            cleaned=$(echo "$combined" | sed '/^[[:space:]]*$/d')
            total=$(echo "$cleaned" | sed -n '1,$p' | wc -l | tr -d ' ')
            idx=0
            echo "$cleaned" | sed -n '1,$p' | while IFS= read -r it; do
                idx=$((idx+1))
                if [ -z "$it" ]; then
                    continue
                fi
                if [ "$idx" -lt "$total" ]; then
                    printf "  \"%s\",\n" "$it" >> "$tmpf"
                else
                    printf "  \"%s\"\n" "$it" >> "$tmpf"
                fi
            done

            # append rest of file starting from ln_end (the closing bracket line and everything after)
            tail -n +"$ln_end" "$GROUPS_FILE" >> "$tmpf"

            # replace file atomically
            mv "$tmpf" "$GROUPS_FILE"
            echo "✅ hostgroups.txt updated (Arabic section)." | tee -a "$LOG_FILE"
        fi
    fi
else
    echo "⚠️  hostgroups.txt not found at: $GROUPS_FILE" | tee -a "$LOG_FILE"
fi

# Step 7: Update urlparser.py hostMap (insert lines immediately after the self.hostMap = { line)
if [ -f "$URLPARSER_FILE" ]; then
    echo "🧩 Updating urlparser.py hostMap section..." | tee -a "$LOG_FILE"
    # backup
    backup_file "$URLPARSER_FILE"

    # find the first line number that contains hostMap (broad match)
    map_ln=$(grep -n "hostMap" "$URLPARSER_FILE" | head -n1 | cut -d: -f1)
    if [ -z "$map_ln" ]; then
        echo "⚠️  Could not find a hostMap assignment in $URLPARSER_FILE; skipping urlparser update." | tee -a "$LOG_FILE"
    else
        # We will insert lines AFTER map_ln. To preserve user order, insert lines in reverse
        tmp_lines="$(mktemp)"
        echo "$URLPARSER_LINES" | sed '/^[[:space:]]*$/d' > "$tmp_lines"

        # reverse the lines then insert one-by-one after map_ln
        awk ' { a[NR]=$0 } END { for(i=NR;i>=1;i--) print a[i] }' "$tmp_lines" | while IFS= read -r ins_line; do
            # extract domain key (the thing inside first quotes)
            domain=$(echo "$ins_line" | sed -n "s/^[[:space:]]*'\([^']*\)'.*/\1/p")
            if [ -z "$domain" ]; then
                echo "⚠️  Could not parse urlparser line: $ins_line" | tee -a "$LOG_FILE"
                continue
            fi

            # check if domain already exists (match the key exactly)
            if grep -qF "'$domain':" "$URLPARSER_FILE"; then
                echo "ℹ️  $domain already exists in urlparser.py; skipping" | tee -a "$LOG_FILE"
            else
                # insert after map_ln (we always insert after the original map_ln so final order matches original order)
                # use a safe sed append (with newline); the line will be inserted directly after the 'self.hostMap' line
                sed -i "${map_ln}a\\
${ins_line}" "$URLPARSER_FILE"
                echo "➕ Inserted $domain into urlparser.py" | tee -a "$LOG_FILE"
            fi
        done
        rm -f "$tmp_lines"
        echo "✅ urlparser.py updated (if any new domains were present)." | tee -a "$LOG_FILE"
    fi
else
    echo "⚠️  urlparser.py not found at expected path: $URLPARSER_FILE" | tee -a "$LOG_FILE"
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
