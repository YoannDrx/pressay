# Audit compte, BYOK, Cloud, synchronisation et paiement

## Conclusion exécutive

Le dépôt contient davantage qu'une simple maquette Cloud : authentification, tokens Keychain, entitlements signés, quotas, chiffrement E2EE, approbation d'appareils et récupération sont représentés dans le code. Cette profondeur reste insuffisante pour une commercialisation sans staging production-shaped et revue externe.

BYOK suit de bonnes fondations — Keychain, migration, redaction, providers multiples — mais « provider présent » ne signifie pas « contrat validé ». Chaque fournisseur et chaque famille de modèles doit passer le même protocole.

Le paiement n'est pas contenu dans le dépôt desktop, mais le dépôt frère `pressay-cloud` implémente Stripe Checkout/portail/webhooks, StoreKit 2, App Store Server Notifications v2 et la projection unifiée des entitlements. Ses tests source passent ; les matrices Stripe Test et StoreKit Sandbox/TestFlight restent néanmoins des release gates externes.

## Incident Google du 18 août 2026

Le callback Google et l'échange OAuth 2.1 PKCE ont réussi dans l'application native. L'échec `internal_error` intervenait ensuite pendant `POST /v1/accounts/bootstrap` : une installation bêta avait conservé `https://api.press-say.app`, domaine encore servi par le backend commercial historique, alors que le client 2.0 attend le contrat du nouveau control plane.

Correction livrée côté desktop :

- migration de schéma 8 des anciennes installations bêta vers `https://pressay-cloud-staging.vercel.app` ;
- maintien de `api.press-say.app` pour une future version stable, sans bascule silencieuse de la production ;
- décodage des deux enveloppes d'erreur API, historique et moderne ;
- erreur de compte explicite sans remise en cause de la dictée locale ;
- test unitaire de migration et exécution de la suite Rust complète.

Preuve staging du 18 août 2026 : health 200, readiness base 200, configuration desktop auth 200, clé publique d'entitlements Ed25519 conforme 200, entitlements sans session 401 et sync sans session 401. Les 75 tests du dépôt Cloud passent. Le validateur vérifie aussi que le JWKS expose exactement la clé publique attendue et jamais la clé privée. Le parcours Google interactif doit encore être rejoué par un utilisateur dans le nouveau binaire, car il nécessite le compte et le navigateur de l'opérateur.

La production ne doit pas être réassignée au nouveau backend pour contourner cet incident. Le cutover exige d'abord la migration ou le rapprochement des comptes, entitlements Stripe/StoreKit, appareils et suppressions, avec sauvegarde et rollback documentés.

## Compte et authentification

### Preuves présentes

- magic link et fournisseurs sociaux Google/Apple exposés dans l'interface compte ;
- deep-link/callback et snapshot de session dans la couche Cloud ;
- bearer token stocké dans Keychain ;
- déconnexion et suppression de compte exposées ;
- état Free/Pro, usage et quotas ;
- allowlist d'hôtes PresSay Cloud et distinction staging/production.

### Matrice staging obligatoire

| Scénario                     | Attendu                                                          | Preuve à conserver                         |
| ---------------------------- | ---------------------------------------------------------------- | ------------------------------------------ |
| Magic link valide            | Session liée au bon compte/appareil/audience.                    | Trace redacted + assertion client/backend. |
| Lien expiré                  | Refus clair, nouveau lien possible.                              | Code d'erreur stable.                      |
| Replay du même callback      | Deuxième échange refusé/idempotent.                              | Test automatisé anti-rejeu.                |
| Google/Apple annulé          | Retour local sans session partielle.                             | Test UI + état Keychain.                   |
| Callback pour autre audience | Refus fail-closed.                                               | Test contractuel.                          |
| Première connexion           | Free local inchangé ; entitlement récupéré.                      | Parcours natif.                            |
| Reconnexion                  | Tokens remplacés, ancien token révoqué.                          | Inspection backend.                        |
| Backend indisponible         | Dictée locale intacte ; statut compte non trompeur.              | Test offline natif.                        |
| Offline grace                | Règle documentée, bornée et liée au dernier entitlement signé.   | Test horloge/expiration.                   |
| Deux Macs                    | Appareils distincts et entitlement cohérent.                     | Test matériel/VM si acceptable.            |
| Déconnexion                  | Token local supprimé ; sync stoppée.                             | Vérification Keychain/réseau.              |
| Suppression compte           | Données serveur supprimées, appareils révoqués, local explicite. | Rapport backend + UX.                      |

