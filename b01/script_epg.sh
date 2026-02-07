#!/bin/bash

# Script d'extraction EPG avec xmlstarlet
# Fichiers attendus : epgs.txt, choix.txt, variables.txt
# Résultat : epg.xml

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# Lire les variables de décalage
source variables.txt

# Calcul des dates (format YYYYMMDD)
date_debut=$(date -d "$jours_avant days ago" +%Y%m%d)
date_fin=$(date -d "$jours_venir days" +%Y%m%d)

# Fichier de sortie
output="epg.xml"

# Initialiser le fichier XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
echo '<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">' >> "$output"

# Lire chaque URL
while IFS= read -r url; do
    echo "Traitement de $url..."
    # Télécharger et décompresser si nécessaire
    if [[ "$url" == *.gz ]]; then
        wget -q -O - "$url" | gunzip > temp.xml
    else
        wget -q -O temp.xml "$url"
    fi

    # Lire chaque chaîne à extraire
    while IFS=, read -r id name icon; do
        echo "  Extraction pour la chaîne $name ($id)"
        # Extraire les programmes pour cette chaîne et cette période
        xmlstarlet sel -t \
            -m "//channel[@id='$id']/programme[starts-with(@start, '$date_debut') and starts-with(@stop, '$date_fin')]" \
            -v "concat('<programme channel=\"$id\" start=\"', @start, '\" stop=\"', @stop, '\">')" \
            -v "concat('<title>', title, '</title>')" \
            -v "concat('<desc>', desc, '</desc>')" \
            -v "</programme>" \
            -n temp.xml >> "$output"
    done < choix.txt
done < epgs.txt

# Fermer le fichier XML
echo '</tv>' >> "$output"

# Nettoyer
rm -f temp.xml

echo "Extraction terminée. Résultat dans $output"
