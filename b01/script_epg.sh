#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")" || exit 1

TMPDIR="/tmp/epg_extract"
mkdir -p "$TMPDIR"

# Vérification fichiers requis
for file in epgs.txt variables.txt choix.txt; do
    if [[ ! -f "$file" ]]; then
        echo "Erreur : fichier $file introuvable."
        exit 1
    fi
done

# Charger variables
source variables.txt

date_debut=$(date -d "$jours_avant days ago" +"%Y%m%d%H%M%S")
date_fin=$(date -d "$jours_venir days" +"%Y%m%d%H%M%S")

echo "Fenêtre : $date_debut → $date_fin"

output="epg.xml"
temp_programmes="$TMPDIR/programmes_temp.txt"
> "$temp_programmes"

# Initialisation XML
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<tv generator-info-name="EPG Extractor">'
} > "$output"

escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

fmt_date() {
    echo "$1" | sed 's/\(....\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/'
}

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

    # Téléchargement blindé
    if [[ "$epg" == *.gz ]]; then
        if ! wget -q -O "$gz" "$epg"; then
            echo "Erreur : téléchargement échoué"
            continue
        fi

        if ! gzip -t "$gz" 2>/dev/null; then
            echo "Erreur : gzip invalide"
            continue
        fi

        if ! gzip -d -f "$gz"; then
            echo "Erreur : décompression échouée"
            continue
        fi

        mv "$TMPDIR/EPG_temp${epg_count}.xml" "$temp"

    else
        if ! wget -q -O "$temp" "$epg"; then
            echo "Erreur : téléchargement échoué"
            continue
        fi
    fi

    if [[ ! -s "$temp" ]]; then
        echo "Erreur : fichier vide"
        continue
    fi

    sed -i '/<!DOCTYPE/d' "$temp"

    echo "# Source: $epg" > "$listing"

    # Extraction des chaînes blindée
    if ! xmlstarlet sel -t -m "//channel" \
        -v "@id" -o "," \
        -v "display-name" -o "," \
        -v "icon/@src" -n "$temp" >> "$listing" 2>/dev/null; then
        echo "Erreur : XML invalide dans $temp"
        continue
    fi

    # Lecture des chaînes à extraire
    while IFS=, read -r id new_id icon priority; do
        [[ -z "$id" ]] && continue

        new_id="${new_id:-$id}"
        priority="${priority:-0}"

        # Récupération icône si vide
        if [[ -z "$icon" ]]; then
            icon=$(xmlstarlet sel -t -m "//channel[@id='$(escape_xml "$id")']/icon/@src" -v . "$temp" 2>/dev/null || echo "")
        fi

        # Calcul dates ajustées
        adjusted_start=$(date -d "$(fmt_date "$date_debut") $priority hours" +"%Y%m%d%H%M%S +0100")
        adjusted_end=$(date -d "$(fmt_date "$date_fin") $priority hours" +"%Y%m%d%H%M%S +0100")

        adj_start=$(clean_date "$adjusted_start")
        adj_end=$(clean_date "$adjusted_end")

        echo "Extraction : $new_id ($id) [$adj_start → $adj_end]"

        chan=$(escape_xml "$id")
        xpath="//programme[@channel='$chan' and substring(@stop,1,14) >= '$adj_start' and substring(@start,1,14) <= '$adj_end']"

        # Extraction blindée
        if ! xmlstarlet sel -t \
            -m "$xpath" \
            -o "<programme channel='$(escape_xml "$new_id")' start='" \
            -v "@start" \
            -o "' stop='" \
            -v "@stop" \
            -o "'>" \
            -o "<title>" -v "title" -o "</title>" \
            -o "<desc>" -v "desc" -o "</desc>" \
            -o "</programme>" \
            -n "$temp" >> "$temp_programmes" 2>/dev/null; then
            echo "Aucun programme trouvé pour $id"
            continue
        fi

    done < choix.txt

done < epgs.txt

sed -i '/^$/d' "$temp_programmes"

sort -u "$temp_programmes" >> "$output"

echo "</tv>" >> "$output"

if xmlstarlet val "$output" >/dev/null 2>&1; then
    echo "EPG généré : $output"
else
    echo "Erreur XML finale"
fi
