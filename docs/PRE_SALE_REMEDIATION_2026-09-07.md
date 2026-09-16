# Préparation avant vente — 7 septembre 2026

Ce document complète l’audit du 6 septembre. Les corrections sont locales et
n’ont pas été publiées dans une release client. Il ne constitue pas une
attestation « 100 % prod ready » ou une validation App Review.

## Corrections réalisées

| Blocage                                                   | Correction                                                                                                                                                                      | Preuve et limite                                                                                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Droits Pro refusés en production                          | Clés publiques Ed25519 distinctes et épinglées pour production et staging ; contrôle du `kid` correspondant à l’API sélectionnée.                                               | JWKS des deux domaines vérifiés ; test Rust des deux clés. Aucune clé privée copiée dans le client.                                              |
| Réponse réseau après déconnexion ou changement de session | Révision de session et sérialisation du dernier contrôle avant de persister compte, appareil et droits ; une réponse ancienne ne rétablit plus le compte.                       | Test de rejet d’une révision devenue obsolète, en complément des tests de rotation OAuth.                                                        |
| Historique défectueux bloquant l’app                      | Échec d’initialisation récupérable, base préservée, nouvelle tentative sur demande ; lecture SQLite/déchiffrement hors du thread async.                                         | Test SQLite corrompue, conservation des octets, restauration et nouvelle tentative. Le trousseau natif signé reste à exercer.                    |
| Recherche chargeant tout l’historique                     | Pages de 100 maximum pour la recherche, curseur indépendant des résultats trouvés ; annulation logique des réponses obsolètes ; pagination clavier.                             | Test SQLite 10 000 lignes et tests du vrai composant React : page vide, nouvelle recherche, retry.                                               |
| Dictée oubliée en cours                                   | Arrêt et transcription automatiques après 15 minutes ; tampon de transcription plafonné à 14,4 millions d’échantillons, environ 55 Mio.                                         | Test de dépassement du tampon ; le plafond ne couvre pas la mémoire du modèle ni toutes les files audio. Essai micro prolongé encore nécessaire. |
| Achats différés ignorés                                   | Écoute native de `Transaction.updates` au lancement ; réveil de la réconciliation ; récupération de `Transaction.unfinished` ; un échec ne bloque plus les autres transactions. | Bridge Swift compilé. Test local expérimental refusé/incomplet hors hôte Xcode adapté ; aucun succès Sandbox revendiqué.                         |
| Verrou commercial incohérent                              | `storekit-purchases` active à la fois le bouton et le backend, et implique MAS + enforcement Free/Pro. Restaurer reste possible quand l’achat est fermé.                        | Tests UI catalogue vide, hors ligne, canal direct, achat fermé/ouvert.                                                                           |
| Client MAS utilisant implicitement staging                | Environnement explicite pour les builds commerciaux ; rejet d’un canal incompatible et d’une URL contradictoire ; clé/API de production pour MAS sans override.                 | Matrice CI direct, MAS et candidat StoreKit ; compilation commerciale stable interdite avec une version source bêta.                             |
| Mises à jour impossibles à livrer                         | Workflow produit l’app et le DMG, inclut `latest.json`, contrôle version/archive/signature ; nouveau client utilise l’endpoint statique GitHub des releases stables.            | Deux tests de structure du manifeste. Le test d’installation signé depuis une ancienne version reste obligatoire.                                |
| Contrôles Rust incomplets                                 | Corrections des sept anciens défauts de lint dans les tests ; CI Clippy stricte avec `--all-targets` ; contrôles natifs avant préparation d’une release.                        | Clippy strict toutes cibles et 328 tests réussis dans chacun des deux builds : direct et candidat StoreKit avec enforcement activé.              |
| Dépendance backend vulnérable                             | Override ciblé `fast-uri` 3.1.7 dans le backend actuel.                                                                                                                         | 114 tests backend réussis, audit sans alerte haute/critique ; une alerte de gravité inférieure reste signalée.                                   |

Les corrections du premier audit sont conservées : rotation OAuth sérialisée,
marqueur de déconnexion dans le trousseau, protection de la sync, manifeste de
confidentialité dans le bundle et séparation des features MAS/direct.

