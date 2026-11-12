# LexMemoria — Encryption technical description

Prepared on 12 November 2026 for the app owner. This is a technical description, not an export licence, ANSSI receipt, classification ruling, signed legal declaration or evidence of an exemption.

## Application identification

App: LexMemoria. Apple App ID: 6833461057. Bundle identifier: es.lexmemoria.app. Version: 1.0.0, build 19. Developer: Ángel Joaquín Rodríguez Mercado. Public contact: armcode.dev@gmail.com. Source revision: 7c2445dd7aef4ee4bd1bf1ed1d30c3c4d0585a2d. Framework: Flutter 3.47.9.

## Main purpose

An educational application for reading legislation, studying with flashcards and retaining study progress. Encryption is used to protect stored study data, account credentials and network communications. The application is not a VPN, a cryptocurrency product or a general-purpose cryptography tool. It does not expose a cryptographic programming interface or configurable encryption algorithms to end users.

## Cryptographic functions

| Component | Function and technical basis |
| --- | --- |
| Local educational state | SQLCipher encrypts the SQLite database. The sqflite_sqlcipher 3.4.1 iOS podspec pins SQLCipher 4.10.0. Upstream defaults are AES-256-CBC, HMAC-SHA-512 and PBKDF2-HMAC-SHA-512, with 256,000 iterations for the main key derivation. These are upstream source defaults, not runtime PRAGMA measurements of the distributed database. |
| iOS SQLCipher provider | The published CocoaPods SQLCipher standard/common subspec specifies SQLCIPHER_CRYPTO_CC and Apple Foundation/Security frameworks. Its crypto_cc implementation uses Apple CommonCrypto. This does not establish that every cryptographic function in the entire Flutter binary is supplied exclusively by Apple. |
| Local key storage | flutter_secure_storage uses iOS Keychain. The application generates a database password on first creation and retains it separately from the database. No real key, password or device identifier is included in this report. |
| Network traffic | HTTPS/TLS protects API, identity and public-content downloads. Dart package:http defaults to IOClient on native platforms; the compiled Flutter/Dart networking stack must be included in a complete implementation inventory. Exact negotiated cipher suites depend on the server and runtime and have not been measured for each endpoint here. |
| Content integrity | The app uses SHA-256 for content and state fingerprints. Hashing is distinguished from confidentiality encryption. |
| User exports | Educational JSON exports are readable plaintext. They are not represented as encrypted backups. |

The application does not introduce a proprietary encryption algorithm. Local SQLCipher encryption is not end-to-end encryption of remotely synchronized data. The server can process the data submitted for synchronization.

## Distribution and compliance status

Apple received build 19 according to the successful upload command. The owner reported it ready for testing. This report is not an independent App Store Connect processing query or proof of physical-device acceptance.

No CCATS number, ECCN determination, ANSSI declaration/authorization/receipt, French exemption ruling or Apple export-compliance approval code is claimed. France availability must reflect the owner's actual distribution decision. An end-user educational purpose alone is not treated here as proof of an export exemption.

ITSAppUsesNonExemptEncryption has not been changed to suppress a compliance prompt. A final value requires the applicable classification. Any ITSAppEncryptionExportComplianceCode must be the genuine code provided by Apple for accepted documentation, not a generated placeholder.

## Sources and verification boundaries

Application source reviewed: mobile/lib/persistence.dart, mobile/lib/store.dart, mobile/lib/remote.dart and mobile/pubspec.lock. These establish use and intent, not a complete disassembly of the distributed IPA.

Published provider specification:
https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/1/2/7/SQLCipher/4.10.0/SQLCipher.podspec.json

Pinned SQLCipher source reviewed:
https://raw.githubusercontent.com/sqlcipher/sqlcipher/v4.10.0/src/sqlcipher.c
https://raw.githubusercontent.com/sqlcipher/sqlcipher/v4.10.0/src/crypto_cc.c

Official Apple export-compliance reference for the owner:
https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/

The official Apple page could not be retrieved from the development environment on 12 November 2026 because its network policy returned CONNECT 403. Consequently this report does not claim that current Apple or French regulatory requirements were independently checked online. The technical source URLs above were retrieved successfully. The developer must provide any governmental document actually requested by the current Apple questionnaire; this technical report cannot substitute for it.