Gate : aucune activation commerciale Cloud avant passage de cette matrice sur un environnement utilisant les mêmes mécanismes de clés, audiences, quotas et révocation que la production.

## Entitlements et quotas

Le client vérifie un entitlement EdDSA lié à l'issuer, l'audience, l'account, l'appareil, l'expiration et une révision. Les tests à ajouter couvrent :

- signature invalide, clé inconnue et rotation de clé ;
- mauvais compte, appareil ou bundle DMG/MAS ;
- horloge en avance/retard et expiration pendant une opération ;
- downgrade, remboursement et révocation prioritaires sur cache offline ;
- réponse plus ancienne que la révision locale ;
- quota atteint pendant une requête concurrente ;
- backend indisponible sans désactivation du Free local.

La matrice `Capabilities` doit être déterministe côté backend et côté client. Le serveur signe des droits atomiques ; le frontend ne déduit pas Pro d'un simple plan ou d'un prix.

## Synchronisation E2EE

### Périmètre actuel

La sync allowliste modes personnalisés, profils d'application, dictionnaire et préférence de mode actif. Sont exclus : transcripts, audio, historique, texte sélectionné, prompts et clés BYOK. Ce périmètre doit rester un test exécutable, pas seulement une convention.

Le protocole documenté utilise clés d'appareil X25519, chiffrement XChaCha20-Poly1305, approbation d'appareil et code de récupération. Les scénarios de [`docs/CLOUD_SYNC.md`](../CLOUD_SYNC.md) sont normatifs.

### Validation opératoire

1. Premier appareil : création des clés, premier snapshot et restauration après relance.
2. Second appareil : état pending sans accès aux données.
3. Approbation : enveloppe lisible seulement par l'appareil approuvé.
4. Refus/révocation : aucune nouvelle sync ; rotation selon threat model.
5. Récupération : consommation unique, réponse réseau perdue, reprise idempotente.
6. Conflits : modifications concurrentes de mode/dictionnaire/profil avec résultat documenté.
7. Payload malformé, ancienne version et ciphertext altéré : rejet sans perte locale.
8. Suppression de compte : données serveur et clés d'enveloppe supprimées.
9. Allowlist négative : injecter transcript/audio/prompt/clé et prouver qu'ils ne sont pas sérialisés.
10. Logs/crash reports : aucune donnée sensible ni matériel cryptographique.

Gate : revue cryptographique et threat-model externe avant activation payante. La revue doit couvrir serveur, protocoles de récupération, rotation et comportement des sauvegardes Keychain, pas seulement les primitives.

## BYOK

### Fondations trouvées

- service Keychain dédié `app.pressay.desktop.byok` ;
- validation des identifiants provider ;
- set/get/delete, et settings ne renvoyant que le booléen « configured » ;
- migration d'anciennes valeurs sérialisées avec report si Keychain indisponible ;
- clients OpenAI-compatible et Anthropic ;
- URL sanitization, structured-output flags, retry de paramètres de raisonnement et tests de redaction.

### Fournisseurs à valider

| Provider              | Auth/transport à vérifier                 | Particularités                                       | Gate                   |
| --------------------- | ----------------------------------------- | ---------------------------------------------------- | ---------------------- |
| OpenAI                | Bearer, base URL officielle, timeouts.    | Structured outputs et paramètres par modèle.         | Mock + smoke réel.     |
| Z.AI                  | Schéma/token et endpoint courant.         | Compatibilité modèles et erreurs.                    | Mock + smoke réel.     |
| OpenRouter            | Bearer, headers éventuels, routing.       | Modèles hétérogènes ; erreurs upstream.              | Mock + smoke réel.     |
| Anthropic             | `x-api-key`, version API, content blocks. | Format non OpenAI, refus/outils.                     | Mock + smoke réel.     |
| Groq                  | OpenAI-compatible.                        | Rate limits et modèle retiré.                        | Mock + smoke réel.     |
| Cerebras              | OpenAI-compatible.                        | Paramètres supportés et streaming/non-streaming.     | Mock + smoke réel.     |
| Bedrock Mantle        | Auth fournie par intégration Mantle.      | Région, credentials temporaires, modèle.             | Environnement dédié.   |
| Endpoint personnalisé | URL, TLS, modèle manuel.                  | SSRF, localhost, réponse invalide, certificat.       | Revue sécurité + mock. |
| Apple Intelligence    | Framework local Apple.                    | Matériel, OS, région, langue, disponibilité runtime. | Matériel compatible.   |

