#!/bin/bash

# Fichiers de configuration
EPG_LIST="epg.txt"
CHOIX_FILE="choix.txt"
VARS_FILE="variables.txt"
OUTPUT_FILE="epg_final.xml"
TEMP_DIR="./temp_epg"

# Lecture des variables
[[ -f $VARS_FILE ]] && source $VARS_FILE
DAYS_BEFORE=${jours_avant:-1}
DAYS_AFTER=${jours_venir:-2}

# Calcul des bornes
START_LIMIT=$(date -d "$DAYS_BEFORE days ago 00:00:00" +"%Y%m%d%H%M%S")
END_LIMIT=$(date -d "$DAYS_AFTER days 23:59:59" +"%Y%m%d%H%M%S")

mkdir -p $TEMP_DIR
# Initialisation propre du fichier XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > $OUTPUT_FILE
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> $OUTPUT_FILE
echo '<tv>' >> $OUTPUT_FILE

# 1. Téléchargement
while read -r url; do
    [[ -z "$url" || "$url" == "#"* ]] && continue
    filename=$(basename "$url")
    echo "Téléchargement de $filename..."
    curl -sL "$url" -o "$TEMP_DIR/$filename"
    if [[ "$filename" == *.gz ]]; then
        gunzip -f "$TEMP_DIR/$filename"
    fi
done < "$EPG_LIST"

# 2. Traitement des chaînes
while IFS=',' read -r old_id new_id logo_url offset; do
    [[ -z "$old_id" || "$old_id" == "#"* ]] && continue
    
    echo "Traitement : $old_id -> $new_id"

    # Extraction unique du bloc <channel> (on prend le premier trouvé pour éviter les doublons)
    # On supprime les déclarations XML parasites avec sed
    xmlstarlet sel -t -c "//channel[@id='$old_id'][1]" $TEMP_DIR/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/" | \
    sed "s|<display-name>[^<]*</display-name>|<display-name>$new_id</display-name>|" | \
    sed '/<?xml/d' > "$TEMP_DIR/chan.tmp"

    if [[ -n "$logo_url" ]]; then
        # On vérifie si une icône existe déjà, sinon on la crée
        if grep -q "<icon" "$TEMP_DIR/chan.tmp"; then
            xmlstarlet ed -L -u "//channel/icon/@src" -v "$logo_url" "$TEMP_DIR/chan.tmp"
        else
            xmlstarlet ed -L -s "//channel" -t elem -n "icon" -v "" \
                          -i "//channel/icon" -t attr -n "src" -v "$logo_url" "$TEMP_DIR/chan.tmp"
        fi
    fi
    cat "$TEMP_DIR/chan.tmp" >> $OUTPUT_FILE

    # Extraction des programmes avec filtrage temporel
    # Utilisation de sed pour garantir un saut de ligne entre chaque bloc <programme>
    xmlstarlet sel -t -c "//programme[@channel='$old_id']" $TEMP_DIR/*.xml 2>/dev/null | \
    sed 's/<\/programme>/<\/programme>\n/g' | sed '/<?xml/d' > "$TEMP_DIR/progs_raw.tmp"

    while read -r line; do
        [[ -z "$line" ]] && continue
        
        start_raw=$(echo "$line" | grep -oP 'start="\K[0-9]{14}')
        stop_raw=$(echo "$line" | grep -oP 'stop="\K[0-9]{14}')

        [[ -z "$start_raw" ]] && continue

        # Filtrage
        if [[ "$start_raw" < "$START_LIMIT" || "$start_raw" > "$END_LIMIT" ]]; then
            continue
        fi

        # Calcul offset
        if [[ -n "$offset" && "$offset" != "0" ]]; then
            start_new=$(date -d "${start_raw:0:8} ${start_raw:8:2}:${start_raw:10:2}:${start_raw:12:2} $offset hours" +"%Y%m%d%H%M%S")
            stop_new=$(date -d "${stop_raw:0:8} ${stop_raw:8:2}:${stop_raw:10:2}:${stop_raw:12:2} $offset hours" +"%Y%m%d%H%M%S")
            line=$(echo "$line" | sed "s/$start_raw/$start_new/" | sed "s/$stop_raw/$stop_new/")
        fi
        
        # Changement de l'ID final
        echo "$line" | sed "s/channel=\"$old_id\"/channel=\"$new_id\"/g" >> $OUTPUT_FILE
    done < "$TEMP_DIR/progs_raw.tmp"

done < "$CHOIX_FILE"

echo "</tv>" >> $OUTPUT_FILE

# Nettoyage final avec l'option --huge pour éviter l'erreur de profondeur
xmlstarlet fo --huge -s 2 $OUTPUT_FILE > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" $OUTPUT_FILE
rm -rf $TEMP_DIR

echo "Terminé : $OUTPUT_FILE"
