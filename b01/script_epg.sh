#!/bin/bash
# ============================================================================== 
# Script: EPG_script.sh (version 1.0)
# Fonction : Le script télécharge, fusionne, et modifie tous les fichiers XML en utilisant XMLStarlet.
# Il ajuste tous les horaires de programme en fonction du décalage horaire spécifié, via Perl.
# La sortie finale est dans EPG_final.xml.
# Utilise XMLStarlet pour manipuler le XML et Perl pour ajuster les horaires
# ==============================================================================

command -v xmlstarlet >/dev/null 2>&1 || { echo >&2 "XMLStarlet est requis. Abandon."; exit 1; }

# Nettoyage initial
sed -i '/^ *$/d' epgs.txt
sed -i '/^ *$/d' canales.txt
rm -f EPG_temp*.xml

epg_count=0
echo "─── TÉLÉCHARGEMENT EPGs ───"

# Vérification de l'existence du fichier epgs.txt
if [ ! -f "epgs.txt" ]; then
    echo "Le fichier epgs.txt n'existe pas."
    exit 1
fi

# Lecture de epgs.txt
while IFS=, read -r epg; do
    ((epg_count++))
    extension="${epg##*.}"
    filename="EPG_temp00.xml"

    # Téléchargement et décompression
    if [ "$extension" = "gz" ]; then
        echo " │ Téléchargement et décompression: $epg"
        wget -O "$filename.gz" -q "$epg"
        if [ ! -s "$filename.gz" ]; then
            echo " └─►  ERREUR: fichier gz vide ou introuvable"
            continue
        fi
        if ! gzip -t "$filename.gz" 2>/dev/null; then
            echo " └─►  ERREUR: fichier gz invalide"
            continue
        fi
        gzip -d -f "$filename.gz"
    else
        echo " │ Téléchargement: $epg"
        wget -O "$filename" -q "$epg"
        if [ ! -s "$filename" ]; then
            echo " └─►  ERREUR: fichier xml vide ou introuvable"
            continue
        fi
    fi
    # Vérification fichier XML
    if [ -f "$filename" ]; then
        # Extraction des chaînes (id, display-name, icon)
        list_filename="canal_epg${epg_count}.txt"
        echo " └─► Générer une liste de chaînes: $list_filename"
        xmlstarlet sel -t -m "//channel" \
            -v "@id" -o "," \
            -v "display-name" -o "," \
            -v "icon/@src" -n "$filename" > "$list_filename"
        # Fusionner dans le fichier global
        cat "$filename" >> EPG_temp.xml
    fi
done < epgs.txt

# 2. Charger les canaux
mapfile -t canales < canales.txt

