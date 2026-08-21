# Audit de release — 21 août 2026

Ce document enregistre les preuves observables de la préparation de `2.0.0-beta.2`.
Il ne contient aucun secret, contenu dicté, identifiant personnel ou donnée de paiement.

## Verdict

La bêta directe est en phase de durcissement et n'est pas encore commercialisable.
La dictée locale reste le cœur disponible sans compte. Les paiements de production
et la soumission Mac App Store restent fermés jusqu'à la levée de tous les gates
externes et natifs ci-dessous.

## Preuves automatisées acquises

| Surface      | Preuve                                                        | Résultat                                                                      |
| ------------ | ------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| App frontend | `bun run check:translations`                                  | 23 langues, 802 clés cohérentes                                               |
| App frontend | `bun run lint` et `bun run build`                             | réussi                                                                        |
| App frontend | `bun run test:playwright`                                     | 8 scénarios réussis                                                           |
| App Rust     | `cargo test --features updater`                               | 316 tests réussis                                                             |
| App Rust     | `cargo clippy --features updater --lib --bins -- -D warnings` | réussi                                                                        |
| Cloud        | `bun run verify`                                              | typecheck, lint, format et 84 tests réussis                                   |
| Landing      | `pnpm lint`, `pnpm build`, `pnpm test:e2e`                    | 28 scénarios locaux et 20 scénarios staging applicables réussis               |
| Modèles      | probes HTTP avec téléchargement partiel                       | Fast, Polyglot et Precise joignables via leurs sources auditées               |
| Auth web     | parcours interactif Google                                    | retour au compte, profil, appareil et entitlement chargés sans erreur console |
| Checkout     | preview Vercel avec kill switch                               | offre affichée, aucune action d'achat, libellé « Ouverture prochaine »        |

## Correctifs P0 inclus dans la branche

- Catalogue sonore exhaustif : dix thèmes typés, aucune retombée silencieuse vers
  Marimba, aperçu début/fin et erreur sur valeur inconnue.
- HUD Minimal/Live : waveform rééchantillonnée, géométrie native alignée, états de
  récupération et fond de webview explicitement transparent sur le build direct.
- Onboarding : permission déjà accordée tolérée, raccourci réellement enregistré
  affiché, première dictée détectée même lorsque l'insertion native ne déclenche pas
  un événement React.
- Auth app : phase `bootstrapping` distincte ; l'état connecté n'est émis qu'après
  initialisation du compte et de l'appareil.
- Modèles : source publique auditée prioritaire, hash et taille conservés comme
  contrôle d'intégrité ; CDN de marque maintenu en fallback.
- Environnements : manifeste sans secrets pour local, staging direct, production
  directe et production MAS.
- Identité : nom visible `Pressay`, nouvelle icône plein cadre et déclinaisons.

## Environnements

| Environnement     | État vérifié                                                                     | Gate restant                                                                             |
| ----------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Cloud staging     | `/health`, `/ready` et auth répondent                                            | rejouer callback app bêta.2, E2EE et matrice d'erreurs                                   |
| Cloud production  | projet Vercel indépendant créé, variables publiques et kill switches configurés  | base de production, secrets distincts, migration, sauvegarde et smoke tests              |
| Landing staging   | alias séparé vers un déploiement preview, checkout fermé, tests distants réussis | OAuth Google/Apple complet, revue visuelle finale et promotion contrôlée                 |
| Stripe dédié      | compte distinct retrouvé, catalogue dédié encore vide                            | KYC, fiscalité, banque, branding, produits/prix, webhooks et Test Clocks                 |
| App Store Connect | fiche macOS existante, contrat fiscal en attente                                 | attestation personnelle, contrats, certificats, produits StoreKit, Sandbox et TestFlight |

## Gates bloquants

1. Révocation de la clé OpenAI précédemment divulguée et remplacement par une clé
   restreinte non persistée dans les dépôts.
2. Validation fiscale et juridique : TVA/franchise, services électroniques B2C UE,
   OSS, médiateur, politique de remboursement et facturation.
3. Cloud production isolé avec base, secrets, surveillance et rollback prouvés.
4. Stripe live : identité vérifiée, catalogue exact, webhooks, portail et matrice
   Test Clocks sans essai.
5. Sign in with Apple réellement configuré et validé, puis suppression de compte.
6. E2EE et quotas validés sur staging production-shaped.
7. Matrice native : raccourcis, permissions, deux HUDs, dix sons, modes, historique,
   BYOK et insertion dans les applications cibles.
8. DMG signé, notarisé, staplé et contrôlé ; MAS validé en Sandbox/TestFlight.
9. Description humaine obligatoire de la PR, revue humaine et checks GitHub à jour.

## Règle de promotion

`COMMERCIAL_CHECKOUT_ENABLED` reste à `false`. Aucun domaine de production, produit
live, prix, abonnement ou fiche Store ne doit être activé uniquement sur la base de
la réussite des tests locaux. Chaque gate doit être relié à une preuve datée dans ce
registre avant promotion.
