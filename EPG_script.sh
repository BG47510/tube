#!/bin/bash
# ============================================================================== 
# Script: miEPG.sh 
# Versión: 3.7
# Fonction: Combinez plusieurs fichiers XML, renommez les chaînes, modifiez les logos et réglez l'heure
# https://github.com/davidmuma/miEPG/tree/db7bec4fd21458c28a5674c897abef372727f360
# ============================================================================== 

sed -i '/^ *$/d' epgs.txt
sed -i '/^ *$/d' canales.txt

rm -f EPG_temp* canales_epg*.txt

epg_count=0

echo "─── TÉLÉCHARGEMENT EPGs ───"

while IFS=, read -r epg; do
	((epg_count++))
    extension="${epg##*.}"
    if [ "$extension" = "gz" ]; then
        echo " │ Téléchargement et décompression: $epg"
        wget -O EPG_temp00.xml.gz -q "$epg"
        if [ ! -s EPG_temp00.xml.gz ]; then
            echo " └─► ❌ ERREUR: le fichier téléchargé est vide ou n'a pas été téléchargé correctement"
            continue
        fi
        if ! gzip -t EPG_temp00.xml.gz 2>/dev/null; then
            echo " └─► ❌ ERREUR: le fichier n'est pas un gzip valide"
            continue
        fi
        gzip -d -f EPG_temp00.xml.gz
    else
        echo " │ Téléchargement: $epg"
        wget -O EPG_temp00.xml -q "$epg"
        if [ ! -s EPG_temp00.xml ]; then
            echo " └─► ❌ ERREUR: le fichier téléchargé est vide ou n'a pas été téléchargé correctement"
            continue
        fi
    fi
	if [ -f EPG_temp00.xml ]; then
        listado="canales_epg${epg_count}.txt"
        echo " └─► Générer une liste de chaînes: $listado"
        echo "# Source: $epg" > "$listado"
		awk '
		/<channel / {
		    match($0, /id="([^"]+)"/, a); id=a[1]; name=""; logo="";
		}
		/<display-name[^>]*>/ && name == "" {
		    match($0, /<display-name[^>]*>([^<]+)<\/display-name>/, a);
		    name=a[1];
		}
		/<icon src/ {
		    match($0, /src="([^"]+)"/, a); logo=a[1];
		}
		/<\/channel>/ {
		    print id "," name "," logo;
		}
		' EPG_temp00.xml >> "$listado"
		cat EPG_temp00.xml >> EPG_temp.xml
        sed -i 's/></>\n</g' EPG_temp.xml		
    fi	
done < epgs.txt

echo "─── CANAUX DE TRAITEMENT ───"

mapfile -t canales < canales.txt
for i in "${!canales[@]}"; do
    IFS=',' read -r old new logo offset <<< "${canales[$i]}"
    old="$(echo "$old" | xargs)"
    new="$(echo "$new" | xargs)"
    logo="$(echo "$logo" | xargs)"
    offset="$(echo "$offset" | xargs)"
    if [[ "$logo" =~ ^[+-]?[0-9]+$ ]] && [[ -z "$offset" ]]; then
        offset="$logo"
        logo=""
    fi
    canales[$i]="$old,$new,$logo,$offset"
done

# Lire les étiquettes de variables.txt
etiquetas_sed=""
if [ -f variables.txt ]; then
    # Extrayez ce qui se trouve après display-name=, supprimez les espaces et séparez par des virgules
    sufijos=$(grep "display-name=" variables.txt | cut -d'=' -f2 | sed 's/, /,/g')
    IFS=',' read -r -a array_etiquetas <<< "$sufijos"
    
    # Nous créons une liste de commandes pour sed (elles seront insérées à partir de la ligne 3)
    linea_ins=3
    for etiq in "${array_etiquetas[@]}"; do
        etiq_clean=$(echo "$etiq" | xargs) # Espaces propres
        if [ -n "$etiq_clean" ]; then
            etiquetas_sed="${etiquetas_sed}${linea_ins}i\  <display-name>${new} ${etiq_clean}</display-name>\n"
            ((linea_ins++))
        fi
    done
fi

