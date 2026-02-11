#!/bin/bash

# Script d'extraction EPG consolidé avec débogage
# Fichiers attendus : epgs.txt, choix.txt, variables.txt
# Résultat : epg.xml et listes de canaux

# Aller au répertoire du script
cd "$(dirname "$0")" || exit 1

# Vérification de l'existence des fichiers
for file in epgs.txt variables.txt choix.txt; do
    if [ ! -f "$file" ]; then
        echo "Erreur : le fichier $file est introuvable."
        exit 1
    fi
done

# Lire les variables de décalage
source variables.txt

# Calcul des dates (format YYYYMMDD)
date_debut=$(date -d "$jours_avant days ago" +"%Y%m%d%H%M%S")
date_fin=$(date -d "$jours_venir days" +"%Y%m%d%H%M%S")

echo "Début: $date_debut, Fin: $date_fin"

# Fichiers de sortie
output="epg.xml"

# Initialiser le fichier XML
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
echo '<tv generator-info-name="EPG Extractor" generator-info-url="https://example.com">' >> "$output"
epg_count=0

# Fonction d'échappement des caractères spéciaux
escape_xml() {
    echo "$1" | sed -e 's/&/&amp;/g' \
                     -e 's/</&lt;/g' \
                     -e 's/>/&gt;/g' \
                     -e 's/"/&quot;/g' \
                     -e "s/'/&apos;/g"
}

# Lire chaque URL dans epgs.txt
while IFS= read -r epg; do
    ((epg_count++))

    temp_file="EPG_temp${epg_count}.xml"
    gz_file="$temp_file.gz"

    echo "Traitement de l'URL: $epg..."
    
    if [[ "$epg" == *.gz ]]; then
        echo "Téléchargement et décompression de : $epg"
        wget -O "$gz_file" -q "$epg"

        if [ ! -s "$gz_file" ] || ! gzip -t "$gz_file" 2>/dev/null; then
            echo "Erreur : le fichier $gz_file est vide ou n'est pas un gzip valide."
            continue
        fi

        gzip -d -f "$gz_file"
    else
        echo "Téléchargement de : $epg"
        wget -O "$temp_file" -q "$epg"

        if [ ! -s "$temp_file" ]; then
            echo "Erreur : le fichier $temp_file est vide."
            continue
        fi
    fi

    # Ignorer la déclaration DTD si elle existe
    sed -i '/<!DOCTYPE/d' "$temp_file"

    # Débogage : affichage du contenu temporaire
    echo "Contenu temporaire de $temp_file :"
    cat "$temp_file" | head -n 20  # Affiche les 20 premières lignes

    # Génération de la liste de canaux
    listing="canaux_epg${epg_count}.txt"
    echo "# Source: $epg" > "$listing"
    
    # Utilisation d'XMLStarlet pour extraire les informations
    xmlstarlet sel -t -m "//channel" \
    -v "@id" -o "," \
    -v "display-name" -o "," \
    -v "icon/@src" -n "$temp_file" >> "$listing"

    # Lire chaque chaîne à extraire
    while IFS=, read -r id new_id icon priority; do
        if [[ -z "$id" || -z "$new_id" || -z "$priority" ]]; then
            echo "Erreur : la chaîne avec ID $id ne respecte pas le format requis dans choix.txt."
            exit 1
        fi

        # Ajustement pour le début et la fin en utilisant la priorité (en heures)
        adjusted_start=$(date -d "${date_debut} + $priority hours" +"%Y%m%d%H%M%S +0100")
        adjusted_end=$(date -d "${date_fin} + $priority hours" +"%Y%m%d%H%M%S +0100")

        echo "Extraction pour la chaîne $new_id ($id)"
        echo "Heure ajustée de début : $adjusted_start, Heure ajustée de fin : $adjusted_end"

        # Recherche de programmes
        result=$(xmlstarlet sel -t \
            -m "//programme[@channel='$(escape_xml "$id")' and @start >= '$adjusted_start' and @stop <= '$adjusted_end']" \
            -o "<programme channel='$(escape_xml "$new_id")' start='@start' stop='@stop'>" \
            -v "title" -o "</title>" \
            -n -o "<desc>" -v "desc" -o "</desc>" \
            -o "</programme>" \
            -n "$temp_file")

        if [[ -n $result ]]; then
            echo "$result" >> "$output"
        else
            echo "Aucun programme trouvé pour la chaîne $new_id avec l'ID $id."
        fi
    done < choix.txt

    # Nettoyer le fichier temporaire après chaque traitement
    rm -f "$temp_file"
done < epgs.txt

# Fermer le fichier XML
echo '</tv>' >> "$output"

# Valider le fichier XML généré
if xmlstarlet val "$output"; then
    echo "Extraction terminée. Résultat dans $output"
else
    echo "Erreur : le fichier XML généré n'est pas valide."
    xmlstarlet val "$output"  # Cela affichera les erreurs de validation
    exit 1
fi
