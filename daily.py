import yt_dlp

def recuperer_flux_public_senat():
    url_page = "https://www.publicsenat.fr/direct"
    
    # Options pour extraire uniquement l'URL du flux sans télécharger
    ydl_opts = {
        'format': 'best',
        'quiet': True,
        'no_warnings': True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Extraction des informations de la page
            info = ydl.extract_info(url_page, download=False)
            
            # L'URL du flux direct m3u8
            url_flux = info.get('url')
            
            if url_flux:
                print("URL du flux direct récupérée :")
                print(url_flux)
                return url_flux
            else:
                print("Impossible de trouver l'URL du flux.")
    except Exception as e:
        print(f"Erreur lors de la récupération : {e}")

if __name__ == "__main__":
    recuperer_flux_public_senat()