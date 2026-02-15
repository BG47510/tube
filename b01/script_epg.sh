#!/bin/bash

# --- Configuration ---
EPG_LIST="epg.txt"
CHOIX_FILE="choix.txt"
VARS_FILE="variables.txt"
OUTPUT_FILE="epg_final.xml"
TEMP_DIR="./temp_epg"

# Nettoyage et création du dossier temporaire
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 0. Lecture des variables
[[ -f $VARS_FILE ]] && source $VARS_FILE
DAYS_BEFORE=${jours_avant:-1}
DAYS_AFTER=${jours_venir:-2}

# Calcul des bornes temporelles
START_LIMIT=$(date -d "$DAYS_BEFORE days ago 00:00:00" +"%Y%m%d%H%M%S")
END_LIMIT=$(date -d "$DAYS_AFTER days 23:59:59" +"%Y%m%d%H%M%S")

# Initialisation du fichier final
echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>' > "$OUTPUT_FILE"

# 1. Téléchargement et Fusion des sources
while read -r url; do
    [[ -z "$url" || "$url" == "#"* ]] && continue
    filename=$(basename "$url")
    echo "Téléchargement de $filename..."
    curl -sL "$url" -o "$TEMP_DIR/$filename"
    
    if [[ "$filename" == *.gz ]]; then
        gunzip -f "$TEMP_DIR/$filename"
        filename="${filename%.gz}"
    fi
    
    # Nettoyage des retours de ligne Windows (\r)
    sed -i 's/\r//g' "$TEMP_DIR/$filename"

    # Afficher le contenu du fichier décompressé pour vérification
    echo "--- Contenu de $filename : ---"
    cat "$TEMP_DIR/$filename" | head -n 20  # Affiche les 20 premières lignes
    echo "-------------------------------------"
done < "$EPG_LIST"

# Création d'une base de données temporaire unique pour xmlstarlet
ALL_XML="$TEMP_DIR/all_sources.xml"
echo '<tv>' > "$ALL_XML"
# Extraction brute du contenu entre les balises <tv>
sed -e '1,/<tv/d' -e '/<\/tv>/,$d' "$TEMP_DIR"/*.xml >> "$ALL_XML"
echo '</tv>' >> "$ALL_XML"

# 2. Traitement par chaîne (Boucle principale)
while IFS=',' read -r old_id new_id logo_url offset; do
    [[ -z "$old_id" || "$old_id" == "#"* ]] && continue
    
    old_id=$(echo "$old_id" | xargs)
    new_id=$(echo "$new_id" | xargs)
    offset=$(echo "$offset" | xargs)
    [[ -z "$offset" ]] && offset=0

    echo -n "Traitement : $old_id -> $new_id (Offset: ${offset}h) "

    # Extraction du bloc <channel>
    xmlstarlet sel -t -c "//channel[@id='$old_id'][1]" "$ALL_XML" 2>/dev/null > "$TEMP_DIR/chan.tmp"

    if [[ -s "$TEMP_DIR/chan.tmp" ]]; then
        # Mise à jour ID et Nom
        xmlstarlet ed -u "//channel/@id" -v "$new_id" \
                      -u "//channel/display-name" -v "$new_id" "$TEMP_DIR/chan.tmp" > "$TEMP_DIR/chan_mod.tmp"
        
        # Injection du logo personnalisé
        if [[ -n "$logo_url" ]]; then
            if grep -q "<icon" "$TEMP_DIR/chan_mod.tmp"; then
                xmlstarlet ed -u "//channel/icon/@src" -v "$logo_url" "$TEMP_DIR/chan_mod.tmp" > "$TEMP_DIR/chan_final.tmp"
            else
                xmlstarlet ed -s "//channel" -t elem -n "icon" -v "" \
                              -i "//channel/icon" -t attr -n "src" -v "$logo_url" "$TEMP_DIR/chan_mod.tmp" > "$TEMP_DIR/chan_final.tmp"
            fi
        else
            cp "$TEMP_DIR/chan_mod.tmp" "$TEMP_DIR/chan_final.tmp"
        fi

        echo "Ajout du channel $new_id"
        sed '/<?xml/d' "$TEMP_DIR/chan_final.tmp" >> "$OUTPUT_FILE"
    else
        echo "Aucun channel trouvé pour ID : $old_id"
    fi

    # 3. Extraction et décalage horaire des programmes
    xmlstarlet sel -t -c "//programme[@channel='$old_id']" "$ALL_XML" 2>/dev/null | \
    sed 's/<\/programme>/<\/programme>\n/g' > "$TEMP_DIR/progs_raw.tmp"

    if [[ ! -s "$TEMP_DIR/progs_raw.tmp" ]]; then
        echo "Aucun programme trouvé pour le channel : $old_id"
        continue
    fi

    count=$(gawk -v start_lim="$START_LIMIT" -v end_lim="$END_LIMIT" \
          -v off="$offset" -v old_id="$old_id" -v new_id="$new_id" '
    function shift_time(ts, h) {
        y = substr(ts,1,4); m = substr(ts,5,2); d = substr(ts,7,2)
        H = substr(ts,9,2); M = substr(ts,11,2); S = substr(ts,13,2)
        curr = mktime(y " " m " " d " " H " " M " " S)
        if (curr < 0) return ts
        return strftime("%Y%m%d%H%M%S", curr + (h * 3600))
    }
    {
        if ($0 !~ /<programme/) next
        match($0, /start="([0-9]{14})/, s)
        match($0, /stop="([0-9]{14})/, e)

        t_start = s[1]; t_stop = e[1]
        if (t_start < start_lim || t_start > end_lim) next

        if (off != 0) {
            t_start = shift_time(t_start, off); t_stop = shift_time(t_stop, off)
        }

        line = $0
        sub("start=\"" s[1] "\"", "start=\"" t_start "\"", line)
        sub("stop=\"" e[1] "\"", "stop=\"" t_stop "\"", line)
        sub("channel=\"" old_id "\"", "channel=\"" new_id "\"", line)
        print line
        c++
    }
    END { print c }' "$TEMP_DIR/progs_raw.tmp" >> "$OUTPUT_FILE")

    echo "[$count programmes ajoutés]"
done < "$CHOIX_FILE"

# Fin de la structure XML
echo "</tv>" >> "$OUTPUT_FILE"

# 4. Validation et formatage XML
if command -v xmlstarlet &> /dev/null; then
    echo "Validation de la structure XML..."
    if ! xmlstarlet val "$OUTPUT_FILE"; then
        echo "Erreur : le fichier XML est invalide."
        echo "Contenu de $OUTPUT_FILE :"
        cat "$OUTPUT_FILE"  # Afficher le contenu pour le débogage
        exit 1
    fi

    echo "Optimisation de la structure XML..."
    xmlstarlet fo -s 2 "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
fi

# Compression finale
echo "Compression du fichier final..."
gzip -f "$OUTPUT_FILE"

# Nettoyer le répertoire temporaire
rm -rf "$TEMP_DIR"
echo "---"
echo "Succès : ${OUTPUT_FILE}.gz a été généré."
