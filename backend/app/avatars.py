"""Decode raster images and re-encode without EXIF or external references."""
import base64
import io
import warnings
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_BYTES = 1_000_000
MAX_PIXELS = 4_000_000


def sanitize_avatar(encoded):
    try:
        raw = base64.b64decode(encoded, validate=True)
        if not raw or len(raw) > MAX_BYTES:
            raise ValueError('Imagen máxima: 1 MB')
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as original:
                if original.format not in ('PNG', 'JPEG', 'WEBP') or getattr(original, 'n_frames', 1) != 1:
                    raise ValueError('Usa una imagen estática PNG, JPEG o WebP')
                if original.width * original.height > MAX_PIXELS:
                    raise ValueError('Imagen máxima: cuatro millones de píxeles')
                original.load()
                image = ImageOps.exif_transpose(original).convert('RGB')
                image.thumbnail((256, 256))
                # New pixel buffer: no original metadata, EXIF, ICC or comments.
                clean = Image.new('RGB', image.size); clean.paste(image)
                output = io.BytesIO(); clean.save(output, format='JPEG', quality=85)
                return base64.b64encode(output.getvalue()).decode('ascii')
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise ValueError('No se puede validar esta imagen') from exc


def google_avatar(token,verifier,expected_identity,client=None):
    """Fetch a verified account's Google-hosted picture once, then store pixels.

    No arbitrary remote URL input, redirects, cookies, credentials or original
    metadata. Other users never cause a request to the provider's image host.
    """
    import json
    from urllib.parse import urlsplit
    import httpx
    identity=verifier.verify(token,max_auth_age=300)
    if identity!=expected_identity:raise ValueError('Selecciona la identidad vinculada a esta cuenta')
    payload=token.split('.')[1]
    claims=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
    url=claims.get('picture','')
    if not isinstance(url,str) or len(url)>2048:raise ValueError('Google no proporciona una imagen válida')
    parsed=urlsplit(url)
    host=parsed.hostname or ''
    if parsed.scheme!='https' or not (host=='googleusercontent.com' or host.endswith('.googleusercontent.com')) or parsed.username or parsed.password or parsed.port not in (None,443) or parsed.fragment:
        raise ValueError('La imagen debe proceder del servicio de imágenes de Google')
    owned_client=client is None
    transport=client or httpx.Client(timeout=10,follow_redirects=False)
    try:
        with transport.stream('GET',url,follow_redirects=False) as response:
            if response.status_code!=200:raise ValueError('No se pudo obtener la imagen')
            if not response.headers.get('content-type','').lower().startswith('image/'):
                raise ValueError('Respuesta de imagen no válida')
            raw=bytearray()
            for chunk in response.iter_bytes(16384):
                raw.extend(chunk)
                if len(raw)>MAX_BYTES:raise ValueError('Imagen demasiado grande')
        return sanitize_avatar(base64.b64encode(raw).decode())
    except httpx.HTTPError:
        raise ValueError('No se pudo descargar la imagen') from None
    finally:
        if owned_client:transport.close()
