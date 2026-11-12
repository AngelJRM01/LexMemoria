# LexMemoria — Annexe technique de cryptographie

Document préparatoire du 12 novembre 2026. Ce document n'est pas un formulaire officiel, une déclaration déposée, un récépissé ANSSI, une autorisation ou une décision d'exemption. Les renseignements techniques doivent être reportés dans le formulaire officiel en vigueur après vérification du régime applicable.

## Identification du logiciel

Nom : LexMemoria. Identifiant Apple : 6833461057. Identifiant de lot : es.lexmemoria.app. Version : 1.0.0, build 19. Développeur et contact public : Ángel Joaquín Rodríguez Mercado, armcode.dev@gmail.com. Révision source : 7c2445dd7aef4ee4bd1bf1ed1d30c3c4d0585a2d. Framework : Flutter 3.47.9. Distribution envisagée : téléchargement pour iOS via l'App Store, y compris en France.

L'identité juridique du déclarant, sa qualité, son adresse et les éventuels documents justificatifs doivent être renseignés dans le dossier officiel privé par le titulaire. Ils ne doivent pas être publiés dans le dépôt du logiciel.

## Fonction principale

Application éducative destinée à l'étude des textes juridiques : lecture de législation, fiches de mémorisation, exercices et répétition espacée. La cryptographie protège les données d'étude stockées localement, les informations d'authentification et les échanges réseau. L'application ne fournit pas de VPN ni d'outil cryptographique général à l'utilisateur.

## Fonctions cryptographiques

La base de données locale utilise SQLCipher. Le plugin iOS sqflite_sqlcipher 3.4.1 fixe SQLCipher 4.10.0. Les valeurs par défaut du code source SQLCipher examiné sont AES-256-CBC, HMAC-SHA-512 et PBKDF2-HMAC-SHA-512, avec 256 000 itérations pour la dérivation principale. Il s'agit des paramètres par défaut du code source, non de mesures d'exécution du binaire distribué.

Le podspec CocoaPods SQLCipher standard/common déclare SQLCIPHER_CRYPTO_CC. L'implémentation crypto_cc utilise Apple CommonCrypto. Cela ne prouve pas que toutes les fonctions cryptographiques du binaire Flutter proviennent exclusivement du système Apple.

La clé de la base de données est conservée séparément au moyen de Keychain et de flutter_secure_storage. Aucune clé réelle, aucun mot de passe et aucun identifiant d'appareil ne sont joints à cette annexe.

Les communications distantes utilisent HTTPS/TLS. Les suites négociées dépendent du serveur et de l'environnement d'exécution. L'application utilise aussi SHA-256 pour vérifier ou identifier certains contenus. Les exports pédagogiques JSON sont lisibles, sans chiffrement de confidentialité supplémentaire. Le chiffrement local ne constitue pas un chiffrement de bout en bout des données synchronisées sur le serveur.

Aucun algorithme cryptographique propriétaire n'est développé par l'application. L'utilisateur ne dispose pas d'une interface lui permettant de sélectionner ou programmer un algorithme de chiffrement.

## Sources techniques

Code applicatif : mobile/lib/persistence.dart, mobile/lib/store.dart, mobile/lib/remote.dart et mobile/pubspec.lock.

https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/1/2/7/SQLCipher/4.10.0/SQLCipher.podspec.json

https://raw.githubusercontent.com/sqlcipher/sqlcipher/v4.10.0/src/sqlcipher.c

https://raw.githubusercontent.com/sqlcipher/sqlcipher/v4.10.0/src/crypto_cc.c

## Limites et état administratif

Aucun numéro de déclaration, récépissé ANSSI, CCATS, classement ECCN ou code Apple d'approbation n'est revendiqué. Aucune conclusion juridique sur une exemption n'est établie par cette annexe. Le site officiel de l'ANSSI doit être consulté pour déterminer le formulaire et les pièces applicables avant dépôt. La préparation de ce document ne constitue pas sa transmission à une autorité.