## Résultats des contrôles locaux

- **328 tests Rust réussis dans chacun des deux builds** : `updater` et
  `storekit-purchases` avec environnement `staging-mac-app-store`.
- **Clippy strict `--all-targets` réussi dans les deux builds**. L’avertissement
  de compatibilité future de `block` 0.1.6 reste présent dans les dépendances.
- **16 tests navigateur réussis** : huit du produit de prévisualisation et huit
  des vrais composants Compte/Historique avec IPC simulé.
- Build TypeScript/Vite, lint frontend, formatage et clés des 24 locales réussis.
- Deux tests du manifeste updater et quatre rejets de configurations commerciales
  invalides réussis. Le graphe StoreKit exclut NSPanel et les API privées Tauri.
- **114 tests backend réussis**, installation gelée du lockfile et contrôles de
  source réussis ; script de diagnostic de production revérifié après correction.

## Vérifications réelles des services

- Backend de production : commit `e6fc44b167218b7a2dc2f71a5879a918a1e55c3e`,
  schéma `0015_free_bootstrap_and_web_accounts.sql`. Health/readiness répondent
  200 ; routes privées non authentifiées répondent 401.
- Huit contrôles du contrat public réussis : santé, base, configuration auth,
  Apple, métadonnées OAuth PKCE, clé de signature et deux frontières d’accès.
- Le backend local initial était en retard. Les modifications finales sont dans
  le worktree `/Users/yoannandrieux/Projets/pressay-cloud-pre-sale`, branche `codex/pre-sale-hardening`,
  basé sur le commit de production. Le checkout habituel a été préservé.
- Le site est vérifié depuis `577b6ef`, dans `/tmp/pressay-release-web` : lint et
  TypeScript passent. Cinq scénarios en lecture sur `https://press-say.app`
  passent : page FR, retours de paiement, pages légales, redirections de support
  et confidentialité, présentation EN des prix et de l’offre fermée.
- Stripe Pressay : paiements et virements activés, aucune exigence actuellement
  due au niveau du compte ; deux tarifs récurrents actifs en EUR, 7,99 €/mois et
  69 €/an, sur le même produit. Aucune transaction financière exécutée.
- Les noms de variables App Store Server API et des deux produits sont présents
  dans la configuration Vercel de production. Leur présence ne prouve pas la
  validité d’un achat ou la réception effective des notifications Apple.

## Suite après connexion à App Store Connect

Contrôle authentifié du 7 septembre : les contrats gratuit et payant, le compte
bancaire, les formulaires fiscaux américains, DSA et DAC7 sont actifs. Ces points
ne sont plus des blocages supposés. L’identifiant de l’app est `fr.yodev.pressay`,
Apple ID `6795505605`.

Le groupe `22326134` contenait le mensuel au niveau 1 et l’annuel au niveau 2.
Les deux offres ont été **enregistrées au niveau 1**, puisqu’elles fournissent le
même service. Le fichier StoreKit local a été aligné. Les prix n’ont pas changé ;
les tarifs en France affichent 7,99 €/mois et 69 €/an, sans offre d’introduction. Les deux produits
restent « Finaliser avant soumission ».

Les descriptions FR et EN ont été enregistrées dans la version en préparation :
précision du téléchargement initial nécessaire pour le hors-ligne, renouvellement,
résiliation et liens confidentialité/EULA Apple déjà applicable. Ces modifications
ne constituent pas une publication ni une soumission à App Review.

Les URL de notifications pointent déjà vers les backends production et staging
appropriés. La déclaration de confidentialité est déjà publiée, avec cinq types
de données liés au compte. Leur adéquation au trafic du candidat final doit
encore être vérifiée.

Un ancien build 2.0.0, chargé le 22 août, existe dans TestFlight et attend les
informations de chiffrement. Il ne contient pas les correctifs de cet audit.
Le document `pressay-anssi-declaration-signed.pdf`, déposé le 23 août, est toujours
« Vérification », sans valeur de clé fournie par Apple. Aucune déclaration de
chiffrement n’a été remplie par déduction à partir de ce seul état.

