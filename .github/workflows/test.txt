#!/bin/bash
# ============================================================================== 
# Script: miEPG.sh 
# Version: 3.7
# Function: Combine multiple XML files, rename channels, modify logos, and adjust time
# Combinez plusieurs fichiers XML, renommez les chaînes, modifiez les logos et ajustez l'heure
# ============================================================================== 

# Remove empty lines from input files
# Supprimer les lignes vides des fichiers d'entrée
clean_file() {
    sed -i '/^ *$/d' "$1"
}

# Download and decompress EPG files
# Téléchargez et décompressez les fichiers EPG
download_epg() {
    local epg="$1"
    local epg_count="$2"
    local temp_dir="$3"

    echo " │ Téléchargement et décompression: $epg"
    wget -O "$temp_dir/EPG_temp.xml.gz" -q "$epg" || return 1

    if [ ! -s "$temp_dir/EPG_temp.xml.gz" ] || ! gzip -t "$temp_dir/EPG_temp.xml.gz" 2>/dev/null; then
        echo " └─► ❌ ERROR: le fichier téléchargé est vide ou n'est pas un gzip valide."
        return 1
    fi
    gzip -d -f "$temp_dir/EPG_temp.xml.gz"
}

# Generate channel list from the downloaded XML
# Générer une liste de chaînes à partir du XML téléchargé
generate_channel_list() {
    local epg_count="$1"
    local temp_dir="$2"
    local output_file="$3"

    echo "# Source: $epg" > "$output_file"
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
    ' "$temp_dir/EPG_temp.xml" >> "$output_file"
}

# Handle each channel based on user-defined rules
# Gérer chaque canal en fonction de règles définies par l'utilisateur
process_channels() {
    local channels=("$@")
    
    for channel in "${channels[@]}"; do
        IFS=',' read -r old new logo offset <<< "$(echo "$channel" | xargs)"
        
        contar_channel="$(grep -c "channel=\"$old\"" "$temp_dir/EPG_temp.xml")"
        
        if [ "${contar_channel:-0}" -gt 0 ]; then
            echo " │ Processing channel: $old → $new"
            
            # 1. Retrieve the original logo if no new one in canales.txt
            logo_original=$(sed -n "/<channel id=\"${old}\">/,/<\/channel>/p" "$temp_dir/EPG_temp.xml" | grep "<icon src" | head -1 | sed 's/^[[:space:]]*//')
            
            # 2. Determine which logo to use (new or original)
            logo_final=""
            if [ -n "$logo" ]; then
                logo_final="    <icon src=\"$logo\" />"
            else
                logo_final="    $logo_original"
            fi

            # 3. Create new channel file (EPG_temp01.xml)
            echo "  <channel id=\"$new\">" > "$temp_dir/EPG_temp01.xml"
            
            # 4. Insert display names based on variables.txt
            if [ -f variables.txt ]; then
                while IFS= read -r line; do
                    if [[ $line == display-name=* ]]; then
                        sufijos=$(echo "$line" | cut -d'=' -f2 | sed 's/, /,/g')
                        IFS=',' read -r -a array_etiquetas <<< "$sufijos"
                        for etiq in "${array_etiquetas[@]}"; do
                            etiq_clean=$(echo "$etiq" | xargs)
                            if [ -n "$etiq_clean" ]; then
                                echo "    <display-name>$new $etiq_clean</display-name>" >> "$temp_dir/EPG_temp01.xml"
                            fi
                        done
                    fi
                done < variables.txt
            else
                echo "    <display-name>$new</display-name>" >> "$temp_dir/EPG_temp01.xml"
            fi

            # 5. Insert the logo at the end
            [ -n "$logo_final" ] && echo "$logo_final" >> "$temp_dir/EPG_temp01.xml"
            echo '  </channel>' >> "$temp_dir/EPG_temp01.xml"

            # Summary of changes
            if [ -n "$logo" ]; then
                echo " │ Channel EPG: $old · New name: $new · Logo changed ··· $contar_channel matches"
            else
                echo " │ Channel EPG: $old · New name: $new · Keeping logo ··· $contar_channel matches"
            fi

            # Append to final temporary channel file
            cat "$temp_dir/EPG_temp01.xml" >> "$temp_dir/EPG_temp1.xml"
            sed -i '$!N;/^\(.*\)\n\1$/!P;D' "$temp_dir/EPG_temp1.xml"

            # Processing programs related to this channel
            sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" "$temp_dir/EPG_temp.xml" > "$temp_dir/EPG_temp02.xml"
            sed -i '/<programme/s/\">.*/\"/g' "$temp_dir/EPG_temp02.xml"
            sed -i "s# channel=\"${old}\"##g" "$temp_dir/EPG_temp02.xml"
            sed -i "/<programme/a EPG_temp channel=\"${new}\">" "$temp_dir/EPG_temp02.xml"
            sed -i ':a;N;$!ba;s/\nEPG_temp//g' "$temp_dir/EPG_temp02.xml"

            # Adjust time if offset is provided
            if [[ "$offset" =~ ^[+-]?[0-9]+$ ]]; then
                echo " └─► Adjusting time for the channel $new ($offset hours)"
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
                ' "$temp_dir/EPG_temp02.xml"
            fi

            # Append the modified programmes to the temporary file
            cat "$temp_dir/EPG_temp02.xml" >> "$temp_dir/EPG_temp2.xml"
        else
            echo "        Skipping channel: $old ··· $contar_channel matches"
        fi
    done
}