for linea in "${canales[@]}"; do
    IFS=',' read -r old new logo offset <<< "$linea"
    contar_channel="$(grep -c "channel=\"$old\"" EPG_temp.xml)"
	if [ "${contar_channel:-0}" -gt 0 ]; then
	
        # 1. Extrayez le logo original au cas où il n'y en aurait pas de nouveau dans canales.txt
        logo_original=$(sed -n "/<channel id=\"${old}\">/,/<\/channel>/p" EPG_temp.xml | grep "<icon src" | head -1 | sed 's/^[[:space:]]*//')
        
        # 2. Définir quel logo utiliser (le nouveau ou celui extrait)
        logo_final=""
        if [ -n "$logo" ]; then
            logo_final="    <icon src=\"${logo}\" />"
        else
            logo_final="    $logo_original"
        fi

        # 3. Créez le nouveau fichier de chaîne à partir de zéro (EPG_temp01.xml)
        echo "  <channel id=\"${new}\">" > EPG_temp01.xml
        
        # 4. Insérer des noms basés sur variables.txt
        if [ -f variables.txt ]; then
            sufijos=$(grep "display-name=" variables.txt | cut -d'=' -f2 | sed 's/, /,/g')
            IFS=',' read -r -a array_etiquetas <<< "$sufijos"
            
            for etiq in "${array_etiquetas[@]}"; do
                etiq_clean=$(echo "$etiq" | xargs)
                if [ -n "$etiq_clean" ]; then
                    echo "    <display-name>${new} ${etiq_clean}</display-name>" >> EPG_temp01.xml
                fi
            done
        else
            # S'il n'y a pas de variables.txt, on met au moins le nom de base
            echo "    <display-name>${new}</display-name>" >> EPG_temp01.xml
        fi

        # 5. Insérer le logo à la fin
        [ -n "$logo_final" ] && echo "$logo_final" >> EPG_temp01.xml
        echo '  </channel>' >> EPG_temp01.xml

        # Téléchargement
        if [ -n "$logo" ]; then
            echo " │ Nombre EPG: $old · Nouveau nom: $new · changement logo ··· $contar_channel coïncidences"
        else
            echo " │ Nombre EPG: $old · Nouveau nom: $new · Maintenir logo ··· $contar_channel coïncidences"
        fi

        cat EPG_temp01.xml >> EPG_temp1.xml
        sed -i '$!N;/^\(.*\)\n\1$/!P;D' EPG_temp1.xml

        sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" EPG_temp.xml > EPG_temp02.xml
        sed -i '/<programme/s/\">.*/\"/g' EPG_temp02.xml
        sed -i "s# channel=\"${old}\"##g" EPG_temp02.xml
        sed -i "/<programme/a EPG_temp channel=\"${new}\">" EPG_temp02.xml
        sed -i ':a;N;$!ba;s/\nEPG_temp//g' EPG_temp02.xml
  
		if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
			echo " └─► Réglage de l'heure dans le canal $new ($offset horas)"
			export OFFSET="$offset"
			export NEW_CHANNEL="$new"
            
			perl -MDate::Parse -MDate::Format -i'' -pe '
			BEGIN {
				$offset_sec = $ENV{OFFSET} * 3600;
				$new_channel_name = $ENV{NEW_CHANNEL};
			}
			if (/<programme start="([^"]+) (\+?\d+)" stop="([^"]+) (\+?\d+)" channel="[^"]+">/) {
				my ($start_time_str, $start_tz, $stop_time_str, $stop_tz) = ($1, $2, $3, $4);

				my $start_fmt = substr($start_time_str, 0, 4) . "-" .
								substr($start_time_str, 4, 2) . "-" .
								substr($start_time_str, 6, 2) . " " .
								substr($start_time_str, 8, 2) . ":" .
								substr($start_time_str, 10, 2) . ":" .
								substr($start_time_str, 12, 2);

				my $stop_fmt = substr($stop_time_str, 0, 4) . "-" .
							   substr($stop_time_str, 4, 2) . "-" .
							   substr($stop_time_str, 6, 2) . " " .
							   substr($stop_time_str, 8, 2) . ":" .
							   substr($stop_time_str, 10, 2) . ":" .
							   substr($stop_time_str, 12, 2);

				my $start = str2time("$start_fmt $start_tz") + $offset_sec;
				my $stop = str2time("$stop_fmt $stop_tz") + $offset_sec;

				my $start_formatted = time2str("%Y%m%d%H%M%S $start_tz", $start);
				my $stop_formatted = time2str("%Y%m%d%H%M%S $stop_tz", $stop);

				s/<programme start="[^"]+" stop="[^"]+" channel="[^"]+">/<programme start="$start_formatted" stop="$stop_formatted" channel="$new_channel_name">/;
			}
			' EPG_temp02.xml
		fi
  
        cat EPG_temp02.xml >> EPG_temp2.xml
  
    else
        echo "        Sauter une chaîne: $old ··· $contar_channel coïncidences"
    fi
done

echo "─── LIMITES TEMPORAIRES DE TRAITEMENT ET CUMULATION ───"

# 1. Assurez-vous que EPG_temp2.xml existe (là où les nouveaux programmes ont été ajoutés) et ajoutez l'historique de epg_acumulado.xml à ce même fichier.
if [ -f epg_acumulado.xml ]; then
    echo " Programmes de sauvetage epg_acumulado.xml..."
    sed -n '/<programme/,/<\/programme>/p' epg_acumulado.xml >> EPG_temp2.xml
