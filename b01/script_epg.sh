#!/bin/bash

# Répertoire de travail
WORKSPACE="${GITHUB_WORKSPACE}/b01"

# Fichiers d'entrée
EPG_FILE_LIST="$WORKSPACE/epg.txt"
CHOIX_FILE="$WORKSPACE/choix.txt"
VARIABLES_FILE="$WORKSPACE/variables.txt"
OUTPUT_XML="$WORKSPACE/final.xml"
TEMP_XML="$WORKSPACE/temp.xml"
CHANNEL_IDS="$WORKSPACE/channel_ids.txt"

# Afficher le contenu du répertoire
echo "Contenu du répertoire courant :"
ls -l "$WORKSPACE"

# Vérification de l'existence des fichiers
if [ ! -f "$EPG_FILE_LIST" ]; then
    echo "Erreur : le fichier $EPG_FILE_LIST n'existe pas."
    exit 1
fi

if [ ! -f "$CHOIX_FILE" ]; then
    echo "Erreur : le fichier $CHOIX_FILE n'existe pas."
    exit 1
fi

if [ ! -f "$VARIABLES_FILE" ]; then
    echo "Erreur : le fichier $VARIABLES_FILE n'existe pas."
    exit 1
fi

# Lire les jours avant et après depuis variables.txt
source "$VARIABLES_FILE"
today=$(date -u +%Y%m%d)
start_date=$(date -u -d "$today - $jours_avant days" +%Y%m%d)
end_date=$(date -u -d "$today + $jours_venir days" +%Y%m%d)

# Initialize the output file
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUTPUT_XML"
echo '<!DOCTYPE tv SYSTEM "xmltv.dtd">' >> "$OUTPUT_XML"
echo '<tv>' >> "$OUTPUT_XML"

Générateur de code
générateur code
Nous avons programmé cet outil pour générer du code source dans différents langages de programmation.
Bonjour, je suis l'IA génératrice de code, comment puis-je vous aider ?
Peux-tu décripter ce code
Extraction des channel IDs depuis les fichiers XML
while read -r url; do
response=$(curl -sL -o temp.gz -w "%{http_code}" "$url")
if [ "$response" != "200" ]; then
echo "Erreur lors du téléchargement de $url : code HTTP $response"
else
file temp.gz # Affiche le type de fichier téléchargé
gzip -dc "temp.gz" | xmllint --xpath '//channel/@id' - >> "$CHANNEL_IDS"
rm -f temp.gz # Supprime le fichier temporaire après utilisation
fi

Voici une explication détaillée de ce script shell qui extrait des identifiants de channels depuis des fichiers XML téléchargés :

while read -r url; do
    response=$(curl -sL -o temp.gz -w "%{http_code}" "$url")
    if [ "$response" != "200" ]; then
        echo "Erreur lors du téléchargement de $url : code HTTP $response"
    else
        file temp.gz  # Affiche le type du fichier téléchargé
        gzip -dc "temp.gz" | xmllint --xpath '//channel/@id' - >> "$CHANNEL_IDS"
        rm -f temp.gz  # Supprime le fichier temporaire après traitement
    fi
done
Détails étape par étape :
Boucle while read -r url; do :

Lit chaque ligne d'une entrée (souvent un fichier ou une sortie de commande) contenant une URL.
La variable $url contient l'URL à traiter.
Téléchargement avec curl :

curl -sL -o temp.gz -w "%{http_code}" "$url" :
-sL : silencieux (-s) et suit les redirections (-L).
-o temp.gz : télécharge le contenu dans un fichier temporaire nommé temp.gz.
-w "%{http_code}" : affiche le code de statut HTTP à la fin de la requête.
La sortie (le code HTTP) est capturée dans la variable $response.
Vérification du code de réponse HTTP :

Si $response n'est pas égal à "200" (succès), affiche un message d'erreur.
Sinon, continue le traitement.
Vérification du type de fichier téléchargé :

file temp.gz : affiche le type du fichier temp.gz, utile pour vérifier qu'il s'agit bien d'un fichier compressé ou XML attendu.
Décompression et extraction des IDs :

gzip -dc "temp.gz" : décompresse le fichier gzip et envoie le contenu stdout.
| xmllint --xpath '//channel/@id' - :
Utilise xmllint pour extraire tous les attributs id des éléments <channel> dans le XML.
Le - indique que le XML est lu depuis stdin (le flux de la décompression).
>> "$CHANNEL_IDS" : ajoute les IDs extraits à un fichier dont le nom est contenu dans la variable $CHANNEL_IDS.
Suppression du fichier temporaire :

rm -f temp.gz : supprime le fichier téléchargé pour libérer de l'espace.
Fin de la boucle :

La boucle continue jusqu'à ce qu'il n'y ait plus d'URLs à lire.
Résumé général :
Ce script lit une liste d'URLs, télécharge chaque fichier, vérifie si le téléchargement a réussi, affiche le type du fichier, extrait tous les attributs id des balises <channel> dans le XML, et sauvegarde ces IDs dans un fichier spécifique, tout en nettoyant les fichiers temporaires.

