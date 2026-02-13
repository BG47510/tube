#!/bin/bash

# Répertoire de travail
WORKSPACE="${GITHUB_WORKSPACE}/b01"
EPG_FILE_LIST="$WORKSPACE/epg.txt"
CHOIX_FILE="$WORKSPACE/choix.txt"
VARIABLES_FILE="$WORKSPACE/variables.txt"
OUTPUT_XML="$WORKSPACE/final.xml"
CHANNEL_IDS="$WORKSPACE/channel_ids.txt"

# Initialisation
mkdir -p "$WORKSPACE"
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv></tv>' > "$OUTPUT_XML"

# 1. Chargement des variables (jours_avant, jours_venir)
source "$VARIABLES_FILE"

# 2. Traitement des URLs
while read -r url || [ -n "$url" ]; do
    url=$(echo "$url" | tr -d '\r' | xargs)
    [ -z "$url" ] && continue

    echo "Traitement de : $url"
    curl -sL -o "current_data" "$url"

    # Décompression si nécessaire
    TYPE=$(file -b current_data)
    if [[ "$TYPE" == *"gzip"* ]]; then
        gzip -dc "current_data" > "current.xml"
    else
        mv "current_data" "current.xml"
    fi

    # Extraction des IDs originaux pour votre liste globale
    xmlstarlet sel -t -v "//channel/@id" "current.xml" >> "$CHANNEL_IDS"
    echo "" >> "$CHANNEL_IDS"

    # 3. Boucle de filtrage et renommage basée sur choix.txt
    while IFS=',' read -r old_id new_id new_logo offset; do
        old_id=$(echo "$old_id" | tr -d '\r' | xargs)
        [ -z "$old_id" ] && continue

        # On extrait les balises <channel> et <programme> correspondantes
        # On les injecte directement dans le fichier final
        
        # Extraction et modification à la volée du channel
        xmlstarlet sel -t -c "//channel[@id='$old_id']" "current.xml" | \
        xmlstarlet ed -u "//channel/@id" -v "$new_id" \
                      -u "//channel/icon/@src" -v "$new_logo" >> "temp_content.xml"

        # Extraction et modification à la volée des programmes
        xmlstarlet sel -t -c "//programme[@channel='$old_id']" "current.xml" | \
        xmlstarlet ed -u "//programme/@channel" -v "$new_id" >> "temp_content.xml"

    done < "$CHOIX_FILE"

    rm -f "current.xml" "current_data"
done < "$EPG_FILE_LIST"

# 4. Assemblage final (on insère tout le contenu dans la balise <tv>)
xmlstarlet ed -s "/tv" -t elem -n "placeholder" -v "REPLACE_ME" "$OUTPUT_XML" > "$OUTPUT_XML.tmp"
sed -i "/REPLACE_ME/r temp_content.xml" "$OUTPUT_XML.tmp"
sed -i "/REPLACE_ME/d" "$OUTPUT_XML.tmp"
mv "$OUTPUT_XML.tmp" "$OUTPUT_XML"

# Nettoyage
sort -u "$CHANNEL_IDS" -o "$CHANNEL_IDS"
rm -f temp_content.xml
echo "Traitement terminé. Fichier généré : $OUTPUT_XML"
