#!/bin/bash

# Script d'extraction EPG consolidé optimisé
cd "$(dirname "$0")" || exit 1

# Vérification des fichiers requis
for file in epgs.txt variables.txt choix.txt; do
    [[ ! -f "$file" ]] && echo "Erreur : fichier $file introuvable." && exit 1
done

# Charger les variables
source variables.txt

# Dates XMLTV (YYYYMMDDHHMMSS)
date_debut=$(date -d "$jours_avant days ago" +"%Y%m%d%H%M%S")
date_fin=$(date -d "$jours_venir days" +"%Y%m%d%H%M%S")

echo "Fenêtre : $date_debut → $date_fin"

output="epg.xml"

# Initialisation XML
cat > "$output" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">
EOF

# Fonction d'échappement XML
escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

# Convertir YYYYMMDDHHMMSS → YYYY-MM-DD HH:MM:SS (compatible GNU date)
fmt_date() {
    echo "$1" | sed 's/\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'
}

epg_count=0

while IFS= read -r epg; do
    ((epg_count++))
    temp="EPG_temp${epg_count}.xml"
    gz="$temp.gz"

    echo "Téléchargement : $epg"

    if [[ "$epg" == *.gz ]]; then
        wget -q -O "$gz" "$epg"
        gzip -t "$gz" 2>/dev/null || { echo "Gzip invalide"; continue; }
        gzip -d -f "$gz"
    else
        wget -q -O "$temp" "$epg"
    fi

    [[ ! -s "$temp" ]] && echo "Fichier vide" && continue

    sed -i '/<!DOCTYPE/d' "$temp"

    # Génération liste des chaînes
    listing="canaux_epg${epg_count}.txt"
    echo "# Source: $epg" > "$listing"

    xmlstarlet sel -t -m "//channel" \
        -v "@id" -o "," \
        -v "display-name" -o "," \
        -v "icon/@src" -n "$temp" >> "$listing"

    # Lecture des chaînes à extraire
    while IFS=, read -r id new_id icon priority; do
        [[ -z "$id" ]] && continue

        xml_icon=$(xmlstarlet sel -t -m "//channel[@id='$(escape_xml "$id")']/icon/@src" -v . "$temp")

        new_id="${new_id:-$id}"
        icon="${icon:-$xml_icon}"
        priority="${priority:-0}"

        # Calcul des dates XMLTV (uniquement avec priority)
        adjusted_start=$(date -d "$(fmt_date "$date_debut") $priority hours" +"%Y%m%d%H%M%S +0100")
        adjusted_end=$(date -d "$(fmt_date "$date_fin") $priority hours" +"%Y%m%d%H%M%S +0100")

        echo "Extraction : $new_id ($id) [$adjusted_start → $adjusted_end]"

        # Extraction des programmes (chevauchement inclus)
        xmlstarlet sel -t \
            -m "//programme[@channel='$(escape_xml "$id")' and @stop >= '$adjusted_start' and @start <= '$adjusted_end']" \
            -o "<programme channel='$(escape_xml "$new_id")' start='" \
            -v "@start" \
            -o "' stop='" \
            -v "@stop" \
            -o "'>" \
            -o "<title>" -v "title" -o "</title>" \
            -o "<desc>" -v "desc" -o "</desc>" \
            -o "</programme>" \
            -n "$temp" >> "$output"

    done < choix.txt

    rm -f "$temp"

done < epgs.txt

echo "</tv>" >> "$output"

xmlstarlet val "$output" && echo "EPG généré : $output" || echo "Erreur XML"