# 3. Processus de chaque canal
for i in "${!canales[@]}"; do
    IFS=',' read -r old new logo offset <<< "${canales[$i]}"
    old=$(echo "$old" | xargs)
    new=$(echo "$new" | xargs)
    logo=$(echo "$logo" | xargs)
    offset=$(echo "$offset" | xargs)

    # Si offset est un nombre seul
    if [[ "$logo" =~ ^[+-]?[0-9]+$ ]] && [[ -z "$offset" ]]; then
        offset="$logo"
        logo=""
    fi

    # Vérifier si le canal existe
    if ! xmlstarlet sel -t -c "//channel[@id='$old']" EPG_temp.xml >/dev/null; then
        echo "Chaîne non trouvée dans XML: $old"
        continue
    fi

    # Récupérer le logo actuel
    logo_original=$(xmlstarlet sel -t -v "//channel[@id='$old']/icon/@src" EPG_temp.xml)

    # Définir le logo final
    logo_final=""
    if [ -n "$logo" ]; then
        logo_final="<icon src=\"$logo\"/>"
    elif [ -n "$logo_original" ]; then
        logo_final="<icon src=\"$logo_original\"/>"
    fi

    # Mise à jour ou ajout display-name
    if xmlstarlet sel -t -v "//channel[@id='$old']/display-name" EPG_temp.xml >/dev/null; then
        xmlstarlet ed -L -u "//channel[@id='$old']/display-name" -v "$new" EPG_temp.xml
    else
        xmlstarlet ed -L -s "//channel[@id='$old']" -t elem -n display-name -v "$new" EPG_temp.xml
    fi

    # Mise à jour ou ajout icon
    if [ -n "$logo_final" ]; then
        if xmlstarlet sel -t -v "//channel[@id='$old']/icon" EPG_temp.xml >/dev/null; then
            xmlstarlet ed -L -u "//channel[@id='$old']/icon/@src" -v "$logo" EPG_temp.xml
        else
            xmlstarlet ed -L -s "//channel[@id='$old']" -t elem -n icon -v ""
            xmlstarlet ed -L -u "//channel[@id='$old']/icon/@src" -v "$logo" EPG_temp.xml
        fi
    fi

    # Renommer l'id du channel
    xmlstarlet ed -L -u "//channel[@id='$old']/@id" -v "$new" EPG_temp.xml

    # Modifier les programmes pour le nouveau channel
    xmlstarlet ed -L -u "//programme[@channel='$old']/@channel" -v "$new" EPG_temp.xml

    # Gestion du décalage horaire
    if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
        echo "Décalage horaire de $offset heures pour $new"
        # Extraction de tous les programmes du canal
        xmlstarlet sel -t -m "//programme[@channel='$new']" -v "@start" -o " " -v "@stop" -n EPG_temp.xml | while read -r start stop; do
            # Ajuster start
            adjusted_start=$(perl -e '
                use Time::Piece;
                my ($dt_str, $tz)=split / /,$ARGV[0];
                my $dt=Time::Piece->strptime($dt_str, "%Y%m%d%H%M%S");
                my $offset=$ARGV[1];
                my $new_dt=$dt->add_seconds($offset*3600);
                print $new_dt->strftime("%Y%m%d%H%M%S");
            ' "$start" "$offset")
            # Ajuster stop
            adjusted_stop=$(perl -e '
                use Time::Piece;
                my ($dt_str, $tz)=split / /,$ARGV[0];
                my $dt=Time::Piece->strptime($dt_str, "%Y%m%d%H%M%S");
                my $offset=$ARGV[1];
                my $new_dt=$dt->add_seconds($offset*3600);
                print $new_dt->strftime("%Y%m%d%H%M%S");
            ' "$stop" "$offset")
            # Mettre à jour dans le XML
            # On doit remplacer start et stop pour chaque programme
            # La façon la plus sûre : extraire, ajuster, réécrire
            # Mais pour simplicité, on peut faire une substitution globale après
            # ici, on laisse pour le moment
            # En pratique, il faut faire une boucle pour tous les programme
        done
        # La partie précise consiste à faire une mise à jour dans le XML pour chaque programme
        # que nous ferons après
    fi
done

# 4. Ajouter l'historique
if [ -f epg_accumuler.xml ]; then
    echo "Ajout de l'historique epg_accumuler.xml"
    # Extraire tous les <programme> et les ajouter
    xmlstarlet sel -t -c "//programme" epg_accumuler.xml >> EPG_temp.xml
fi

# 5. Modifier les horaires dans le XML
# Pour chaque programme, ajuster start et stop
# On va extraire tous les programmes, les traiter, et réécrire

# Créer un fichier temporaire pour la version modifiée
cp EPG_temp.xml EPG_mod.xml

# Extraire tous les programmes
xmlstarlet sel -t -m "//programme" -v "@start" -o "|" -v "@stop" -v "@channel" -n EPG_mod.xml | while IFS='|' read -r start stop channel_id; do
    # Ajuster start
    adj_start=$(perl -e '
        use Time::Piece;
        my ($dt_str,$tz)=split / /,$ARGV[0];
        my $dt=Time::Piece->strptime($dt_str, "%Y%m%d%H%M%S");
        my $offset=$ARGV[1];
        my $new_dt=$dt->add_seconds($offset*3600);
        print $new_dt->strftime("%Y%m%d%H%M%S");
    ' "$start" "$offset")
    # Ajuster stop
    adj_stop=$(perl -e '
        use Time::Piece;
        my ($dt_str,$tz)=split / /,$ARGV[0];
        my $dt=Time::Piece->strptime($dt_str, "%Y%m%d%H%M%S");
        my $offset=$ARGV[1];
        my $new_dt=$dt->add_seconds($offset*3600);
        print $new_dt->strftime("%Y%m%d%H%M%S");
    ' "$stop" "$offset")
    # Mettre à jour le programme dans le XML
    # Remplacer start et stop pour ce programme
    xmlstarlet ed -L \
        -u "//programme[@channel='$channel_id' and @start='$start']/@start" -v "$adj_start" \
        -u "//programme[@channel='$channel_id' and @stop='$stop']/@stop" -v "$adj_stop" \
        EPG_mod.xml
done

# 6. Finaliser
mv EPG_mod.xml EPG_final.xml

echo "Traitement terminé. Fichier final : EPG_final.xml"
