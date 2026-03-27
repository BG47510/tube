import yt_dlp
import requests
import re

def recuperer_direct_public_senat():
    page_url = "https://www.publicsenat.fr/direct"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }

    try:
        # 1. On récupère le code source de la page Public Sénat
        response = requests.get(page_url, headers=headers)
        response.raise_for_status()
        
        # 2. On cherche l'ID Dailymotion (ex: x7r7m99 ou similaire)
        # On cherche dans les balises iframe ou les scripts de configuration
        match = re.search(r'dailymotion\.com/(?:video|embed/video)/([a-zA-Z0-9]+)', response.text)
        
        if not match:
            # Alternative : chercher l'ID dans les attributs data-video-id
            match = re.search(r'data-video-id="([a-zA-Z0-9]+)"', response.text)

        if match:
            video_id = match.group(1)
            dm_url = f"https://www.dailymotion.com/video/{video_id}"
            print(f"ID trouvé : {video_id} | URL source : {dm_url}")
            
            # 3. On utilise yt-dlp sur l'URL Dailymotion directe
            ydl_opts = {
                'format': 'best',
                'quiet': True,
                'no_warnings': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(dm_url, download=False)
                return info.get('url')
        else:
            return "Impossible d'extraire l'ID vidéo de la page."

    except Exception as e:
        return f"Erreur : {str(e)}"

if __name__ == "__main__":
    flux_url = recuperer_direct_public_senat()
    print("\n--- URL M3U8 POUR VOTRE IPTV ---")
    print(flux_url)
