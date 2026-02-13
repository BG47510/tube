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

echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>' > "$OUTPUT_FILE"

# 1. Téléchargement
while read -r url; do
    [[ -z "$url" || "$url" == "#"* ]] && continue
    filename=$(basename "$url")
    echo "Téléchargement de $filename..."
    curl -sL "$url" -o "$TEMP_DIR/$filename"
    [[ "$filename" == *.gz ]] && gunzip -f "$TEMP_DIR/$filename"
done < "$EPG_LIST"

# 2. Traitement des chaînes et programmes
while IFS=',' read -r old_id new_id logo_url offset; do
    [[ -z "$old_id" || "$old_id" == "#"* ]] && continue
    
    echo "Traitement : $old_id -> $new_id (Offset: ${offset:-0}h)"

    # Extraction du bloc <channel> : on force la sélection de la 1ère occurrence uniquement
    xmlstarlet sel -t -c "(//channel[@id='$old_id'])[1]" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/" | \
    sed "s|<display-name>[^<]*</display-name>|<display-name>$new_id</display-name>|" > "$TEMP_DIR/chan_raw.tmp"

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
        cat "$TEMP_DIR/chan.tmp" >> "$OUTPUT_FILE"
    fi

    # 3. Extraction et décalage horaire des programmes
    xmlstarlet sel -t -c "//programme[@channel='$old_id']" "$TEMP_DIR"/*.xml 2>/dev/null | \
    sed 's/<\/programme>/<\/programme>\n/g' > "$TEMP_DIR/progs_raw.tmp"

    gawk -v start_lim="$START_LIMIT" -v end_lim="$END_LIMIT" \
         -v off="${offset:-0}" -v old_id="$old_id" -v new_id="$new_id" '
    {
        if (!match($0, /start="([0-9]{14})/)) next
        
        # Extraction dates
        match($0, /start="([0-9]{14})"/, s)
        match($0, /stop="([0-9]{14})"/, e)
        
        t_start = s[1]; t_stop = e[1]

        # Filtrage temporel
        if (t_start < start_lim || t_start > end_lim) next

        # Application de l offset
        if (off != 0) {
            t_start = shift_time(t_start, off)
            t_stop = shift_time(t_stop, off)
        }

        # Remplacement et écriture
        line = $0
        gsub("start=\"" s[1] "\"", "start=\"" t_start "\"", line)
        gsub("stop=\"" e[1] "\"", "stop=\"" t_stop "\"", line)
        gsub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line)
        print line
    }

    function shift_time(ts, h) {
        y = substr(ts,1,4); m = substr(ts,5,2); d = substr(ts,7,2)
        H = substr(ts,9,2); M = substr(ts,11,2); S = substr(ts,13,2)
        curr = mktime(y " " m " " d " " H " " M " " S)
        return strftime("%Y%m%d%H%M%S", curr + (h * 3600))
    }' "$TEMP_DIR/progs_raw.tmp" >> "$OUTPUT_FILE"

done < "$CHOIX_FILE"

echo "</tv>" >> "$OUTPUT_FILE"

# 4. Formatage final
echo "Formatage du fichier final..."
xmlstarlet fo -s 2 "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"

rm -rf "$TEMP_DIR"
echo "Succès : $OUTPUT_FILE a été généré."
