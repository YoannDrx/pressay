# Rapport d’implémentation — Signal OS

Date : 18 août 2026

Ce rapport sépare ce qui a été implémenté et testé en source de ce qui exige encore un Mac de référence, des comptes fournisseurs ou un environnement commercial réel.

## App macOS

- `VoiceSurfaceState` est désormais la source canonique de présentation pour dashboard, Voice Bar et menu bar.
- Les phases `arming`, `listening`, `captured`, `transcribing`, `transforming`, `inserting`, `success`, `cancelled` et `failed` sont reliées au pipeline réel.
- Les routes `local_stt`, `apple_intelligence`, `byok` et `pressay_cloud` sont explicites ; aucun contenu de dictée, prompt ou clé n’est placé dans l’événement canonique.
- La Voice Bar montre route, phase, succès, annulation, erreurs récupérables et actions de reprise.
- Une famille complète de glyphes menu bar Signal OS remplace les assets hérités et dérive du même état backend.
- Le thème minéral/obsidienne, ses couleurs de route et ses états sémantiques sont partagés entre la fenêtre principale et l’overlay.
- L’onboarding compte trois étapes visibles : bienvenue, préparation du Mac et première dictée. Le diagnostic devient silencieux, les permissions sont réunies, un seul modèle est recommandé par défaut et le raccourci est appris pendant l’essai. Personnalisation et Pro sont reportés dans l’app après le premier succès.
- L’ancienne autorisation macOS héritée du bundle ad hoc a été reproduite puis réparée : la famille d’icônes native utilise désormais le Signal Orb et l’entrée TCC fraîche est reconnue par l’app.
- La sélection d’un modèle ne marque plus prématurément l’onboarding comme terminé. La fin est une commande explicite après le premier succès ou le choix conscient de tester plus tard.
- Les commandes déterministes exigent une wake phrase exacte (`Pressay command` ou `Commande Pressay`) et couvrent nouvelle ligne, paragraphe, liste à puces, snippet local, mode temporaire/suivant et annulation.
- La matrice `Capabilities` centrale distingue `enabled`, `upgrade_required` et `release_gate`. Stripe et StoreKit restent fermés tant que les matrices externes n’ont pas passé leurs gates.
- Les commandes Pro sensibles appliquent désormais la même matrice côté backend. L’enforcement commercial est un feature flag de compilation fermé par défaut pendant la bêta ; l’UI l’identifie comme aperçu Pro.
- Les nouveaux textes Signal OS utilisent i18next. Les catalogues secondaires sont chargés à la demande, ce qui ramène le plus gros chunk initial d’environ 1,13 Mo à environ 265 Ko.
- Les douze modes historiques sont restaurés, dont Traduction, avec migration non destructive des modes/profils et préférences de l’ancienne app native.
- L’historique dispose de recherche, filtres, tags chiffrés, export JSON/Markdown, retry avec choix du mode et filiation des résultats dérivés.
- Le compte utilise désormais l’identité du site via OAuth 2.1 PKCE ; access/refresh tokens restent dans le Trousseau et l’ancien token natif est migré sans être supprimé.
- Le menu bar natif expose désormais l’état vocal, le mode actif, le modèle local, l’état BYOK, le niveau Cloud et le raccourci ; les modes et modèles téléchargés sont sélectionnables directement dans leurs sous-menus.
- Les deux HUD existants sont clarifiés : Minimal retire les métadonnées non essentielles, Live conserve route, durée et transcription. Les libellés disposent de plus d’espace et les erreurs `no_audio`/`silent_input` disparaissent automatiquement après 2,2 secondes.
- Le réglage audio propose dix personnalités sonores. Les huit nouvelles paires proviennent des cues CC0 `press`/`release` de UI SFX ; sortie et volume restent configurables même lorsque le feedback est momentanément désactivé.
- Le sélecteur OpenAI est limité à six modèles texte utiles lorsqu’ils sont réellement retournés par le compte. GPT-5.6 Luna est le choix recommandé coût/volume, Terra le choix équilibré et Sol le choix premium ; une saisie manuelle reste disponible.
- La consommation Compte se rafraîchit toutes les 30 secondes et au retour de focus. Elle représente exclusivement les quotas Pressay Cloud signés par le backend, pas les requêtes BYOK.
- Les erreurs de synchronisation E2EE conservent maintenant leur code public sûr dans l’interface et dans les logs. Le backend staging doit encore passer la matrice à deux appareils avant toute promesse commerciale.

