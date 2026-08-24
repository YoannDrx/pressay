# Audit de release — 24 août 2026

Ce registre ne contient que des preuves techniques non sensibles. Aucun contenu
dicté, secret, identifiant de compte, moyen de paiement ou donnée personnelle
n'y est reproduit.

## Baseline desktop et MAS

La tête de `origin/main` auditée est `5193f77`. Les correctifs de projection
Cloud et de redaction desktop ont été relus par le propriétaire, mergés et
rejoués par la CI. Le workflow Apple Silicon, les tests, la qualité du code et
le contrôle de sécurité sont verts sur ce commit.

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

Le DMG `v2.0.0-beta.3` retéléchargé depuis GitHub a été vérifié de nouveau :
image disque valide, checksum public identique, ticket de notarisation présent
sur le DMG et l'app interne, puis acceptation Gatekeeper des deux niveaux sous
l'identité Developer ID de Yoann ANDRIEUX.

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

Le correctif Cloud mergé applique désormais la même projection effective aux
réponses compte/bootstrap et au jeton signé :
un droit Pro expiré est exposé comme `free/none`, avec sa révision conservée.
Deux tests de régression couvrent la réponse compte et le JWT. `bun run verify`
passe 105 tests ; Secretlint et l'audit des dépendances ne détectent aucun
secret ni avis high/critical.

Le commit Cloud `c56f6d5` est déployé sur deux projets Vercel indépendants. Les
domaines `api-staging.press-say.app` et `api.press-say.app` ont été réaffectés
à leurs projets canoniques après validation des URLs Vercel et avec l'ancien
projet conservé comme rollback. Les deux endpoints `/health` annoncent le bon
commit et le bon environnement ; `/ready` valide la base et le schéma `0015`.

Deux clients Google OAuth distincts ont été créés dans le projet Google Cloud
Pressay. Leurs origines et callbacks sont limités à chaque API et les couples
client/secret sont stockés comme variables sensibles dans les projets Vercel
correspondants. Les configurations publiques staging et production annoncent
maintenant `google` et `apple`, et les deux routes Better Auth produisent une
redirection Google valide. Le branding Google est publié, externe et validé.
Le parcours natif complet a ensuite été rejoué sur le build signé :
déconnexion, Google, callback OAuth, deep link, bootstrap du compte, projection
Free et chargement de l'usage. Le compte est revenu à l'état connecté sans
erreur de chargement ; la gate Google/compte est fermée sur cette machine.

## Diagnostics desktop

L'audit des journaux de développement a révélé que le dump `Debug` complet des
réglages pouvait contenir des prompts, des entrées de dictionnaire et des noms
de périphériques. Le correctif desktop mergé remplace ce dump par un résumé
composé uniquement de booléens et de compteurs. Un test injecte des sentinelles
dans les champs sensibles et prouve qu'elles n'apparaissent pas dans le
diagnostic.

Les erreurs de chargement du compte journalisent désormais seulement le code
public sûr. Le catalogue des dix thèmes sonores dispose aussi d'un contrat
frontend testé par la CI.

Un cycle natif de capture silencieuse a été rejoué sur le build signé. La
capture a démarré, le pipeline a reçu zéro échantillon utilisable, la surface
est passée par l'état d'erreur attendu puis l'icône menu bar est revenue à
`Idle` environ 2,2 secondes plus tard. Une annulation de sécurité effectuée
ensuite n'a trouvé aucune opération ou surface orpheline.

## Landing et portfolio

Le site Pressay passe lint, typecheck et build. La suite Playwright locale a
d'abord révélé trois timeouts pendant une exécution concurrente avec la lourde
matrice portfolio. Les mêmes contrats passaient isolément, mais restaient trop
proches de la limite à cause de la compilation à froid de plusieurs routes
Next.js. La PR web #20 sérialise donc les scénarios à l'intérieur de chaque
projet tout en conservant desktop et mobile en parallèle. Avec ce réglage,
40 scénarios passent et 2 scénarios réservés à un déploiement distant sont
ignorés en 30 secondes.

La production `https://press-say.app` passe les 32 scénarios applicables sur
desktop et mobile ; 10 contrats réservés au mode local sont ignorés. Le
portfolio passe son build et 30 scénarios multi-navigateurs ; 14 scénarios non
applicables à certaines variantes sont ignorés. Un timeout Chromium observé
pendant la concurrence avec la suite web repasse seul en 4,6 secondes et ne
révèle aucune violation Axe sérieuse.

Les routes de téléchargement de la landing et du portfolio ont été suivies
jusqu'à l'asset GitHub publié. Toutes deux aboutissent à `Pressay.dmg` de la
prerelease `v2.0.0-beta.3`, d'une taille de 20 439 772 octets. Le checksum
public correspond au digest GitHub :
`89ae5d40df921a796f238e1c750c6f204beca49f0d5eea1dbf2798e5827bf9e3`.

## Stripe direct

Le compte test Pressay contient un seul produit actif `Pressay Pro`, à 7,99 €
par mois et 69 € par an, sans essai. La destination staging cible
`https://api-staging.press-say.app/v1/webhooks/stripe` et écoute 21 événements.

Les secrets de signature staging et live ont été renouvelés dans Stripe avec
une fenêtre de transition d'une heure, enregistrés comme variables sensibles
dans leurs projets Vercel puis redéployés. Le replay d'un événement Stripe de
test reçoit désormais HTTP 200 sur staging. Une charge utile de vérification
sans donnée utilisateur, signée avec le secret live, reçoit aussi HTTP 200 sur
production. La divergence de signature est donc corrigée.

Le catalogue live a été relu via l'API Stripe : un seul produit actif
`Pressay Pro`, deux prix récurrents actifs en euros, 7,99 € mensuels et 69 €
annuels, sans période d'essai. Les identifiants ne sont pas reproduits ici.

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
- Les coordonnées App Review autorisées ont été renseignées et sauvegardées.
  La fiche conserve Yoann ANDRIEUX comme contact et la version reste en
  publication manuelle.

Le workflow MAS doit rester bloqué tant que le code de conformité Apple n'est
pas disponible. Les captures d'abonnement doivent montrer la vraie surface
StoreKit du build candidat, pas un mock ou la variante Stripe.

## Matrice native

Le Mac disponible pour cet audit est un Apple M2 16 Go sous macOS 26.3.1. Mail,
Messages, Notes, Safari, Chrome, Slack et Terminal sont installés ; Notion,
Word et Cursor ne le sont pas. La bêta 3 installée est signée, notarisée,
acceptée par Gatekeeper et possède un ticket staplé.

Les scénarios interactifs complets restent à exécuter après déploiement du
correctif Cloud. La capture silencieuse et son auto-disparition sont validées
sur cette machine. La gate M1 8 Go/macOS 14 ne peut pas être remplacée par le
Mac actuel ou par des tests automatisés.

## Gates restantes

1. Scénarios E2EE et suppression sur deux Macs.
2. Matrice Stripe Checkout/Test Clock complète et projection des entitlements,
   sans ouvrir le checkout live.
3. Capture App Review de chaque abonnement depuis la vraie variante StoreKit.
4. Réponse Apple sur le chiffrement, upload MAS, Sandbox puis TestFlight.
5. Matrice native M1 8 Go/macOS 14 et applications manquantes.
6. Revue cryptographique externe et validation fiscale externe.

Aucune de ces gates ne doit être masquée par un statut « 100 % ». La bêta
directe locale reste utilisable ; le lancement commercial et la soumission MAS
restent fermés jusqu'aux preuves correspondantes.
