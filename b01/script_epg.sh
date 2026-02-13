#!/bin/bash

# Répertoire de travail
WORKSPACE="${GITHUB_WORKSPACE}/b01"

# Fichiers d'entrée
EPG_FILE_LIST="$WORKSPACE/epg.txt"
CHOIX_FILE="$WORKSPACE/choix.txt"
VARIABLES_FILE="$WORKSPACE/variables.txt"
OUTPUT_XML="$WORKSPACE/final.xml"
TEMP_XML="$WORKSPACE/temp.xml"
CHANNEL_IDS="$WORKSPACE/channel_ids.txt"

# Afficher le contenu du répertoire
echo "Contenu du répertoire courant :"
ls -l "$WORKSPACE"

# Vérification de l'existence des fichiers
if [ ! -f "$EPG_FILE_LIST" ]; then
    echo "Erreur : le fichier $EPG_FILE_LIST n'existe pas."
    exit 1
fi

if [ ! -f "$CHOIX_FILE" ]; then
    echo "Erreur : le fichier $CHOIX_FILE n'existe pas."
    exit 1
fi

if [ ! -f "$VARIABLES_FILE" ]; then
    echo "Erreur : le fichier $VARIABLES_FILE n'existe pas."
    exit 1
fi

# Lire les jours avant et après depuis variables.txt
source "$VARIABLES_FILE"
today=$(date -u +%Y%m%d)
start_date=$(date -u -d "$today - $jours_avant days" +%Y%m%d)
end_date=$(date -u -d "$today + $jours_venir days" +%Y%m%d)

# Initialize the output file
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUTPUT_XML"h
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> "$OUTPUT_XML"
echo '<tv>' >> "$OUTPUT_XML"

# Extraction des channel IDs depuis les fichiers XML
while read -r url; do
    response=$(curl -sL -o temp.gz -w "%{http_code}" "$url")
    if [ "$response" != "200" ]; then
        echo "Erreur lors du téléchargement de $url : code HTTP $response"
    else
        file temp.gz  # Affiche le type de fichier téléchargé
        gzip -dc "temp.gz" | xmllint --xpath '//channel/@id' - >> "$CHANNEL_IDS"
        rm -f temp.gz  # Supprime le fichier temporaire après utilisation
    fi
done < "$EPG_FILE_LIST"


# Suppression des doublons
sort -u "$CHANNEL_IDS" -o "$CHANNEL_IDS"

# Traitement selon le fichier choix.txt
declare -A CHANNEL_MAP
while IFS=',' read -r ancien_id nouveau_id logo_url offset_h; do
    CHANNEL_MAP["$ancien_id"]="$nouveau_id,$logo_url,$offset_h"
done < "$CHOIX_FILE"

# Traitement des fichiers XML
while read -r url; do
    gzip -dc "$url" | while read -r line; do
        if [[ $line == *"<channel "* ]]; then
            channel_id=$(echo "$line" | sed -n 's/.*id="\([^"]*\)".*/\1/p')
            if [[ -n "${CHANNEL_MAP[$channel_id]}" ]]; then
                new_info=(${CHANNEL_MAP[$channel_id]//,/ })
                new_id=${new_info[0]}
                logo_url=${new_info[1]}
                line=$(echo "$line" | sed "s/id=\"$channel_id\"/id=\"$new_id\"/")
                if [[ ! -z $logo_url ]]; then
                    line=$(echo "$line" | sed "s|src=\"[^\"]*\"|src=\"$logo_url\"|")
                fi
                echo "$line" >> "$TEMP_XML"
            fi
        elif [[ $line == *"<programme "* ]]; then
            start_time=$(echo "$line" | sed -n 's/.*start="\([^"]*\)".*/\1/p')
            stop_time=$(echo "$line" | sed -n 's/.*stop="\([^"]*\)".*/\1/p')
            channel_id=$(echo "$line" | sed -n 's/.*channel="\([^"]*\)".*/\1/p')
            if [[ -n "${CHANNEL_MAP[$channel_id]}" ]]; then
                offset_h=${CHANNEL_MAP[$channel_id]//,*}
                if [[ ! -z "$offset_h" ]]; then
                    offset_seconds=$((offset_h * 3600))
                    start_time=$(date -u -d "$start_time + $offset_seconds seconds" +%Y%m%d%H%M%S)
                    stop_time=$(date -u -d "$stop_time + $offset_seconds seconds" +%Y%m%d%H%M%S)
                fi
                line=$(echo "$line" | sed "s/start=\"[^\"]*\"/start=\"$start_time\"/")
                line=$(echo "$line" | sed "s/stop=\"[^\"]*\"/stop=\"$stop_time\"/")
                echo "$line" >> "$TEMP_XML"
            fi
        fi
    done
done < "$EPG_FILE_LIST"

# Suppression des doublons dans le fichier temporaire
awk '!seen[$0]++' "$TEMP_XML" >> "$OUTPUT_XML"
rm "$TEMP_XML"

# Fermeture de la structure XML finale
echo '</tv>' >> "$OUTPUT_XML"

# Validation de l'XML final
if xmllint --noout "$OUTPUT_XML"; then
    echo "XML final valide créé : $OUTPUT_XML"
else
    echo "Erreur de validation XML."
    rm "$OUTPUT_XML"
fi

# Nettoyage des fichiers temporaires
rm "$CHANNEL_IDS"
