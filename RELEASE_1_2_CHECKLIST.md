# Checklist de publication Pressay 1.2

Ce document sépare les capacités codées des preuves nécessaires pour publier.
Une case ne doit être cochée qu’avec un artefact ou un résultat reproductible.

## Implémentation présente

- [x] `MARKETING_VERSION` 1.2.2, build 12101 et convention de builds
  bêta/RC/stable/correctif.
- [x] Schéma `modes.json` v2, migration v1, permissions `0600` et sauvegarde
  conservée deux lancements.
- [x] Douze modes natifs, modes personnalisés et profils d’application opt-in.
- [x] Registre de raccourcis Dictée, Transformation et mode, avec rollback en
  cas de conflit d’enregistrement.
- [x] Consentement cloud interactif, timeout, brut, consentement persistant
  signé par mode/fournisseur/modèle/sources.
- [x] Capture de sélection AX et fallback presse-papiers sérialisé.
- [x] Validation de PID, bundle, fenêtre, élément, plage et hash avant écriture.
- [x] Aperçu obligatoire des transformations et retranscriptions.
- [x] Replay audio en mémoire, trois éléments/10 Mo/cinq minutes.
- [x] Diff mot à mot pour les transformations courtes et comparaison
  post-insertion Brut/Final sans remplacement.
- [x] Cinquante variantes automatisées d’injection passive sans outil ni
  promotion du contexte en instruction.
- [x] Canal Sparkle bêta, validation des tags et fusion stable/bêta d’appcast.
- [x] Routeurs et dépôt de modèles constituant le socle technique 1.3.

## Finition de code bloquant l’étiquette stable

- [x] Ajouter un vrai enregistreur de raccourci dans les réglages, y compris
  l’affichage immédiat des conflits Carbon et des doublons Pressay.
- [x] Ajouter la fixture AX AppKit/SwiftUI et automatiser ses scénarios de
  sélection, destruction de cible et champ sécurisé.
- [x] Ajouter les labels VoiceOver, les alternatives non colorimétriques, les
  raccourcis clavier et la réduction des animations aux HUD/aperçus.
- [ ] Rejouer manuellement l’ordre clavier, VoiceOver et le contraste renforcé
  sur une session macOS propre.

## Matrice bêta

Pour chaque application Tier A : 20 dictées simples, 10 changements
d’application, 10 transformations, 5 annulations, 5 changements concurrents du
presse-papiers et 5 cibles détruites.

- [ ] TextEdit
- [ ] Notes
- [ ] Mail
- [ ] Safari
- [ ] Chrome
- [ ] Slack ou Discord
- [ ] Xcode
- [ ] VS Code
- [ ] Terminal
- [ ] Champ sécurisé natif
- [ ] Champ sécurisé web

Tier B — au moins quatre applications, avec un testeur par application :

- [ ] Google Docs
- [ ] Notion
- [ ] Cursor
- [ ] iTerm
- [ ] Microsoft Word

## Distribution et promotion

- [x] Créer la branche `gh-pages`, publiée uniquement par le workflow Release.
- [x] Configurer GitHub Pages sur la racine de cette branche et valider
  `https://yoanndrx.github.io/pressay/appcast.xml`.
- [x] Rediriger définitivement les anciens feeds Pressay et Whisper vers
  `https://yoanndrx.github.io/pressay/appcast.xml` ; PR portfolio validée,
  fusionnée et déployée.
- [x] Valider les six secrets de publication dans l'environnement GitHub
  protégé `release` : P12 CI, mot de passe P12, compte et équipe Apple, mot de
  passe spécifique Apple et clé Sparkle exportée en Base64. Aucun doublon ne
  subsiste au niveau dépôt ; le mot de passe du Keychain temporaire est généré
  et masqué à chaque workflow.
- [x] Produire
  [`v1.2.0-beta.1`](https://github.com/YoannDrx/pressay/releases/tag/v1.2.0-beta.1)
  build 12001 avec DMG, checksum et appcast signés. Le run
  [`30348895645`](https://github.com/YoannDrx/pressay/actions/runs/30348895645)
  valide les tests, l'analyse, l'archive universelle, la notarisation, Gatekeeper,
  la signature Sparkle, la GitHub Release et la publication Pages.
- [x] Retélécharger les assets publics et vérifier indépendamment le SHA-256,
  le ticket agrafé, Gatekeeper sur le DMG et l'app montée, `arm64 + x86_64`,
  la version 1.2.0/build 12001 et la signature Ed25519 de l'appcast.
- [x] Comparer l'appcast de la release et celui de GitHub Pages octet par octet,
  puis valider l'ancien feed redirigé vers le feed canonique.
- [ ] Tester stable → bêta, bêta → bêta et bêta → stable.
- [ ] Couvrir au moins un Mac Apple Silicon et un Mac Intel.
- [ ] Obtenir cinq testeurs minimum et sept jours sans P0/P1.
- [x] Exporter des diagnostics par liste blanche et vérifier automatiquement
  l’absence de texte, audio, sélection, vocabulaire privé et clé API.
- [x] Produire localement l’archive Release build 12001 universelle signée
  Developer ID, vérifier sa signature profonde, son Team ID, Hardened Runtime
  et `arm64 + x86_64`.
- [x] Publier les stables 1.2.0 puis 1.2.1, notariser, vérifier Gatekeeper et
  promouvoir le feed stable.
- [x] Publier les correctifs 1.2.2 build 12101 puis 1.2.3 build 12102 ; pour
  1.2.3, retélécharger les trois artefacts, vérifier SHA-256, ticket agrafé,
  Gatekeeper, signature, Team ID, Hardened Runtime, `arm64 + x86_64`, appcast
  public et installation dans `/Applications` sur Apple Silicon.
- [x] Valider le correctif Codex de 1.2.4 build 12103 avec une dictée Fn réelle,
  le presse-papiers préservé, 120 tests Swift et les builds universels Direct et
  App Store.

## Socle 1.3 non publiable

Les routeurs et le dépôt de modèles sont présents, mais 1.3 reste derrière les
gates suivants :

- [ ] intégrer et épingler FluidAudio/Parakeet ;
- [ ] produire et intégrer le XCFramework whisper.cpp universel ;
- [x] ajouter le code SpeechAnalyzer et Foundation Models sous disponibilité
  macOS 26 et compilation conditionnelle ; ils restent hors des capacités
  garanties du binaire 1.2 jusqu’au passage des gates 1.3 ;
- [ ] intégrer llama.cpp/Qwen opt-in ;
- [ ] signer et publier le catalogue de modèles ;
- [ ] livrer l’interface de téléchargement, pause, reprise et suppression ;
- [ ] constituer le corpus consenti et passer les gates WER/latence/mémoire.