Souhaitez-vous que je vous fournisse une version améliorée ou commentée du script, ou une explication plus approfondie de certains éléments ?

Je veux bien voir la version améliorée
Voici une version améliorée et plus robuste de votre script, avec des commentaires détaillés, une gestion d’erreurs améliorée, et quelques bonnes pratiques :

#!/bin/bash

# Fichier où seront stockés tous les IDs extraits
CHANNEL_IDS="channel_ids.txt"

# S'assurer que le fichier de sortie est vide avant de commencer
> "$CHANNEL_IDS"

# Lire chaque URL depuis un fichier ou une entrée standard
while IFS= read -r url; do
    echo "Traitement de l'URL : $url"

    # Télécharger le fichier, capturer le code HTTP
    response=$(curl -sL -o temp.gz -w "%{http_code}" "$url")
    
    # Vérifier si le téléchargement a réussi
    if [ "$response" != "200" ]; then
        echo "Erreur lors du téléchargement de $url : code HTTP $response" >&2
        continue  # Passer à la prochaine URL
    fi

    # Vérifier le type de fichier téléchargé
    file_type=$(file temp.gz)
    echo "Type de fichier : $file_type"

    # Vérifier si le fichier est bien un gzip ou un XML
    if echo "$file_type" | grep -q "gzip compressed data"; then
        # Décompresser et extraire les IDs
        gzip -dc "temp.gz" | xmllint --xpath '//channel/@id' - >> "$CHANNEL_IDS"
    elif echo "$file_type" | grep -q "XML"; then
        # Si c'est déjà un XML non compressé
        xmllint --xpath '//channel/@id' "temp.gz" >> "$CHANNEL_IDS"
    else
        echo "Fichier inattendu pour $url" >&2
    fi

    # Nettoyer le fichier temporaire
    rm -f temp.gz
done < "$EPG_FILE_LIST"


# Suppression des doublons
sort -u "$CHANNEL_IDS" -o "$CHANNEL_IDS"

# Traitement selon le fichier choix.txt
declare -A CHANNEL_MAP
while IFS=',' read -r ancien_id nouveau_id logo_url offset_h; do
    CHANNEL_MAP["$ancien_id"]="$nouveau_id,$logo_url,$offset_h"
done < "$CHOIX_FILE"

# Traitement des fichiers XML
while read -r url; do
    gzip -dc "$url" | while read -r line; do
        if [[ $line == *"<channel "* ]]; then
            channel_id=$(echo "$line" | sed -n 's/.*id="\([^"]*\)".*/\1/p')
            if [[ -n "${CHANNEL_MAP[$channel_id]}" ]]; then
                new_info=(${CHANNEL_MAP[$channel_id]//,/ })
                new_id=${new_info[0]}
                logo_url=${new_info[1]}
                line=$(echo "$line" | sed "s/id=\"$channel_id\"/id=\"$new_id\"/")
                if [[ ! -z $logo_url ]]; then
                    line=$(echo "$line" | sed "s|src=\"[^\"]*\"|src=\"$logo_url\"|")
                fi
                echo "$line" >> "$TEMP_XML"
            fi
        elif [[ $line == *"<programme "* ]]; then
            start_time=$(echo "$line" | sed -n 's/.*start="\([^"]*\)".*/\1/p')
            stop_time=$(echo "$line" | sed -n 's/.*stop="\([^"]*\)".*/\1/p')
            channel_id=$(echo "$line" | sed -n 's/.*channel="\([^"]*\)".*/\1/p')
            if [[ -n "${CHANNEL_MAP[$channel_id]}" ]]; then
                offset_h=${CHANNEL_MAP[$channel_id]//,*}
                if [[ ! -z "$offset_h" ]]; then
                    offset_seconds=$((offset_h * 3600))
                    start_time=$(date -u -d "$start_time + $offset_seconds seconds" +%Y%m%d%H%M%S)
                    stop_time=$(date -u -d "$stop_time + $offset_seconds seconds" +%Y%m%d%H%M%S)
                fi
                line=$(echo "$line" | sed "s/start=\"[^\"]*\"/start=\"$start_time\"/")
                line=$(echo "$line" | sed "s/stop=\"[^\"]*\"/stop=\"$stop_time\"/")
                echo "$line" >> "$TEMP_XML"
            fi
        fi
    done
done < "$EPG_FILE_LIST"

# Suppression des doublons dans le fichier temporaire
awk '!seen[$0]++' "$TEMP_XML" >> "$OUTPUT_XML"
rm "$TEMP_XML"

# Fermeture de la structure XML finale
echo '</tv>' >> "$OUTPUT_XML"

# Validation de l'XML final
if xmllint --noout "$OUTPUT_XML"; then
    echo "XML final valide créé : $OUTPUT_XML"
else
    echo "Erreur de validation XML."
    rm "$OUTPUT_XML"
fi

# Nettoyage des fichiers temporaires
rm "$CHANNEL_IDS"