echo "─── CANAUX DE TRAITEMENT ───"
mapfile -t canales < canales.txt
process_channels "${canales[@]}"


# Main execution starts here
# L'exécution principale commence ici
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

clean_file epgs.txt
clean_file canales.txt

rm -f EPG_temp* canales_epg*.txt

epg_count=0
echo "─── TÉLÉCHARGEMENT des EPG ───"

while IFS=, read -r epg; do
    ((epg_count++))
    download_epg "$epg" "$epg_count" "$temp_dir" && generate_channel_list "$epg_count" "$temp_dir" "canales_epg${epg_count}.txt"
done < epgs.txt

# Assemble final XML
# Assembler le XML final
assemble_xml() {
    local temp_dir="$1"
    local output_file="miEPG.xml"

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<tv generator-info-name=\"miEPG v3.6\" generator-info-url=\"https://github.com/davidmuma/miEPG\">"

        # Insert processed channels
        [ -f "$temp_dir/EPG_temp1.xml" ] && cat "$temp_dir/EPG_temp1.xml"
        
        # Insert filtered programs
        [ -f "$temp_dir/EPG_temp2.xml" ] && cat "$temp_dir/EPG_temp2.xml"
        
        echo '</tv>'
    } > "$output_file"

    echo "─── FINAL XML VALIDATION ───"
    error_log=$(xmllint --noout "$output_file" 2>&1)

    if mycmd; then
        echo " │ The XML file is well-formed."
        
        num_canales=$(grep -c "<channel " "$output_file")
        num_programas=$(grep -c "<programme " "$output_file")
        echo " └─► Channels: $num_canales | Programs: $num_programas"
        
        cp "$output_file" "epg_accumuler.xml"
        echo " epg_accumuler.xml updated for the next session."
    else
        echo " ❌ ERROR: errors were detected in the XML structure."
        echo "──────────────────────────────────────────────────────────────────"
        
        lineas_con_error=$(echo "$error_log" | grep -oP '(?<=miEPG.xml:)\d+' | sort -nu)

        for linea in $lineas_con_error; do
            detalle=$(echo "$error_log" | grep "miEPG.xml:$linea:" | head -1 | cut -d':' -f3-)
            contenido_linea=$(sed -n "${linea}p" "$output_file" | xargs)

            echo "📍 Line $linea:"
            echo "   Error: $detalle"
            echo "   Text: \"$contenido_linea\""
            echo "───"
        done
        
        echo "──────────────────────────────────────────────────────────────────"
        echo " ⚠️ WARNING: epg_accumuler.xml was NOT updated."
    fi
}

# Main execution starts here
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

clean_file epgs.txt
clean_file canales.txt

rm -f "$temp_dir/EPG_temp*" "canales_epg*.txt"

epg_count=0
echo "─── DOWNLOADING EPGs ───"

while IFS=, read -r epg; do
    ((epg_count++))
    download_epg "$epg" "$epg_count" "$temp_dir" && generate_channel_list "$epg_count" "$temp_dir" "canales_epg${epg_count}.txt"
done < epgs.txt



# Assemble the final XML
assemble_xml "$temp_dir"

echo "─── PROCESS COMPLETED ───"






