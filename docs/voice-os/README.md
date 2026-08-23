# Pressay Voice OS local — dossier d'investigation

Date de référence : 18 août 2026

Ce dossier transforme le plan produit « Voice OS local » en spécifications vérifiables. Il ne déclare pas comme terminées les capacités qui exigent encore un appareil physique, un backend de staging, des comptes fournisseurs, Stripe, StoreKit ou TestFlight.

## Décision produit

Pressay devient la couche vocale privée du Mac : une expérience native pour dicter, transformer, corriger puis, à terme, agir. Le chemin local reste gratuit, illimité, hors ligne et utilisable sans compte. Toute route externe est visible, choisie et révocable.

La différence défendable n'est pas « encore une app de dictée avec de l'IA ». Elle repose sur quatre éléments combinés :

1. une dictée locale réellement autonome ;
2. une Voice Bar qui expose l'état et la route de traitement ;
3. des commandes de texte sûres avant les actions système ;
4. une architecture ouverte où Apple Intelligence, BYOK et Pressay Cloud sont des routes facultatives.

## Statuts de vérité

| Statut                        | Signification                                                                                                                                |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `validée`                     | Chemin UI → backend couvert par un test automatisé pertinent et un test natif représentatif, erreurs et confidentialité incluses.            |
| `implémentée à vérifier`      | Code et surface produit présents, mais preuve native, fournisseur réel ou matrice d'erreurs incomplète.                                      |
| `bloquée par un release gate` | Implémentation partielle ou complète, mais dépendance externe, revue sécurité, canal de distribution ou validation opérationnelle manquante. |
| `absente`                     | Aucun chemin produit complet trouvé dans ce dépôt.                                                                                           |

Avec cette définition stricte, aucune grande capacité de dictée n'est encore « validée » à 100 %. Le build, le lint, les tests Rust/Playwright et les probes natifs partiels prouvent la santé et une partie du pipeline, pas encore la matrice d’insertion inter-apps, le M1 8 Go ou les paiements réels.

## Livrables

- [Feature ledger](FEATURE_LEDGER.md) — inventaire des capacités et niveau de preuve.
- [Architecture produit](PRODUCT_ARCHITECTURE.md) — benchmark, Free/Pro, routes et fonctionnalités locales.
- [Direction Signal OS](SIGNAL_OS_DESIGN.md) — explorations, tokens, motion, onboarding et landing.
- [Spécification Voice Bar](VOICE_BAR_SPEC.md) — états, événements, commandes, erreurs et menu bar.
- [Audit Cloud, BYOK et paiement](CLOUD_BYOK_BILLING_AUDIT.md) — état présent et protocoles de validation.
- [Validation et backlog](VALIDATION_AND_BACKLOG.md) — matrices natives, critères de sortie, risques et ordre d'exécution.
- [Rapport d’implémentation](IMPLEMENTATION_REPORT.md) — changements livrés dans l’app et la landing, tests rejoués et gates externes restants.
- [Runbook des release gates](RELEASE_GATE_RUNBOOK.md) — commandes, matrices externes et format de preuve.

## Décisions verrouillées pour la phase de conception

- Cible : macOS 14+, Apple Silicon.
- Free : dictée locale illimitée et sans compte.
- Pro : Voice Bar avancée, transformations, modes/profils avancés, routes Apple Intelligence/BYOK, synchronisation E2EE et quota Cloud.
- Pas de compte, d'essai ou de paywall avant la première dictée réussie.
- Pas de fallback silencieux vers le Cloud.
- Historique désactivé par défaut ; aucun analytics comportemental.
- Même matrice de capacités entre DMG et Mac App Store ; paiement Stripe pour le DMG, StoreKit pour le Store.
- Pas de lifetime au lancement tant que l'offre inclut des coûts récurrents.
- Les actions macOS ouvertes, réunions et agents multi-étapes restent hors V1.

## Baseline technique rejouée avant cette investigation

| Vérification                 | Résultat                                                        |
| ---------------------------- | --------------------------------------------------------------- |
| `bun run check:translations` | Réussi : 23 langues et 778 clés.                                |
| `bun run lint`               | Réussi.                                                         |
| `bun run build`              | Réussi ; aucun chunk supérieur à 500 Ko.                        |
| `bun run test:playwright`    | Réussi : 8 scénarios, dont FR lazy-load, RTL et reduced motion. |
| `cargo test --lib`           | Réussi : 303 tests après implémentation.                        |

## Limites de l'investigation

- La landing Signal OS est déployée sur `https://press-say.app` ; ses parcours distants desktop/mobile et son identité Better Auth passent.
- Le staging public est joignable et ses huit probes read-only passent. Le catalogue Stripe dédié existe avec prix mensuel/annuel ; les identifiants restreints, webhooks signés, fiscalité et Test Clocks restent des gates avant ouverture.
- Les tests M1 8 Go, macOS 14, Apple Intelligence, Sandbox StoreKit et TestFlight sont des release gates explicites.
- Les prix et offres concurrentes évoluent ; ils doivent être revérifiés au moment des décisions commerciales.

## Sources d'implémentation principales

- [`src/App.tsx`](../../src/App.tsx) — coque et séquence d'onboarding actuelle.
- [`src/styles/theme.css`](../../src/styles/theme.css) — tokens et thème actuels.
- [`src/overlay/RecordingOverlay.tsx`](../../src/overlay/RecordingOverlay.tsx) — overlay compact/live.
- [`src-tauri/src/transcription_coordinator.rs`](../../src-tauri/src/transcription_coordinator.rs) — phases et sérialisation du pipeline.
- [`src-tauri/src/tray.rs`](../../src-tauri/src/tray.rs) — états et assets de menu bar.
- [`docs/CLOUD_SYNC.md`](../CLOUD_SYNC.md) — protocole E2EE et scénarios opératoires.
- [`docs/MODELS.md`](../MODELS.md) — catalogue signé et presets locaux.
- [`docs/RELEASES.md`](../RELEASES.md) — différences DMG/MAS et release gates.
- [`docs/MAC_APP_STORE_SPIKE.md`](../MAC_APP_STORE_SPIKE.md) — état du spike Mac App Store.
