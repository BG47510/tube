#!/bin/bash

# Script d'extraction EPG consolidé optimisé
cd "$(dirname "$0")" || exit 1

# Dossier temporaire hors du dépôt Git
TMPDIR="/tmp/epg_extract"
mkdir -p "$TMPDIR"

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
temp_programmes="$TMPDIR/programmes_temp.txt"
> "$temp_programmes"

# Initialisation XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
echo '<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">' >> "$output"

# Fonction d'échappement XML
escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

# Fonction pour nettoyer les dates XMLTV (supprimer fuseau)
clean_date() {
    echo "$1" | cut -c1-14
}

epg_count=0

while IFS= read -r epg; do
    ((epg_count++))

    temp="$TMPDIR/EPG_temp${epg_count}.xml"
    gz="$TMPDIR/EPG_temp${epg_count}.xml.gz"
    listing="$TMPDIR/canaux_epg${epg_count}.txt"

    echo "Téléchargement : $epg"

    if [[ "$epg" == *.gz ]]; then
        wget -q -O "$gz" "$epg"
        gzip -t "$gz" 2>/dev/null || { echo "Erreur : gzip invalide"; continue; }
        gzip -d -f "$gz"
    else
        wget -q -O "$temp" "$epg"
    fi

    [[ ! -s "$temp" ]] && echo "Erreur : fichier vide" && continue

    # Supprimer DTD
    sed -i '/<!DOCTYPE/d' "$temp"

    # Génération liste des chaînes
    echo "# Source: $epg" > "$listing"

    xmlstarlet sel -t -m "//channel" \
        -v "@id" -o "," \
        -v "display-name" -o "," \
        -v "icon/@src" -n "$temp" >> "$listing"

    # Lecture des chaînes à extraire
    while IFS=, read -r id new_id icon priority; do
        [[ -z "$id" ]] && continue

        xml_icon=$(xmlstarlet sel -t -m "//channel[@id='$(escape_xml
