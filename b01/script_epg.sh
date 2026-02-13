#!/bin/bash

# --- Configuration ---
EPG_LIST="epg.txt"
CHOIX_FILE="choix.txt"
VARS_FILE="variables.txt"
OUTPUT_FILE="epg_final.xml"
TEMP_DIR="./temp_epg"

# Nettoyage et création du dossier temporaire
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Lecture des variables avec valeurs par défaut
[[ -f $VARS_FILE ]] && source $VARS_FILE
DAYS_BEFORE=${jours_avant:-1}
DAYS_AFTER=${jours_venir:-2}

# Calcul des bornes temporelles
START_LIMIT=$(date -d "$DAYS_BEFORE days ago 00:00:00" +"%Y%m%d%H%M%S")
END_LIMIT=$(date -d "$DAYS_AFTER days 23:59:59" +"%Y%m%d%H%M%S")

# Initialisation du fichier final avec l'en-tête XML unique
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>' > "$OUTPUT_FILE"

# 1. Téléchargement et Nettoyage Format
while read -r url; do
    [[ -z "$url" || "$url" == "#"* ]] && continue
    filename=$(basename "$url")
    echo "Téléchargement de $filename..."
    curl -sL "$url" -o "$TEMP_DIR/$filename"
    
    # Décompression
    [[ "$filename" == *.gz ]] && gunzip -f "$TEMP_DIR/$filename"
    
    # Nettoyage des caractères Windows (\r) dans les sources
    target_file="${TEMP_DIR}/${filename%.gz}"
    if [[ -f "$target_file" ]]; then
        sed -i 's/\r//g' "$target_file"
    fi
done < "$EPG_LIST"

# 2. Traitement des chaînes et programmes
while IFS=',' read -r old_id new_id logo_url offset; do
    [[ -z "$old_id" || "$old_id" == "#"* ]] && continue
    
    # Nettoyage des entrées du fichier choix.txt
    old_id=$(echo "$old_id" | tr -d '\r' | xargs)
    new_id=$(echo "$new_id" | tr -d '\r' | xargs)
    offset=$(echo "$offset" | tr -d '\r' | xargs)

    echo -n "Traitement : $old_id -> $new_id (Offset: ${offset:-0}h) "

    # Extraction du bloc <channel> (une seule occurrence, sans header XML)
    xmlstarlet sel -t -c "(//channel[@id='$old_id'])[1]" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/" | \
    sed "s|<display-name>[^<]*</display-name>|<display-name>$new_id</display-name>|" | \
    grep -v "<?xml" > "$TEMP_DIR/chan_raw.tmp"

    if [[ -s "$TEMP_DIR/chan_raw.tmp" ]]; then
        # Gestion du logo (Icon)
        if [[ -n "$logo_url" ]]; then
            if grep -q "<icon" "$TEMP_DIR/chan_raw.tmp"; then
                xmlstarlet ed -u "//channel/icon/@src" -v "$logo_url" "$TEMP_DIR/chan_raw.tmp" > "$TEMP_DIR/chan.tmp"
            else
                xmlstarlet ed -s "//channel" -t elem -n "icon" -v "" \
                            -i "//channel/icon" -t attr -n "src" -v "$logo_url" "$TEMP_DIR/chan_raw.tmp" > "$TEMP_DIR/chan.tmp"
            fi
        else
            cp "$TEMP_DIR/chan_raw.tmp" "$TEMP_DIR/chan.tmp"
        fi
        cat "$TEMP_DIR/chan.tmp" | grep -v "<?xml" >> "$OUTPUT_FILE"
    fi

    # 3. Extraction, filtrage et décalage horaire des programmes
    xmlstarlet sel -t -c "//programme[@channel='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed 's/<\/programme>/<\/programme>\n/g' | grep -v "<?xml" > "$TEMP_DIR/progs_raw.tmp"

    # Gawk traite les programmes et renvoie le compte sur stderr pour le log
    count=$(gawk -v start_lim="$START_LIMIT" -v end_lim="$END_LIMIT" \
         -v off="${offset:-0}" -v old_id="$old_id" -v new_id="$new_id" '
    BEGIN { c = 0 }
    {
        if (!match($0, /start="([0-9]{14})/)) next
        match($0, /start="([0-9]{14})"/, s)
        match($0, /stop="([0-9]{14})"/, e)
        t_start = s[1]; t_stop = e[1]

        if (t_start < start_lim || t_start > end_lim) next

        if (off != 0) {
            t_start = shift_time(t_start, off)
            t_stop = shift_time(t_stop, off)
        }

        line = $0
        gsub("start=\"" s[1] "\"", "start=\"" t_start "\"", line)
        gsub("stop=\"" e[1] "\"", "stop=\"" t_stop "\"", line)
        gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line)
        print line
        c++
    }
    function shift_time(ts, h) {
        y = substr(ts,1,4); m = substr(ts,5,2); d = substr(ts,7,2)
        H = substr(ts,9,2); M = substr(ts,11,2); S = substr(ts,13,2)
        curr = mktime(y " " m " " d " " H " " M " " S)
        return strftime("%Y%m%d%H%M%S", curr + (h * 3600))
    }
    END { print c > "/dev/stderr" }' "$TEMP_DIR/progs_raw.tmp" >> "$OUTPUT_FILE" 2>&1)

    echo "[$count programmes]"

done < "$CHOIX_FILE"

echo "</tv>" >> "$OUTPUT_FILE"

# 4. Formatage final (XML propre et indenté)
if command -v xmlstarlet &> /dev/null; then
    echo "Formatage du fichier final..."
    xmlstarlet fo -s 2 "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
fi

rm -rf "$TEMP_DIR"
echo "Succès : $OUTPUT_FILE a été généré."