## Landing `pressay-web`

- Nouveau hero « Votre Mac devient vocal / Your Mac now speaks » et palette Signal OS.
- Narration scroll `Press → Speak → Transform → Act` alignée sur les états réels de la Voice Bar.
- Carte interactive et accessible des routes Local, Apple Intelligence, BYOK et Pressay Cloud.
- Promesses corrigées : Apple Silicon, local par défaut, Cloud jamais obligatoire, aucune offre lifetime au lancement.
- Offre publique simplifiée en Free local illimité et Pro mensuel/annuel ; checkout public toujours fail-closed jusqu’au go-live fiscal/live.
- Reduced motion, responsive desktop/mobile et navigation clavier sont conservés.
- Les mentions Intel/WhisperKit héritées ont été remplacées par la cible Apple Silicon et les presets Fast/Polyglot/Precise réellement livrés.

## Backend `pressay-cloud`

Le dépôt frère accepte maintenant les JWT OAuth/JWKS du site et les jetons courts du proxy web. Stripe test est configuré avec le produit Pro, deux prix, un webhook signé et une migration qui journalise le consentement légal sans texte dicté ni donnée comportementale. Un probe staging read-only vérifie health, base de données, config auth et protections d’accès.

## Vérifications exécutées

| Dépôt           | Vérification                   | Résultat                                           |
| --------------- | ------------------------------ | -------------------------------------------------- |
| `Pressay`       | `cargo test --lib`             | 308 réussis                                        |
| `Pressay`       | `bun run lint`                 | réussi                                             |
| `Pressay`       | `bun run check:translations`   | 23 langues / 787 clés cohérentes                   |
| `Pressay`       | `bun run format:check`         | réussi                                             |
| `Pressay`       | `bun run build`                | réussi, aucun chunk supérieur à 500 Ko             |
| `Pressay`       | `bun run test:playwright`      | 7 réussis, dont FR lazy-load et RTL/reduced motion |
| `pressay-web`   | lint, typecheck, build Next 16 | réussis                                            |
| `pressay-web`   | Playwright desktop + mobile    | 26 locaux ; 18 distants réussis                    |
| `pressay-cloud` | `bun run verify`               | 22 fichiers / 75 tests réussis                     |

## Release gates encore ouverts

- Dictée et insertion natives sur les 11 applications cibles.
- Trois modèles CDN et benchmarks M1 8 Go/macOS 14.
- Apple Intelligence sur matériel et région compatibles.
- Contrats réels de chaque fournisseur BYOK.
- Comptage local des tokens BYOK et registre de prix versionné avant d’afficher un coût mensuel : sans `usage` réel de chaque réponse, une estimation serait trompeuse.
- Smoke interactif Google OAuth dans l’app, puis sync à deux appareils ; les cinq probes et l’identité web distante passent.
- Stripe Test Clocks et matrice upgrade/downgrade/échec/remboursement/taxes.
- StoreKit Configuration, Sandbox, restore, remboursement et TestFlight.
- Revue sécurité externe E2EE/entitlements.
- Core Web Vitals sur déploiement Preview et MacBook Air de référence.
- Traduction humaine des nouveaux textes Signal OS au-delà de FR/EN. Les autres langues ont un fallback anglais explicite ; RTL et reduced motion sont testés.

Observation CDN du 17 août 2026 : les trois fallbacks Hugging Face annoncent les tailles signées attendues, mais les trois routes primaires `models.press-say.app` sont inaccessibles. La gate modèle est donc en échec mesuré, pas seulement non testée.

Preuve native partielle sur le Mac de travail M2 16 Go/macOS 26.3.1 : Fast et Polyglot sont présents avec des tailles et SHA-256 exactement conformes au catalogue. Sur une fixture vocale française synthétique de 5,58 s, le binaire release headless transcrit Fast en 635 ms (chargement 330 ms) et Polyglot en 860 ms (chargement 135 ms), tous deux via Metal. Precise reste un téléchargement partiel de 283 453 046 octets. Ces chiffres prouvent le chemin fichier→modèle→texte sur cette machine, pas la gate M1 8 Go ni l’insertion inter-apps.

Ces gates ne peuvent pas être déclarés réussis par des mocks ou des tests source. La dictée locale reste indépendante de leur disponibilité.
