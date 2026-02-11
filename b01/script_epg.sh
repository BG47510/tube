#!/usr/bin/env bash

set -euo pipefail

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
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">'
} > "$output"

# Fonction d'échappement XML
escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

# Convertir YYYYMMDDHHMMSS → YYYY-MM-DD HH:MM:SS
fmt_date() {
    echo "$1" | sed 's/\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'
}

# Nettoyer les dates XMLTV (garder seulement YYYYMMDDHHMMSS)
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

    # Test .gz corrigé
    if [[ "$epg" == *.gz ]]; then
        wget -q -O "$gz" "$epg"
        if ! gzip -t "$gz" 2>/dev/null; then
            echo "Erreur : gzip invalide"
            continue
        fi
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

        xml_icon=$(xmlstarlet sel -t -m "//channel[@id='$(escape_xml "$id")']/icon/@src" -v . "$temp")

        new_id="${new_id:-$id}"
        icon="${icon:-$xml_icon}"
        priority="${priority:-0}"

        # Décalage horaire éventuel (priority en heures)
        adjusted_start=$(date -d "$(fmt_date "$date_debut") $priority hours" +"%Y%m%d%H%M%S +0100")
        adjusted_end=$(date -d "$(fmt_date "$date_fin") $priority hours" +"%Y%m%d%H%M%S +0100")

        adj_start=$(clean_date "$adjusted_start")
        adj_end=$(clean_date "$adjusted_end")

        echo "Extraction : $new_id ($id) [$adj_start → $adj_end]"

        # Construction propre du XPath
        chan=$(escape_xml "$id")
        xpath="//programme[@channel='$chan' and substring(@stop,1,14) >= '$adj_start' and substring(@start,1,14) <= '$adj_end']"

        xmlstarlet sel -t \
            -m "$xpath" \
            -o "<programme channel='$(escape_xml "$new_id")' start='" \
            -v "@start" \
            -o "' stop='" \
            -v "@stop" \
            -o "'>" \
            -o "<title>" -v "title" -o "</title>" \
            -o "<desc>" -v "desc" -o "</desc>" \
            -o "</programme>" \
            -n "$temp" >> "$temp_programmes"

    done < choix.txt

done < epgs.txt

# Nettoyage : suppression lignes vides
sed -i '/^$/d' "$temp_programmes"

# Suppression des doublons
sort -u "$temp_programmes" >> "$output"

# Fermeture XML
echo "</tv>" >> "$output"

xmlstarlet val "$output" && echo "EPG généré : $output" || echo "Erreur XML"