Le profil de distribution correspondant, avec Sign in with Apple, est présent et
valide jusqu’au 21 août 2027. Les champs e-mail et téléphone App Review sont vides ;
les coordonnées à transmettre ont été demandées au titulaire. Les détails bancaires
et fiscaux personnels ne sont pas copiés dans le registre.

Un nouveau candidat natif a été compilé en release puis signé : version 2.0.0,
build 2.0.1, backend `staging-mac-app-store`. `codesign --verify --deep --strict`
passe ; le certificat de signature est bien autorisé par le profil embarqué,
les entitlements concordent, App Sandbox et audio-input sont actifs, aucune
permission de débogage n’est présente. Le Mach-O annonce macOS 14.0 minimum et
le SDK 26.2. Le manifeste de confidentialité passe `plutil -lint`.

Le paquet `.pkg` est signé avec le certificat Mac Installer Distribution et
conservé dans `/Users/yoannandrieux/Projets/Pressay-release-candidates/2.0.0-2.0.1`,
avec SHA-256, configuration et logs. L’archive Xcode a été assemblée à partir de
ce bundle Tauri signé ; Organizer la reconnaît comme archive macOS Apple Silicon.
**La validation Apple réussit avec un avertissement dSYM manquant.** Ce premier
candidat a été envoyé via Xcode en **TestFlight Internal Only** ; Apple a terminé
son traitement et affiche « Informations manquantes » pour le chiffrement.
Le profil release a été corrigé pour produire les informations de lignes dans un
dSYM séparé. Un garde-fou contrôle l’identité des UUID binaire/symboles ; la CI
conserve ce fichier. Le second candidat 2.0.2 a été compilé, signé et archivé avec
son dSYM. **Apple a validé cette archive sans avertissement** : tous les contrôles
de validation ont réussi. Son envoi TestFlight interne a réussi à 02:08 le
7 septembre ; App Store Connect affiche le traitement « Terminé » et le build
2.0.2 « Internes ». Les informations de chiffrement restent à fournir avant
l’activation des tests. Les consignes de recette ont été ajoutées au build.

La recompilation a révélé une sonde CMake SVE bloquée, lancée par la détection
`GGML_NATIVE=ON` de transcribe.cpp. La configuration Cargo fixe désormais
`GGML_NATIVE=OFF` par défaut : une distribution ne doit pas dépendre des
instructions propres au Mac de compilation. Le cache CMake de la relance
confirme Metal actif, DOTPROD/FMA/FP16 disponibles, SVE et MATMUL_INT8 inactifs.
Cela ne remplace pas la recette sur M1 ni les mesures du candidat final.

La relance release termine en 15 min 26 s. Le dSYM correspond à l’UUID
`19A9E16E-E082-32A0-8255-CBCD01502C0C` de l’exécutable arm64 ;
`dwarfdump --verify` ne signale aucune erreur. Le script
`scripts/package-macos-store.py` a produit le `.pkg` signé et l’archive avec
symboles dans `/Users/yoannandrieux/Projets/Pressay-release-candidates/2.0.0-2.0.2`.

Deux transcriptions par moteur ont été exécutées sur une copie identique du
binaire compilé, en mode CLI portable avec données isolées et fichier audio
synthétique de 7,81 s. Whisper Small reconnaît la phrase attendue :
CPU 2 596/2 576 ms ; Metal 1 342/1 141 ms. Ces essais couvrent le moteur sur M2,
pas l’app installée sous App Sandbox, le microphone, le collage ni les achats.
Ils ne constituent pas un benchmark de percentiles.

Ce candidat sert aux tests internes Sandbox. Il ne constitue pas le binaire
commercial final et sa validation ne démontre pas encore achat/restauration,
permissions ou collage en conditions réelles.

Le registre complémentaire est
`docs/audit-evidence/2026-09-07-app-store-connect.json`.

## Conditions encore ouvertes avant ouverture commerciale

1. **Fiche de vérification et chiffrement.** L’accès App Store Connect et les
   contrats sont vérifiés. Compléter les coordonnées App Review autorisées et
   traiter le document de chiffrement encore « Vérification » chez Apple.
