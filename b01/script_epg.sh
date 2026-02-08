#!/bin/bash

# Script d'extraction EPG avec xmlstarlet
# Fichiers attendus : epgs.txt, choix.txt, variables.txt
# Résultat : epg.xml

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# Vérification de l'existence des fichiers
if [ ! -f "epgs.txt" ]; then
    echo "Erreur : le fichier epgs.txt est introuvable."
    exit 1
fi

if [ ! -f "variables.txt" ]; then
    echo "Erreur : le fichier variables.txt est introuvable."
    exit 1
fi

# Lire les variables de décalage
source variables.txt

# Calcul des dates (format YYYYMMDD)
date_debut=$(date -d "$jours_avant days ago" +%Y%m%d)
date_fin=$(date -d "$jours_venir days" +%Y%m%d)

echo "Début: $date_debut, Fin: $date_fin"

# Fichier de sortie
output="epg.xml"

# Initialiser le fichier XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
echo '<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">' >> "$output"

# Fonction d'échappement des caractères spéciaux
escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

# Lire chaque URL dans epgs.txt
while IFS= read -r url; do
    echo "Traitement de l'URL: $url..."
    # Télécharger et décompresser si nécessaire
    if [[ "$url" == *.gz ]]; then
        wget -q -O - "$url" | gunzip > temp.xml
    else
        wget -q -O temp.xml "$url"
    fi

    # Vérifier le succès du téléchargement
    if [[ $? -ne 0 ]]; then
        echo "Erreur lors du téléchargement de $url"
        continue
    fi

    # Ignorer la déclaration DTD si elle existe
    sed -i '/<!DOCTYPE/d' temp.xml

    # Lire chaque chaîne à extraire
    while IFS=, read -r id name icon; do
        # Vérification du format des chaînes
        if [[ -z "$id" || -z "$name" ]]; then
            echo "Erreur : La chaîne $name ne respecte pas le format requis dans choix.txt."
            exit 1
        fi
        echo "  Extraction pour la chaîne $name ($id)"

        # Extraire les programmes pour cette chaîne et cette période
        result=$(xmlstarlet sel -t \
            -m "//channel[@id='$(escape_xml "$id")']/programme[starts-with(@start, '$date_debut') and starts-with(@stop, '$date_fin')]" \
            -o "<programme channel='$(escape_xml "$id")' start='@start' stop='@stop'>" \
            -v "title" -o "</title>" \
            -n -o "<desc>" -v "desc" -o "</desc>" \
            -o "</programme>" \
            -n temp.xml)

        if [[ -n $result ]]; then
            echo "$result" >> "$output"
        else
            echo "Aucun programme trouvé pour la chaîne $name avec l'ID $id."
        fi
    done < choix.txt

    # Nettoyer le fichier temporaire après chaque traitement
    rm -f temp.xml
done < epgs.txt

# Fermer le fichier XML
echo '</tv>' >> "$output"

# Valider le fichier XML généré
if xmlstarlet val "$output"; then
    echo "Extraction terminée. Résultat dans $output"
else
    echo "Erreur : le fichier XML généré n'est pas valide."
    exit 1
fi
