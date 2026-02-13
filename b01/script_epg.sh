#!/bin/bash

# Fichiers de configuration
EPG_LIST="epg.txt"
CHOIX_FILE="choix.txt"
VARS_FILE="variables.txt"
OUTPUT_FILE="epg_final.xml"
TEMP_DIR="./temp_epg"

# Lecture des variables de filtrage
source $VARS_FILE
DAYS_BEFORE=${jours_avant:-1}
DAYS_AFTER=${jours_venir:-2}

# Calcul des bornes temporelles (format XMLTV: YYYYMMDDHHMMSS)
START_LIMIT=$(date -d "$DAYS_BEFORE days ago 00:00:00" +"%Y%m%d%H%M%S")
END_LIMIT=$(date -d "$DAYS_AFTER days 23:59:59" +"%Y%m%d%H%M%S")

mkdir -p $TEMP_DIR
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>' > $OUTPUT_FILE

# 1. Téléchargement et extraction
while read -r url; do
    [[ -z "$url" ]] && continue
    filename=$(basename "$url")
    echo "Téléchargement de $filename..."
    curl -sL "$url" -o "$TEMP_DIR/$filename"
    
    if [[ "$filename" == *.gz ]]; then
        gunzip -f "$TEMP_DIR/$filename"
    fi
done < "$EPG_LIST"

# 2. Traitement par chaîne définie dans choix.txt
# Format: ancien_id,nouveau_id,logo_url,offset_h
while IFS=',' read -r old_id new_id logo_url offset; do
    [[ -z "$old_id" || "$old_id" == "#"* ]] && continue
    
    echo "Traitement de la chaîne : $old_id -> $new_id"

    # Extraction du bloc <channel>
    # On cherche dans tous les XML téléchargés
    xmlstarlet sel -t -c "//channel[@id='$old_id']" $TEMP_DIR/*.xml 2>/dev/null | \
    sed "s/id=\"$old_id\"/id=\"$new_id\"/" | \
    sed "s|<display-name>.*</display-name>|<display-name>$new_id</display-name>|" > "$TEMP_DIR/chan.tmp"

    # Mise à jour du logo si spécifié
    if [[ -n "$logo_url" ]]; then
        xmlstarlet ed -L -u "//channel[@id='$new_id']/icon/@src" -v "$logo_url" "$TEMP_DIR/chan.tmp"
    fi
    cat "$TEMP_DIR/chan.tmp" >> $OUTPUT_FILE

    # Extraction et transformation des programmes
    xmlstarlet sel -t -c "//programme[@channel='$old_id']" $TEMP_DIR/*.xml 2>/dev/null | \
    sed "s/channel=\"$old_id\"/channel=\"$new_id\"/g" > "$TEMP_DIR/progs.tmp"

    # Application du décalage horaire (offset) et filtrage
    # On utilise un script awk ou une boucle pour traiter chaque bloc programme
    while read -r line; do
        [[ -z "$line" ]] && continue
        
        # Extraction dates
        start_raw=$(echo "$line" | grep -oP 'start="\K[0-9]{14}')
        stop_raw=$(echo "$line" | grep -oP 'stop="\K[0-9]{14}')

        # Filtrage temporel
        if [[ "$start_raw" -lt "$START_LIMIT" || "$start_raw" -gt "$END_LIMIT" ]]; then
            continue
        fi

        # Calcul offset
        if [[ -n "$offset" && "$offset" -ne 0 ]]; then
            start_new=$(date -d "${start_raw:0:8} ${start_raw:8:2}:${start_raw:10:2}:${start_raw:12:2} $offset hours" +"%Y%m%d%H%M%S")
            stop_new=$(date -d "${stop_raw:0:8} ${stop_raw:8:2}:${stop_raw:10:2}:${stop_raw:12:2} $offset hours" +"%Y%m%d%H%M%S")
            line=$(echo "$line" | sed "s/$start_raw/$start_new/" | sed "s/$stop_raw/$stop_new/")
        fi
        
        echo "$line" >> $OUTPUT_FILE
    done < <(xmlstarlet sel -t -c "//programme[@channel='$old_id']" $TEMP_DIR/*.xml 2>/dev/null | sed 's/<\/programme>/<\/programme>\n/g')

done < "$CHOIX_FILE"

# Fermeture du XML et nettoyage
echo "</tv>" >> $OUTPUT_FILE

# Suppression des lignes vides et formatage final
xmlstarlet fo -s 2 $OUTPUT_FILE > "$OUTPUT_FILE.clean" && mv "$OUTPUT_FILE.clean" $OUTPUT_FILE
rm -rf $TEMP_DIR

echo "Fichier $OUTPUT_FILE généré avec succès."
