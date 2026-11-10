# Anexo técnico de LexMemoria — 10 de noviembre de 2026

Inventario generado por lectura del código, sin conectar a servicios privados. Una ruta o componente no acredita aceptación de producción. Las rutas auxiliares pueden tener condiciones de configuración y autorización.

## API: 98 declaraciones de ruta

| Método | Ruta | Archivo | Función |
| --- | --- | --- | --- |
| DELETE | `/v1/account` | `backend/app/main.py` | `erase` |
| DELETE | `/v1/account/avatar` | `backend/app/accounts.py` | `delete_avatar` |
| DELETE | `/v1/account/sessions/{session_id}` | `backend/app/accounts.py` | `revoke` |
| DELETE | `/v1/collaboration/contacts/{relationship_id}` | `backend/app/collaboration.py` | `remove_contact` |
| DELETE | `/v1/collaboration/decks/{deck_id}/publication` | `backend/app/collaboration.py` | `withdraw_publication` |
| DELETE | `/v1/collaboration/groups/{group_id}` | `backend/app/collaboration.py` | `delete_group` |
| DELETE | `/v1/collaboration/groups/{group_id}/resources/{resource_id}` | `backend/app/collaboration.py` | `remove_resource` |
| DELETE | `/v1/collaboration/invitations/{invitation_id}` | `backend/app/collaboration.py` | `cancel` |
| DELETE | `/v1/collaboration/{target_id}/members/{user_id}` | `backend/app/collaboration.py` | `remove_member` |
| GET | `/account/delete` | `backend/app/main.py` | `deletion_page` |
| GET | `/account/privacy` | `backend/app/main.py` | `privacy_contact_page` |
| GET | `/health` | `backend/app/main.py` | `health` |
| GET | `/invite` | `backend/app/collaboration.py` | `invite_landing` |
| GET | `/v1/account/avatar` | `backend/app/accounts.py` | `avatar` |
| GET | `/v1/account/export` | `backend/app/main.py` | `export` |
| GET | `/v1/account/profile` | `backend/app/accounts.py` | `get_profile` |
| GET | `/v1/account/security` | `backend/app/accounts.py` | `security` |
| GET | `/v1/admin/collaboration` | `backend/app/collaboration.py` | `moderation` |
| GET | `/v1/admin/collaboration/decks/{deck_id}` | `backend/app/collaboration.py` | `moderation_preview` |
| GET | `/v1/admin/ingestions` | `backend/app/main.py` | `ingestions` |
| GET | `/v1/auth/session` | `backend/app/main.py` | `current_session` |
| GET | `/v1/cards/by-client/{client_id}` | `backend/app/main.py` | `card_by_client` |
| GET | `/v1/cards/{id}/history` | `backend/app/main.py` | `card_history` |
| GET | `/v1/collaboration/catalogue` | `backend/app/collaboration.py` | `catalogue` |
| GET | `/v1/collaboration/contacts` | `backend/app/collaboration.py` | `contacts` |
| GET | `/v1/collaboration/copies/{copy_id}/updates` | `backend/app/collaboration.py` | `preview_copy_updates` |
| GET | `/v1/collaboration/decks` | `backend/app/collaboration.py` | `shared_decks` |
| GET | `/v1/collaboration/decks/{deck_id}` | `backend/app/collaboration.py` | `shared_content` |
| GET | `/v1/collaboration/decks/{deck_id}/members` | `backend/app/collaboration.py` | `deck_members` |
| GET | `/v1/collaboration/groups` | `backend/app/collaboration.py` | `groups` |
| GET | `/v1/collaboration/groups/{group_id}` | `backend/app/collaboration.py` | `group_details` |
| GET | `/v1/collaboration/invitations` | `backend/app/collaboration.py` | `invitations` |
| GET | `/v1/collaboration/reports` | `backend/app/collaboration.py` | `own_reports` |
| GET | `/v1/decks` | `backend/app/main.py` | `decks` |
| GET | `/v1/legal-updates` | `backend/app/main.py` | `updates` |
| GET | `/v1/library/coverage` | `backend/app/main.py` | `coverage` |
| GET | `/v1/library/norms` | `backend/app/main.py` | `norms` |
| GET | `/v1/library/norms/{id}` | `backend/app/main.py` | `norm` |
| GET | `/v1/library/norms/{id}/units` | `backend/app/main.py` | `units` |
| GET | `/v1/library/norms/{id}/versions` | `backend/app/main.py` | `versions` |
| GET | `/v1/library/units/{id}/compare` | `backend/app/main.py` | `compare` |
| GET | `/v1/notifications` | `backend/app/main.py` | `notifications` |
| GET | `/v1/payments/entitlements` | `backend/app/main.py` | `entitlements` |
| GET | `/v1/public/identity-config` | `backend/app/main.py` | `public_identity_configuration` |
| GET | `/v1/reports` | `backend/app/main.py` | `reports` |
| GET | `/v1/study/today` | `backend/app/main.py` | `today` |
| GET | `/v1/sync/status` | `backend/app/main.py` | `synchronization_status` |
| GET | `/v1/workspace` | `backend/app/main.py` | `workspace` |
| POST | `/v1/account/avatar/google` | `backend/app/accounts.py` | `import_google_avatar` |
| POST | `/v1/account/check-deletion-identity` | `backend/app/main.py` | `check_deletion_identity` |
| POST | `/v1/account/delete-with-identity` | `backend/app/main.py` | `erase_with_identity` |
| POST | `/v1/account/identities/{identity_id}/unlink` | `backend/app/accounts.py` | `unlink_identity` |
| POST | `/v1/account/sessions/revoke-others` | `backend/app/accounts.py` | `revoke_others` |
| POST | `/v1/admin/collaboration/accounts/{account_id}/restriction` | `backend/app/collaboration.py` | `restrict` |
| POST | `/v1/admin/collaboration/reports/{report_id}/decision` | `backend/app/collaboration.py` | `decide_report` |
| POST | `/v1/admin/collaboration/{deck_id}/decision` | `backend/app/collaboration.py` | `moderate` |
| POST | `/v1/admin/editorial/{id}/approve` | `backend/app/main.py` | `approve` |
| POST | `/v1/auth/guest` | `backend/app/main.py` | `guest` |
| POST | `/v1/auth/link` | `backend/app/main.py` | `oidc_link` |
| POST | `/v1/auth/logout` | `backend/app/main.py` | `logout` |
| POST | `/v1/auth/oidc` | `backend/app/main.py` | `oidc_login` |
| POST | `/v1/auth/recover` | `backend/app/main.py` | `recover` |
| POST | `/v1/auth/recover-idempotent` | `backend/app/main.py` | `recover` |
| POST | `/v1/auth/recovery-code` | `backend/app/main.py` | `recovery_code` |
| POST | `/v1/auth/refresh` | `backend/app/main.py` | `refresh` |
| POST | `/v1/cards` | `backend/app/main.py` | `card` |
| POST | `/v1/cards/lookup` | `backend/app/main.py` | `cards_lookup` |
| POST | `/v1/collaboration/blocks/{user_id}` | `backend/app/collaboration.py` | `block_user` |
| POST | `/v1/collaboration/contacts/link` | `backend/app/collaboration.py` | `contact_link` |
| POST | `/v1/collaboration/contacts/requests` | `backend/app/collaboration.py` | `contact_request` |
| POST | `/v1/collaboration/contacts/{request_id}/accept` | `backend/app/collaboration.py` | `accept_contact` |
| POST | `/v1/collaboration/copies/{copy_id}/updates` | `backend/app/collaboration.py` | `apply_copy_updates` |
| POST | `/v1/collaboration/decks/{deck_id}/copy` | `backend/app/collaboration.py` | `copy_deck` |
| POST | `/v1/collaboration/decks/{deck_id}/publication` | `backend/app/collaboration.py` | `request_publication` |
| POST | `/v1/collaboration/groups` | `backend/app/collaboration.py` | `create_group` |
| POST | `/v1/collaboration/groups/{group_id}/resources` | `backend/app/collaboration.py` | `add_resource` |
| POST | `/v1/collaboration/invitations/accept` | `backend/app/collaboration.py` | `accept` |
| POST | `/v1/collaboration/invitations/{invitation_id}/accept` | `backend/app/collaboration.py` | `accept_direct` |
| POST | `/v1/collaboration/reports` | `backend/app/collaboration.py` | `report` |
| POST | `/v1/collaboration/{target_id}/invitations` | `backend/app/collaboration.py` | `create_invitation` |
| POST | `/v1/decks` | `backend/app/main.py` | `deck` |
| POST | `/v1/exams/attempts` | `backend/app/main.py` | `attempt` |
| POST | `/v1/exams/attempts/{id}/submit` | `backend/app/main.py` | `submit` |
| POST | `/v1/legal-updates/subscriptions` | `backend/app/main.py` | `follow` |
| POST | `/v1/notifications/{id}/read` | `backend/app/main.py` | `read_notification` |
| POST | `/v1/payments/validate` | `backend/app/main.py` | `payment` |
| POST | `/v1/private` | `backend/app/main.py` | `private` |
| POST | `/v1/reports` | `backend/app/main.py` | `report` |
| POST | `/v1/reviews` | `backend/app/main.py` | `review` |
| PUT | `/v1/account/avatar` | `backend/app/accounts.py` | `upload_avatar` |
| PUT | `/v1/account/profile` | `backend/app/accounts.py` | `update_profile` |
| PUT | `/v1/admin/accounts/{account_id}/entitlement` | `backend/app/accounts.py` | `assign_entitlement` |
| PUT | `/v1/cards/{id}` | `backend/app/main.py` | `edit_card` |
| PUT | `/v1/collaboration/cards/{card_id}` | `backend/app/collaboration.py` | `shared_edit` |
| PUT | `/v1/collaboration/groups/{group_id}` | `backend/app/collaboration.py` | `update_group` |
| PUT | `/v1/collaboration/{target_id}/members/{user_id}` | `backend/app/collaboration.py` | `change_role` |
| PUT | `/v1/private/{id}` | `backend/app/main.py` | `edit` |
| PUT | `/v1/workspace` | `backend/app/main.py` | `save_workspace` |

