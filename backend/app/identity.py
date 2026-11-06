"""Firebase ID token verification for Google/Apple sign-in.

Certificate downloads use HTTPS trust and Cache-Control; unknown signing keys
refresh once. Tokens, emails and private study content are never logged.
"""
import base64
import json
import math
import threading
import time
import httpx
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column
from .db import Base, uid

CERTS = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com'

class ExternalIdentity(Base):
    __tablename__ = 'external_identities'
    __table_args__ = (UniqueConstraint('issuer', 'subject'),)
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), index=True)
    issuer: Mapped[str] = mapped_column(String(256))
    subject: Mapped[str] = mapped_column(String(128))

class IdentityError(ValueError): pass

class FirebaseVerifier:
    def __init__(self, project, client=None, clock=time.time):
        self.project = project
        self.client = client or httpx.Client(timeout=15)
        self.clock = clock
        self.certificates = {}
        self.expires = 0
        self.lock = threading.Lock()

    def verify(self, token, *, max_auth_age=None):
        if not self.project:
            raise IdentityError('Proveedor de identidad no configurado')
        if not isinstance(token, str) or len(token) > 16000:
            raise IdentityError('Token no válido')
        try:
            encoded_header, encoded_claims, signature = token.split('.')
            def decode(value): return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
            header = json.loads(decode(encoded_header)); claims = json.loads(decode(encoded_claims))
            if not isinstance(header, dict) or header.get('alg') != 'RS256' or not isinstance(header.get('kid'), str):
                raise IdentityError('Firma de identidad no válida')
            with self.lock:
                if self.clock() >= self.expires or header['kid'] not in self.certificates:
                    response = self.client.get(CERTS); response.raise_for_status()
                    certificates = response.json()
                    if not isinstance(certificates, dict): raise IdentityError('Certificados no disponibles')
                    cache = response.headers.get('cache-control', '')
                    age = next((int(p.strip()[8:]) for p in cache.split(',') if p.strip().startswith('max-age=') and p.strip()[8:].isdigit()), 300)
                    self.certificates = certificates; self.expires = self.clock() + min(age, 3600)
                certificate = self.certificates.get(header['kid'])
            if not certificate: raise IdentityError('Clave de firma desconocida')
            key = x509.load_pem_x509_certificate(certificate.encode()).public_key()
            if not isinstance(key, rsa.RSAPublicKey): raise IdentityError('Clave no válida')
            key.verify(decode(signature), (encoded_header + '.' + encoded_claims).encode(), padding.PKCS1v15(), hashes.SHA256())
            now = self.clock()
            if claims.get('aud') != self.project or claims.get('iss') != 'https://securetoken.google.com/' + self.project:
                raise IdentityError('Emisor o audiencia no válidos')
            subject = claims.get('sub')
            if not isinstance(subject, str) or not 1 <= len(subject) <= 128:
                raise IdentityError('Identidad no válida')
            for field in ('exp', 'iat', 'auth_time'):
                if type(claims.get(field)) not in (int, float) or not math.isfinite(claims[field]): raise IdentityError('Fecha de identidad no válida')
            if claims['exp'] <= now or claims['iat'] > now + 30 or claims['auth_time'] > now + 30:
                raise IdentityError('Token caducado o fecha futura')
            if max_auth_age is not None and now - claims['auth_time'] > max_auth_age:
                raise IdentityError('Se requiere una identificación reciente')
            if claims.get('firebase', {}).get('sign_in_provider') not in ('google.com', 'apple.com'):
                raise IdentityError('Proveedor no admitido')
            return {'issuer': claims['iss'], 'subject': subject}
        except IdentityError:
            raise
        except httpx.HTTPError as exc:
            raise IdentityError('Verificación de identidad temporalmente no disponible') from exc
        except Exception as exc:
            raise IdentityError('Token de identidad no válido') from exc