Pour chaque ligne, exécuter : clé valide/invalide/remplacée/supprimée ; liste modèle et modèle manuel ; 401/403/404/408/429/5xx ; timeout/DNS/offline ; JSON invalide/UTF-8/empty ; structured outputs supportés/non supportés ; paramètre de raisonnement refusé ; annulation ; texte long ; redaction des logs.

### Disclosure avant première requête

Afficher une fiche concise : fournisseur, endpoint (host uniquement), type de contenu envoyé, raison, rétention relevant du fournisseur, lien politique, route de retour et option annuler. Le consentement est enregistré par provider/endpoint et réaffiché si l'endpoint change.

Les prompts exacts et réponses restent locaux sauf ce qui est nécessaire à la requête ; aucune donnée utilisateur dans les smoke tests.

## Historique et confidentialité

Le stockage local chiffre texte et audio avec une master key Keychain et prévoit des migrations plaintext. À valider :

- historique réellement désactivé sur une installation fraîche ;
- permissions POSIX et protection des fichiers temporaires ;
- crash entre écriture et renommage ;
- expiration séparée texte/audio et nettoyage au démarrage ;
- suppression sans entrée orpheline, preview ou cache ;
- sauvegarde/restauration macOS et conséquence d'une Keychain perdue ;
- aucun historique, transcript ou audio dans sync, export config, logs ou crash reports.

Une suppression sécurisée physique n'est pas garantie sur SSD/APFS ; l'UX doit promettre suppression logique et destruction de clé quand applicable, pas un effacement matériel absolu.

## Paiement DMG — Stripe

### Architecture recommandée

1. L'app demande au backend une Checkout Session authentifiée.
2. Le navigateur ouvre Stripe Checkout ; l'app ne manipule pas de carte.
3. Les webhooks Stripe sont vérifiés et idempotents côté serveur.
4. Le backend projette l'état d'abonnement vers des capabilities atomiques.
5. L'app récupère un entitlement signé lié au compte/appareil/audience.
6. Le portail client gère facture, moyen de paiement et annulation.

Ne jamais octroyer Pro à partir du seul redirect de succès. La source de vérité est le webhook traité et l'entitlement signé.

### Matrice Stripe

- nouvelle souscription mensuelle/annuelle ;
- essai éventuel, avec et sans moyen de paiement ;
- upgrade/downgrade et prorata ;
- renouvellement, échec, dunning et récupération ;
- annulation immédiate/fin de période ;
- remboursement partiel/complet et chargeback ;
- taxes, devise et facture ;
- webhook dupliqué, hors ordre, retardé et signature invalide ;
- compte supprimé avec abonnement actif ;
- achat fait avec autre adresse puis liaison explicite ;
- Test Clocks pour renouvellement/expiration.

Gate : tous les scénarios produisent l'entitlement attendu, sans bloquer le Free local.

## Paiement Mac App Store — StoreKit

Le binaire MAS ne contient aucun lien, CTA ou appel Stripe. Il utilise des produits StoreKit propres au bundle MAS, avec achat, restauration et validation serveur.

Matrice : StoreKit Configuration locale, Sandbox puis TestFlight ; achat mensuel/annuel ; Ask to Buy si pertinent ; interruption/annulation ; restauration sur nouvel appareil ; expiration ; billing retry/grace ; remboursement/révocation ; changement d'Apple ID ; compte PresSay absent/différent ; transaction dupliquée ; validation serveur indisponible.

Le rapprochement Apple transaction ↔ compte PresSay doit éviter qu'un achat disparaisse tout en empêchant son attribution silencieuse au mauvais compte. Prévoir une UX de liaison/récupération et un support auditable.

Gate : aucune mention « MAS ready » avant le passage de [`docs/MAC_APP_STORE_SPIKE.md`](../MAC_APP_STORE_SPIKE.md), de la Sandbox et de TestFlight sur build signé.

## Journal des release gates

| Gate           | Propriétaire suggéré     | Condition de sortie                                                     |
| -------------- | ------------------------ | ----------------------------------------------------------------------- |
| AUTH-STAGING   | Backend + macOS          | Matrice auth/entitlements complète, traces redacted.                    |
| SYNC-SECURITY  | Security externe         | Threat model et revue protocole sans finding critique/élevé ouvert.     |
| BYOK-CONTRACTS | macOS + QA               | Tous providers mockés, smoke réels prioritaires.                        |
| STRIPE-E2E     | Backend + Finance/QA     | Webhooks, clocks, portail et suppression compte validés.                |
| STOREKIT-E2E   | macOS + Backend          | Configuration, Sandbox, TestFlight et restore validés.                  |
| PRIVACY        | Produit + Legal/Security | Disclosure route, rétention et politiques alignés au comportement réel. |
