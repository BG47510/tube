#!/bin/bash

# Vérification de xmlstarlet
command -v xmlstarlet >/dev/null 2>&1 || { echo "Erreur : xmlstarlet requis"; exit 1; }

# Fichiers
EPG_FINAL="EPG_final.xml"
TMP_FILE="EPG_temp.xml"
DUPLICATES_FILE="programmes_unique.txt"
VARIABLES_FILE="variables.txt"

# Lecture des variables : jours-avant et jours-venir
jours_avant=0
jours_venir=7

if [ -f "$VARIABLES_FILE" ]; then
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        case "$key" in
            "jours-avant") jours_avant=$value ;;
            "jours-venir") jours_venir=$value ;;
        esac
    done < "$VARIABLES_FILE"
fi

# Calcul des bornes de date
date_debut=$(date -d "today - $jours_avant days" +"%Y%m%d")
date_fin=$(date -d "today + $jours_venir days" +"%Y%m%d")
echo "Filtrage des programmes du $date_debut au $date_fin"

# Fonctions
download_and_extract() {
    local url="$1"
    local filename="$2"
    local ext="${url##*.}"
    if [ "$ext" = "gz" ]; then
        wget -O "$filename.gz" -q "$url" || return 1
        gzip -d -f "$filename.gz"
    else
        wget -O "$filename" -q "$url" || return 1
    fi
    [ -s "$filename" ] || { echo "Erreur : fichier vide ou introuvable $url"; return 1; }
}

extract_channel_info() {
    local xmlfile="$1"
    local output="$2"
    xmlstarlet sel -t -m "//channel" -v "@id" -o "," -v "display-name" -o "," -v "icon/@src" -n "$xmlfile" > "$output"
}

update_channel_name() {
    local xmlfile="$1" old_id="$2" new_name="$3"
    if xmlstarlet sel -t -c "//channel[@id='$old_id']" "$xmlfile" >/dev/null; then
        xmlstarlet ed -L -u "//channel[@id='$old_id']/display-name" -v "$new_name" "$xmlfile"
    else
        xmlstarlet ed -L -s "//channel" -t elem -n channel -v "" \
            -i "//channel[last()]" -t attr -n "id" -v "$old_id" \
            -s "//channel[@id='$old_id']" -t elem -n display-name -v "$new_name" "$xmlfile"
    fi
}

update_channel_logo() {
    local xmlfile="$1" old_id="$2" new_logo="$3"
    if xmlstarlet sel -t -v "//channel[@id='$old_id']/icon" "$xmlfile" >/dev/null; then
        xmlstarlet ed -L -u "//channel[@id='$old_id']/icon/@src" -v "$new_logo" "$xmlfile"
    else
        xmlstarlet ed -L -s "//channel" -t elem -n channel -v "" \
            -i "//channel[last()]" -t attr -n "id" -v "$old_id" \
            -s "//channel[@id='$old_id']" -t elem -n icon -v "" \
            -u "//channel[@id='$old_id']/icon/@src" -v "$new_logo" "$xmlfile"
    fi
}

rename_channel() {
    local xmlfile="$1" old_id="$2" new_id="$3"
    xmlstarlet ed -L -u "//channel[@id='$old_id']/@id" -v "$new_id" "$xmlfile"
    xmlstarlet ed -L -u "//programme[@channel='$old_id']/@channel" -v "$new_id" "$xmlfile"
}

adjust_time() {
    perl -e '
        use Time::Piece;
        my ($dt, $offset)=@ARGV;
        my $t=Time::Piece->strptime($dt, "%Y%m%d%H%M%S");
        my $nt=$t->add_seconds($offset*3600);
        print $nt->strftime("%Y%m%d%H%M%S");
    ' "$1" "$2"
}

adjust_programs_for_channel() {
    local xmlfile="$1" channel_id="$2" offset="$3"
    xmlstarlet sel -t -m "//programme[@channel='$channel_id']" -v "@start" -o "|" -v "@stop" -v "@channel" -n "$xmlfile" | \
    while IFS='|' read -r start stop ch; do
        new_start=$(adjust_time "$start" "$offset")
        new_stop=$(adjust_time "$stop" "$offset")
        xmlstarlet ed -L \
            -u "//programme[@channel='$ch' and @start='$start']/@start" -v "$new_start" \
            -u "//programme[@channel='$ch' and @stop='$stop']/@stop" -v "$new_stop" \
            "$xmlfile"
    done
}

# Nettoyage
rm -f "$EPG_FINAL" "$DUPLICATES_FILE"
touch "$DUPLICATES_FILE"

# 1. Télécharger et fusionner
while IFS=, read -r url; do
    filename="EPG_temp.xml"
    download_and_extract "$url" "$filename" || continue
    extract_channel_info "$filename" "channels_info.txt"
    cat "$filename" >> "$EPG_FINAL"
done < "epgs.txt"

# 2. Charger canaux
mapfile -t canaux < "canales.txt"

# 3. Mise à jour canaux et ajustements
for entry in "${canaux[@]}"; do
    IFS=',' read -r old_id new_name logo offset <<< "$entry"
    old_id=$(echo "$old_id" | xargs)
    new_name=$(echo "$new_name" | xargs)
    logo=$(echo "$logo" | xargs)
    offset=$(echo "$offset" | xargs)

    if ! xmlstarlet sel -t -c "//channel[@id='$old_id']" "$EPG_FINAL" >/dev/null; then
        echo "Canal non trouvé: $old_id"
        continue
    fi

    update_channel_name "$EPG_FINAL" "$old_id" "$new_name"
    [ -n "$logo" ] && update_channel_logo "$EPG_FINAL" "$old_id" "$logo"
    rename_channel "$EPG_FINAL" "$old_id" "$new_name"

    if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
        echo "Décalage $offset heures pour $new_name"
        adjust_programs_for_channel "$EPG_FINAL" "$new_name" "$offset"
    fi
done

# 4. Ajouter historique
if [ -f "epg_accumuler.xml" ]; then
    echo "Ajout historique"
    xmlstarlet sel -t -c "//programme" "epg_accumuler.xml" >> "$EPG_FINAL"
fi

# 5. Filtrage période
> "$DUPLICATES_FILE"
xmlstarlet sel -t -m "//programme" -v "@start" -o "|" -v "@stop" -o "|" -v "@channel" -n "$EPG_FINAL" | \
while IFS='|' read -r start stop ch; do
    start_date=${start:0:8}
    if [[ "$start_date" < "$date_debut" || "$start_date" > "$date_fin" ]]; then
        continue
    fi
    key="${ch}_${start}_${stop}"
    if grep -qx "$key" "$DUPLICATES_FILE"; then
        continue
    else
        echo "$key" >> "$DUPLICATES_FILE"
    fi
done

# 6. Nettoyage final
mv "$EPG_FINAL" "$EPG_FINAL"

echo "Traitement terminé. Fichier final : $EPG_FINAL"