2. **Candidat Apple signé et tests Sandbox/TestFlight.** Achat, achat différé,
   restauration, renouvellement, expiration, remboursement et mauvais compte
   doivent passer avec JWS Apple et projection serveur. Une simulation de l’IPC
   ou un fichier `.storekit` local ne clôt pas cette condition.
   Le build commercial devra aussi résoudre le parcours App Review :
   `pressay-cloud/src/billing/apple-client.ts::appleVerificationTargetsFor`
   accepte uniquement Production sur le backend de production, alors qu’Apple
   effectue ses achats de revue en Sandbox. Le candidat interne utilise staging
   et n’exerce donc pas ce cas. L’isolation des droits Sandbox et commerciaux
   doit être conservée lors de cette résolution.
3. **Recette native du candidat.** Permissions refusées puis rétablies, collage
   réel, Trousseau après mise à jour, veille/reprise, micro débranché, longue
   capture, reprise après arrêt et accessibilité VoiceOver. macOS 14/M1 et un
   second Mac pour la récupération E2EE restent nécessaires pour la matrice
   annoncée. Le Mac utilisé ici est un M2 sous macOS 26.
4. **Release finale et mise à jour.** Aligner les versions stables, signer,
   tester l’archive et son installation, puis publier la release. Les releases
   publiques bêta existantes ne contiennent pas d’archive updater signée et
   `latest.json`. Le changement d’URL n’actualise pas les binaires déjà installés
   qui pointent encore vers `updates.press-say.app`.
5. **Validation des modifications et promotion.** Les correctifs ne sont pas
   fusionnés dans les branches principales et le backend modifié n’est pas
   déployé en production. Le nouveau binaire est réservé au TestFlight interne.
   Une validation humaine du diff est exigée
   avant fusion par les instructions du dépôt. L’ouverture du paiement doit
   utiliser un candidat dont les preuves ci-dessus sont enregistrées.

## Reproduction

```sh
# Application : contrôles de code et composants
bun run build
bun run lint
bun run check:translations
bun test scripts/check-updater-manifest.test.ts
bunx playwright test --workers 1

# Direct : modèle et bibliothèques natifs requis
CMAKE_POLICY_VERSION_MINIMUM=3.5 CARGO_INCREMENTAL=0 \
  cargo clippy --manifest-path src-tauri/Cargo.toml --locked \
  --all-targets --no-default-features --features updater -- -D warnings
CMAKE_POLICY_VERSION_MINIMUM=3.5 CARGO_INCREMENTAL=0 \
  cargo test --manifest-path src-tauri/Cargo.toml --locked \
  --lib --no-default-features --features updater

# Candidat StoreKit utilisant exclusivement le backend Sandbox
PRESSAY_BUILD_ENVIRONMENT=staging-mac-app-store \
CMAKE_POLICY_VERSION_MINIMUM=3.5 CARGO_INCREMENTAL=0 \
  cargo test --manifest-path src-tauri/Cargo.toml --locked \
  --lib --no-default-features --features storekit-purchases

# Backend : depuis le worktree pressay-cloud-pre-sale
bun run ci:source
PRESSAY_STAGING_BASE_URL=https://api.press-say.app \
PRESSAY_EXPECTED_CLOUD_AUTH_PROVIDERS=apple bun run validate:staging
```

Le registre final est `docs/audit-evidence/2026-09-07.json`. Les résultats du
6 septembre concernent l’état précédent et ne sont pas réutilisés comme preuve
pour le code modifié aujourd’hui. Les essais StoreKit temporaires et leurs logs
restent dans `/tmp/pressay-audit-20260906` ; ils ne sont pas embarqués dans l’app.

L’écoute des transactions et leur reprise suivent les séquences décrites par
[Apple pour Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates)
et [Transaction.unfinished](https://developer.apple.com/documentation/storekit/transaction/unfinished).

Le comportement Sandbox de TestFlight est décrit dans
[la documentation de test Apple](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox).
Le cas d’un binaire signé pour la production évalué en Sandbox est également
documenté dans [la FAQ In-App Purchase d’Apple](https://developer.apple.com/library/archive/technotes/tn2413/).
