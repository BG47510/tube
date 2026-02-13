#!/bin/bash

# Fichiers d'entrée
EPG_FILE_LIST="epg.txt"
CHOIX_FILE="choix.txt"
VARIABLES_FILE="variables.txt"
OUTPUT_XML="final.xml"

# Read days before and after from variables.txt
source $VARIABLES_FILE
today=$(date -u +%Y%m%d)
start_date=$(date -u -d "$today - $jours_avant days" +%Y%m%d)
end_date=$(date -u -d "$today + $jours_venir days" +%Y%m%d)

# Temporary files
TEMP_XML="temp.xml"
CHANNEL_IDS="channel_ids.txt"

# Initialize the output file
echo '<?xml version="1.0" encoding="UTF-8"?>' > $OUTPUT_XML
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> $OUTPUT_XML
echo '<tv>' >> $OUTPUT_XML

# Extract channel IDs from XML files
while read -r url; do
    gzip -dc "$url" | xmllint --xpath '//channel/@id' - >> $CHANNEL_IDS
done < $EPG_FILE_LIST

# Remove duplicates and create unique channel IDs
sort -u $CHANNEL_IDS -o $CHANNEL_IDS

# Convert the choices into a format for processing
declare -A CHANNEL_MAP
while IFS=',' read -r ancien_id nouveau_id logo_url offset_h; do
    CHANNEL_MAP[$ancien_id]="$nouveau_id,$logo_url,$offset_h"
done < $CHOIX_FILE

# Process each XML file
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
                echo "$line" >> $TEMP_XML
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
                echo "$line" >> $TEMP_XML
            fi
        fi
    done
done < $EPG_FILE_LIST

# Cleaning up temporary files and duplicates
awk '!seen[$0]++' $TEMP_XML >> $OUTPUT_XML
rm $TEMP_XML

# Close the final XML structure
echo '</tv>' >> $OUTPUT_XML

# Final XML validation
if xmllint --noout $OUTPUT_XML; then
    echo "XML final valide créé : $OUTPUT_XML"
else
    echo "Erreur de validation XML."
    rm $OUTPUT_XML
fi

# Cleanup
rm $CHANNEL_IDS
