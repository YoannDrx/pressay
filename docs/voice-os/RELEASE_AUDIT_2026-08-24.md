# Audit de release — 24 août 2026

Ce registre ne contient que des preuves techniques non sensibles. Aucun contenu
dicté, secret, identifiant de compte, moyen de paiement ou donnée personnelle
n'y est reproduit.

## Baseline desktop et MAS

La tête de `origin/main` auditée est `91345a6`. Les corrections décrites plus
bas sont isolées sur `codex/cloud-session-recovery` et ne constituent pas encore
une release.

| Contrôle                 | Résultat                                               |
| ------------------------ | ------------------------------------------------------ |
| Traductions              | 23 langues, 802 clés, réussi                           |
| ESLint et Prettier       | réussi                                                 |
| Build frontend           | réussi                                                 |
| Tests unitaires frontend | 10 réussis                                             |
| Playwright               | 8 réussis                                              |
| Rust direct/updater      | 321 tests réussis, Clippy sans avertissement           |
| Rust MAS                 | 321 tests réussis, Clippy sans avertissement           |
| Catalogue StoreKit local | identifiants, prix, FR/EN et absence d'essai conformes |
| Graphe MAS               | aucune dépendance Stripe, updater ou API macOS privée  |

Le bundle MAS local compile avec l'identifiant `fr.yodev.pressay`, la version
`2.0.0`, App Sandbox et `ITSAppUsesNonExemptEncryption=true`. Cette preuve ne
remplace ni un upload, ni StoreKit Sandbox, ni TestFlight.

## Modèles et exécution headless

Les trois routes primaires et leurs fallbacks ont été reprobés. Les tailles
annoncées sont exactes : 739 508 576 octets pour Fast, 269 751 136 pour
Polyglot et 1 161 143 008 pour Precise.

Une fixture française synthétique de 6,05 secondes a été transcrite vingt fois
par modèle sur un Apple M2 16 Go sous macOS 26.3.1. Fast et Polyglot restent
nettement temps réel ; Precise conserve une médiane d'environ 3,5 secondes et
un pic mémoire inférieur à 1 Go sur cette fixture. Ces chiffres ne doivent pas
être extrapolés au M1 8 Go ou à un corpus humain.

## Compte Cloud : cause racine et correctif

Le compte de staging auditait comme connecté, mais l'app rejetait son snapshot
avec `cloud_entitlement_invalid`. La base contenait un ancien droit Pro d'essai
expiré. Le jeton signé le déclassait correctement en Free, tandis que la réponse
JSON exposait encore Pro. Le client comparait les deux représentations et
échouait à juste titre.

La branche Cloud `codex/expired-entitlement-projection` applique désormais la
même projection effective aux réponses compte/bootstrap et au jeton signé :
un droit Pro expiré est exposé comme `free/none`, avec sa révision conservée.
Deux tests de régression couvrent la réponse compte et le JWT. `bun run verify`
passe 105 tests ; Secretlint et l'audit des dépendances ne détectent aucun
secret ni avis high/critical.

Le correctif doit être revu, mergé et déployé sur staging avant de rejouer le
login natif, puis promu en production après smoke tests. La dictée locale ne
dépend pas de cette promotion.

## Diagnostics desktop

L'audit des journaux de développement a révélé que le dump `Debug` complet des
réglages pouvait contenir des prompts, des entrées de dictionnaire et des noms
de périphériques. La branche desktop remplace ce dump par un résumé composé
uniquement de booléens et de compteurs. Un test injecte des sentinelles dans les
champs sensibles et prouve qu'elles n'apparaissent pas dans le diagnostic.

Les erreurs de chargement du compte journalisent désormais seulement le code
public sûr. Le catalogue des dix thèmes sonores dispose aussi d'un contrat
frontend testé par la CI.

## Stripe direct

Le compte test Pressay contient un seul produit actif `Pressay Pro`, à 7,99 €
par mois et 69 € par an, sans essai. La destination staging cible
`https://api-staging.press-say.app/v1/webhooks/stripe` et écoute 21 événements.

Un scénario synthétique `customer.subscription.updated` a ensuite été
déclenché depuis Stripe Workbench. Stripe a correctement créé ses fixtures et
envoyé cinq événements associés, mais les cinq livraisons ont reçu HTTP 401
`invalid_stripe_signature`. Le secret de signature injecté dans le projet
Vercel staging ne correspond donc pas à la destination Stripe actuelle. Cette
incohérence est une gate P0 : le secret doit être réaligné, le test renvoyé puis
la projection SQL et l'entitlement contrôlés avant toute matrice Checkout.

Le live conserve le bon produit et les bons prix, mais les points suivants
restent des gates : clarification du statut KYC affiché par Stripe, support
public à finaliser, branding à compléter, fiscalité, puis matrice Checkout/Test
Clock et projection d'entitlement. Aucun paiement live ne doit être créé pour
lever ces gates.

## App Store Connect

- La version macOS 2.0.0 est toujours « À finaliser avant soumission ».
- Les métadonnées publiques FR et EN sont présentes, avec trois captures par
  langue et des notes App Review locales-first.
- Aucun build n'est encore chargé.
- Le document de conformité chiffrement est encore « Vérification » depuis le
  23 août ; aucun code d'export ne doit être inventé.
- Le groupe `Pressay Pro` contient les abonnements mensuel et annuel, mais les
  deux restent « Finaliser avant soumission » car leur capture App Review est
  absente.
- Les coordonnées App Review restent à confirmer visuellement avant la
  soumission finale.

Le workflow MAS doit rester bloqué tant que le code de conformité Apple n'est
pas disponible. Les captures d'abonnement doivent montrer la vraie surface
StoreKit du build candidat, pas un mock ou la variante Stripe.

## Matrice native

Le Mac disponible pour cet audit est un Apple M2 16 Go sous macOS 26.3.1. Mail,
Messages, Notes, Safari, Chrome, Slack et Terminal sont installés ; Notion,
Word et Cursor ne le sont pas. La bêta 3 installée est signée, notarisée,
acceptée par Gatekeeper et possède un ticket staplé.

Les scénarios interactifs complets restent à exécuter après déploiement du
correctif Cloud. La gate M1 8 Go/macOS 14 ne peut pas être remplacée par le Mac
actuel ou par des tests automatisés.

## Gates restantes

1. Revue et merge des correctifs Cloud et desktop de cet audit.
2. Déploiement staging Cloud et replay Google/compte/usage sur le build signé.
3. Scénarios E2EE et suppression sur deux Macs.
4. Matrice Stripe test complète, sans ouvrir le checkout live.
5. Capture App Review de chaque abonnement depuis la vraie variante StoreKit.
6. Réponse Apple sur le chiffrement, upload MAS, Sandbox puis TestFlight.
7. Matrice native M1 8 Go/macOS 14 et applications manquantes.
8. Revue cryptographique externe et validation fiscale externe.

Aucune de ces gates ne doit être masquée par un statut « 100 % ». La bêta
directe locale reste utilisable ; le lancement commercial et la soumission MAS
restent fermés jusqu'aux preuves correspondantes.
