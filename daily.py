import yt_dlp
import requests
import re

def recuperer_direct_public_senat():
    # URL de la page et ID de secours (le direct permanent de Public Sénat)
    page_url = "https://www.publicsenat.fr/direct"
    fallback_id = "x7r7m99" 
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }

    print("--- Analyse de la page Public Sénat ---")
    try:
        response = requests.get(page_url, headers=headers, timeout=10)
        html = response.text
        
        # Tentative de détection de l'ID Dailymotion dans le code source
        # Recherche de formats variés : "x7r7m99", "video/x7r7m99", "embed/x7r7m99"
        match = re.search(r'(?:dailymotion\.com/(?:video|embed/video/)|data-video-id="|videoID\\":\\")([a-zA-Z0-9]{7})', html)
        
        if match:
            video_id = match.group(1)
            print(f"ID détecté sur la page : {video_id}")
        else:
            print(f"ID non détecté dynamiquement. Utilisation de l'ID permanent : {fallback_id}")
            video_id = fallback_id

        # Extraction de l'URL M3U8 avec yt-dlp
        dm_url = f"https://www.dailymotion.com/video/{video_id}"
        ydl_opts = {
            'format': 'best',
            'quiet': True,
            'no_warnings': True,
            'force_generic_extractor': False
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(dm_url, download=False)
            return info.get('url')

    except Exception as e:
        return f"Erreur lors de l'extraction : {str(e)}"

if __name__ == "__main__":
    url_final = recuperer_direct_public_senat()
    print("\n--- URL M3U8 POUR VOTRE IPTV ---")
    print(url_final)
