#!/bin/bash

# Lire les variables de décalage
source variables.txt

# Fichiers
output="epg.xml"
log="erreurs.log"
> "$log"  # Vider le log au démarrage

# Créer le fichier de sortie XML avec en-tête conforme
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> "$output"
echo '<tv generator-info-name="EPG Generator" source-info-name="Custom">' >> "$output"

# Fonction pour télécharger et extraire un fichier
process_epg() {
    output="epgs_processed.txt"  # Nom du fichier de sortie pour les chaînes
    log="telechargement.log"      # Nom du fichier journal pour les erreurs

    # Vérifier si epgs.txt existe
    if [ ! -f "epgs.txt" ]; then
        echo "Erreur : Le fichier epgs.txt n'existe pas." >> "$log"
        return
    fi

    # Lire chaque URL à partir de epgs.txt
    while IFS= read -r url; do
        tempfile=$(mktemp)

        # Tenter de télécharger le fichier
        if ! wget -q "$url" -O "$tempfile"; then
            echo "Erreur : Impossible de télécharger $url" >> "$log"
            rm "$tempfile"
            continue
        fi

        # Vérifier si le fichier est un gzip et le décompresser
        if [[ "$url" == *.gz ]]; then
            if ! gunzip -c "$tempfile" > "$tempfile.unzipped"; then
                echo "Erreur : Fichier gz invalide $url" >> "$log"
                rm "$tempfile"
                continue
            fi
            tempfile="$tempfile.unzipped"
        fi

        # Extraire les chaînes demandées et les programmes
        while IFS=, read -r id name icon; do
            if [ -z "$id" ]; then
                continue  # Ignorer les lignes vides
            fi

            # Ajouter la définition de la chaîne (une seule fois par id)
            if ! grep -q "<channel id=\"$id\">" "$output"; then
                echo "  <channel id=\"$id\">" >> "$output"
                echo "    <display-name>$name</display-name>" >> "$output"
                echo "    <icon src=\"$icon\"/>" >> "$output"
                echo "  </channel>" >> "$output"
            fi
        # Calcul des timestamps pour le décalage
        now=$(date +%s)
        start_filter=$((now - 86400 * jours_avant))
        end_filter=$((now + 86400 * jours_venir))

        # Extraire les programmes pour cette chaîne et dans la plage de temps
        xmlstarlet sel -t \
            -m "//channel[id='$id']/programme[start >= $start_filter and stop <= $end_filter]" \
            -v "concat('  <programme channel=\"$id\" start=\"', start + ($offset * 3600), '\" stop=\"', stop + ($offset * 3600), '\">')" \
            -v "    <title>" -v title -v "</title>" \
            -v "    <desc>" -v desc -v "</desc>" \
            -v "  </programme>" \
            -n "$tempfile" >> "$output.tmp"
    done < choix.txt

    rm -f "$tempfile" "$tempfile.unzipped"
}

# Traiter chaque URL dans epgs.txt
while read -r url; do
    if [ -n "$url" ]; then
        process_epg "$url"
    fi
done < epgs.txt

# Supprimer les doublons et les lignes vides
sort -u "$output.tmp" | grep -v -e '^$' >> "$output"
rm "$output.tmp"

echo '</tv>' >> "$output"