fi

# 2. Lire les variables du jour à partir de variables.txt
dias_pasados=$(grep "dias-pasados=" variables.txt | cut -d'=' -f2 | xargs)
dias_pasados=${dias_pasados:-0}

dias_futuros=$(grep "dias-futuros=" variables.txt | cut -d'=' -f2 | xargs)
dias_futuros=${dias_futuros:-99}

# 3. Calculer les dates limites (format XMLTV)
fecha_corte_pasado=$(date -d "$dias_pasados days ago 00:00" +"%Y%m%d%H%M%S")
fecha_corte_futuro=$(date -d "$dias_futuros days 02:00" +"%Y%m%d%H%M%S")

echo " Nettoyage Passé: Maintenir depuis $fecha_corte_pasado ($dias_pasados días)"
echo " Nettoyage futur: Limité à $fecha_corte_futuro ($dias_futuros días)"

# 4. Filtre Perl avancé: Déduplication + Rapport de répartition
perl -i -ne '
    BEGIN { 
        $c_old = "'$fecha_corte_pasado'"; 
        $c_new = "'$fecha_corte_futuro'"; 
        %visto=(); 
        $pasados=0; $futuros=0; $duplicados=0; $aceptados=0;
    }
    if (/<programme start="(\d{14})[^"]+" stop="[^"]+" channel="([^"]+)">/) {
        $inicio = $1; $canal = $2;
        $llave = "$inicio-$canal"; 
        if ($inicio < $c_old) { $pasados++; $imprimir = 0; }
        elsif ($inicio > $c_new) { $futuros++; $imprimir = 0; }
        elsif ($visto{$llave}++) { $duplicados++; $imprimir = 0; }
        else { $aceptados++; $imprimir = 1; }
    }
    print if $imprimir;
    if (/<\/programme>/) { $imprimir = 0; }
    END { 
        print STDERR " ─► Ajouté/Maintenu: $aceptados\n";
        print STDERR " ─►️ Passés supprimés: $pasados\n";
        print STDERR " ─►️ Contrats à terme supprimés: $futuros\n";
        print STDERR " ─►️ Les doublons éliminés: $duplicados\n";
    }
' EPG_temp2.xml

date_stamp=$(date +"%d/%m/%Y %R")
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<tv generator-info-name=\"miEPG v3.6\" generator-info-url=\"https://github.com/davidmuma/miEPG\">"
    
    # Insérez les chaînes (avec leurs variantes et logos que nous avons traités auparavant)
    [ -f EPG_temp1.xml ] && cat EPG_temp1.xml
    
    # Insérer les programmes (nouveau + ancien filtré)
    [ -f EPG_temp2.xml ] && cat EPG_temp2.xml
    
    echo '</tv>'
} > miEPG.xml

echo "─── VALIDATION FINALE DU XML ───"

# Nous exécutons xmllint capturant toutes les erreurs
# 2>&1 rediriger les erreurs vers le flux standard afin qu'elles puissent être enregistrées dans la variable
error_log=$(xmllint --noout miEPG.xml 2>&1)

if [ $? -eq 0 ]; then
    echo " │ Le fichier XML est parfaitement formé."
    
    num_canales=$(grep -c "<channel " miEPG.xml)
    num_programas=$(grep -c "<programme " miEPG.xml)
    echo " └─► Canaux: $num_canales | Programmes: $num_programas"

    cp miEPG.xml epg_acumulado.xml
    echo " epg_accumulated.xml mis à jour pour la prochaine session."
else
    echo " ❌ ERREUR: des erreurs ont été détectées dans la structure XML."
    echo "──────────────────────────────────────────────────────────────────"
    
    # Nous extrayons tous les numéros de ligne uniques rapportés par xmllint
    lineas_con_error=$(echo "$error_log" | grep -oP '(?<=miEPG.xml:)\d+' | sort -nu)

    echo "Récapitulatif des lignes comportant des erreurs:"
    for linea in $lineas_con_error; do
        # Nous recherchons le message xmllint spécifique à cette ligne
        detalle=$(echo "$error_log" | grep "miEPG.xml:$linea:" | head -1 | cut -d':' -f3-)
        
        echo "📍 Línea $linea:"
        echo "   Erreur: $detalle"
        # Nous montrons le contenu réel de cette ligne dans le fichier
        contenido_linea=$(sed -n "${linea}p" miEPG.xml | xargs)
        echo "   Texte: \"$contenido_linea\""
        echo "───"
    done
    
    echo "──────────────────────────────────────────────────────────────────"
    echo " ⚠️ AVERTISSEMENT: epg_acumulado.xml n'a PAS été mis à jour."
fi

# Nettoyage des fichiers de session temporaires
rm -f EPG_temp* 2>/dev/null
echo "─── PROCESSUS TERMINÉ ───"
