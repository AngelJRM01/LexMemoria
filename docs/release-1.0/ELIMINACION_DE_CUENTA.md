# Eliminación de cuenta — texto y aceptación de Google Play

## Texto para una página pública

LexMemoria permite solicitar la eliminación de tu cuenta y los datos asociados. En la aplicación, abre Perfil → Cuenta y copias y utiliza la opción de eliminación de cuenta, confirma ELIMINAR y acredita de nuevo la misma identidad Google cuando se solicite. Borrar solo el almacenamiento del móvil no elimina la cuenta remota.

También puedes usar https://lexmemoria-api.onrender.com/account/delete cuando esté configurada y aceptada la identidad web. Si no puedes acceder, contacta con [CORREO PÚBLICO DE SOPORTE] para ejercer tus derechos mediante un procedimiento de identificación proporcionado. No envíes contraseñas, claves o códigos de recuperación al soporte.

La eliminación afecta a los datos activos vinculados a la cuenta y revoca sus sesiones. Las copias de materiales que otras personas recibieron legítimamente pueden conservarse con atribución anonimizada. El alcance/plazo de copias de seguridad y registros será [PLAZO APROBADO E IMPLANTADO]. Una copia JSON o datos locales en otro dispositivo quedan bajo control de quien los conserva.

## Configuración técnica ya existente

- API: /account/delete y /v1/account/delete-with-identity; coordinación Google en el cliente.
- Firebase web: FIREBASE_WEB_API_KEY, proyecto lexmemoria-aa86a y dominio autorizado.
- Contacto: PUBLIC_CONTROLLER_NAME, PUBLIC_SUPPORT_EMAIL y PUBLIC_PRIVACY_POLICY_URL.
- La API actual devuelve pendiente cuando faltan datos de privacidad; no debe anunciarse como política final.

## Prueba obligatoria pendiente con proveedor real

1. Crear cuenta de prueba Google y datos sintéticos en A y B.
2. Exportar sin tokens ni secretos; verificar los datos antes del borrado.
3. Eliminar desde la app; comprobar revocación, ausencia de datos en API y finalización Firebase.
4. Repetir con una cuenta distinta mediante la página web, también sin la app instalada.
5. Interrumpir red entre API y Firebase; reintentar con la misma identidad sin borrar otra cuenta.
6. Confirmar aislamiento de B y retirada de membresías/invitaciones; documentar el efecto en copias de terceros.
7. Documentar retención de backups/logs y proceso de caducidad real.

Estado: las pruebas locales automatizadas no sustituyen esta aceptación real. No facilitar a Play una URL que solo muestra un error o necesita la app para completar la solicitud.