## Cliente: 54 componentes públicos de interfaz

Incluye páginas y componentes reutilizables; no son necesariamente destinos de navegación independientes.

| Componente | Archivo |
| --- | --- |
| `PersonalProfilePage` | `mobile/lib/account_pages.dart` |
| `AccountSecurityPage` | `mobile/lib/account_pages.dart` |
| `SyncConflictsPage` | `mobile/lib/account_pages.dart` |
| `AutoSyncHost` | `mobile/lib/auto_sync.dart` |
| `PageControls` | `mobile/lib/browsing_widgets.dart` |
| `CollaborationPage` | `mobile/lib/collaboration.dart` |
| `CollaborationListPage` | `mobile/lib/collaboration.dart` |
| `SharedDeckPage` | `mobile/lib/collaboration.dart` |
| `StudyGroupPage` | `mobile/lib/collaboration.dart` |
| `DeckAccessPage` | `mobile/lib/collaboration.dart` |
| `CopyUpdatesPage` | `mobile/lib/collaboration.dart` |
| `FullEuropeanLibraryPage` | `mobile/lib/european_library.dart` |
| `FullEuropeanNormPage` | `mobile/lib/european_library.dart` |
| `EuropeanUnitPage` | `mobile/lib/european_library.dart` |
| `EuropeanResourcesPage` | `mobile/lib/european_library.dart` |
| `ExerciseInput` | `mobile/lib/exercises.dart` |
| `LibraryPage` | `mobile/lib/library.dart` |
| `NormPage` | `mobile/lib/library.dart` |
| `LegalParagraph` | `mobile/lib/library.dart` |
| `ReaderPage` | `mobile/lib/library.dart` |
| `ComparePage` | `mobile/lib/library.dart` |
| `UpdatesPage` | `mobile/lib/library.dart` |
| `AppBootstrap` | `mobile/lib/main.dart` |
| `LexMemoria` | `mobile/lib/main.dart` |
| `ModerationPage` | `mobile/lib/moderation.dart` |
| `PlannerPage` | `mobile/lib/planning.dart` |
| `ExamPage` | `mobile/lib/planning.dart` |
| `ProgressPage` | `mobile/lib/planning.dart` |
| `ProfilePage` | `mobile/lib/profile.dart` |
| `AccountPage` | `mobile/lib/profile.dart` |
| `SettingsPage` | `mobile/lib/profile.dart` |
| `PlansPage` | `mobile/lib/profile.dart` |
| `PrivacyPage` | `mobile/lib/profile.dart` |
| `RecoveryPage` | `mobile/lib/profile.dart` |
| `WelcomePage` | `mobile/lib/shell.dart` |
| `AppShell` | `mobile/lib/shell.dart` |
| `HomePage` | `mobile/lib/shell.dart` |
| `StudyPage` | `mobile/lib/study.dart` |
| `CardEditor` | `mobile/lib/study.dart` |
| `ReviewPage` | `mobile/lib/study.dart` |
| `CardListPage` | `mobile/lib/study.dart` |
| `CardHistoryPage` | `mobile/lib/study.dart` |
| `PreparedDecksPage` | `mobile/lib/study.dart` |
| `ArchivedExercisesPage` | `mobile/lib/study.dart` |
| `UniversityPage` | `mobile/lib/university.dart` |
| `CoursePage` | `mobile/lib/university.dart` |
| `Paper` | `mobile/lib/widgets.dart` |
| `Badge` | `mobile/lib/widgets.dart` |
| `PageBody` | `mobile/lib/widgets.dart` |
| `SearchPageBody` | `mobile/lib/widgets.dart` |
| `Details` | `mobile/lib/widgets.dart` |
| `Section` | `mobile/lib/widgets.dart` |
| `EmptyState` | `mobile/lib/widgets.dart` |
| `WorkspacePage` | `mobile/lib/workspace.dart` |

## Entidades y almacenamiento

Servidor: Record, Account, Token, RecoveryCode, Mutation y Audit, con agregados por tipo, historial e índices auxiliares. No se presenta como modelo relacional V2 íntegro.

Cliente: estado privado, tarjetas, estados SM-2, revisiones, notas, cursos, plan, lectura, simulacros, colas y referencias. Credenciales separadas; corpus público fuera del backup privado.

Pruebas automatizadas en backend/tests y mobile/test; nativas en mobile/integration_test. CI declarada en .github/workflows/ci.yml. La ejecución remota de esa CI no se infiere de su existencia.
