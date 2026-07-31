# Plan d’implémentation Pressay

État de référence : 31 juillet 2026. Ce document distingue le code présent, la
validation encore requise et les lots futurs. Une case n’est terminée que si le
parcours nominal, les erreurs, les permissions, la suppression des données et
les tests de non-régression sont couverts.

## Lot A — expérience de dictée et HUD

État : implémenté, validation manuelle à terminer.

- HUD confortable ou compact, position bas, haut ou près du pointeur ;
- durée du résultat rapide, équilibrée, détendue ou fermeture manuelle ;
- états séparés écoute, transcription, transformation, insertion et résultat ;
- fermeture manuelle toujours disponible et actions de résultat facultatives ;
- choix du mode pendant la capture sans voler le focus de l’application cible ;
- détail local/cloud et fournisseur réellement utilisé ;
- annulation par Échap dans tous les états visibles.

Gate : vérifier clavier, VoiceOver, contraste, réduction des animations, écrans
multi-moniteurs et changement d’espace macOS.

## Lot B — correction vocale et récupération

État : implémenté, matrice AX à terminer.

- action `Corriger` dans le résultat et raccourci configurable `⌥⇧R` ;
- sélection exacte de la dernière insertion seulement si cible, fenêtre, plage
  et texte sont encore prouvables ;
- réutilisation du pipeline de transformation avec aperçu obligatoire ;
- aucune suppression si la preuve de cible est insuffisante ;
- copie de secours et replay audio en mémoire, jamais sur disque durable.

Gate : Notes, TextEdit, Mail, Safari, Chrome, Electron, Xcode, VS Code,
Terminal, champs riches, cible détruite et curseur déplacé.

## Lot C — Voice Inbox privée

État : première version implémentée.

- routage vers l’Inbox lorsque la cible est absente ou non éditable ;
- fichier `inbox.enc` distinct, AES-GCM, clé Keychain distincte et permissions
  `0600` ;
- activation explicite, rétention 7/30/90 jours, copie, suppression et purge ;
- aucune capture globale du presse-papiers ;
- erreur de stockage visible et non fatale.

Suite 1.5 : ajouter métadonnées structurées, recherche, export Markdown,
Obsidian, Rappels et Calendrier lors de la migration SQLite.

## Lot D — contrôle par application

État : implémenté.

Chaque profil activé explicitement peut choisir un mode et une politique :

- automatique : injection sûre puis copie de secours ;
- aperçu : aucune modification avant confirmation ;
- copie seule : aucune tentative d’injection ;
- exclue : aucune capture audio ne démarre.

Gate : persistance/migration, priorité raccourci → explicite → app → manuel →
défaut, et vérification qu’une app exclue ne crée ni historique ni Inbox.

## Lot E — moteurs locaux système 1.3

État : code intégré, opt-in obligatoire.

- `SpeechAnalyzer` macOS 26 : langue FR/EN, assets gérés par `AssetInventory`,
  analyse de fichier et finalisation explicite ;
- Foundation Models macOS 26 Apple Silicon : disponibilité vérifiée, session
  neuve par transformation, contexte limité aux sources autorisées ;
- sélecteurs transcription et transformation dans chaque mode ;
- `localOnly` sans fallback réseau et `preferLocal` avec fallback contrôlé ;
- builds macOS 14 arm64 et x86_64 conservés.

Les types macOS 26 sont protégés par disponibilité et compilation
conditionnelle afin que la stable 1.2 continue de compiler avec Xcode 16.4. La
chaîne 1.3 devra sélectionner explicitement Xcode 26 avant de rendre ces
fournisseurs visibles dans un binaire public.

Avant activation automatique : corpus consenti, WER/CER, lexique technique,
hallucinations, p95, mémoire et énergie. Objectifs : moins de 1,5 s au p95 sur
M2 16 Go pour dix secondes, dégradation WER relative ≤ 15 %, lexique technique
≥ 90 %.

## Lot F — moteurs locaux téléchargés

État : architecture prête, implémentation à faire après le gate système.

1. Épingler FluidAudio et valider Parakeet FR/EN sur Apple Silicon.
2. Produire et vérifier le XCFramework `whisper.cpp` universel.
3. Intégrer `llama.cpp` et Qwen GGUF uniquement sur Apple Silicon.
4. Publier le manifeste Ed25519 avec URL officielle, licence, taille et SHA-256.
5. Ajouter pause, reprise, espace disque, mise à jour, rollback et suppression.
6. Interdire la suppression d’un modèle utilisé par une session.

Gate : aucune licence manquante, aucun poids dans le DMG, checksum avant
déplacement atomique, un seul fallback et aucun moteur local promu sans corpus.

## Lot G — publication 1.2.x

État : 1.2.1 publique ; correctif 1.2.2 en préparation, avec automatisation
locale verte et validation terrain continue.

1. Terminé : le launcher XCTest ne touche plus au Trousseau au démarrage et
   les 74 tests Swift passent.
2. Terminé : les 2 tests Python d’appcast et `xcodebuild analyze` passent.
3. Terminer Tier A et au moins quatre apps Tier B.
4. Tester migration, installation propre et mises à jour stable/bêta/stable.
5. Archive universelle et signature Developer ID validées ; notariser le
   livrable final puis vérifier Gatekeeper.
6. Produire DMG, SHA-256 et appcast signé pour chaque correctif public.
7. Obtenir cinq testeurs, un Mac Intel, un Apple Silicon et sept jours sans P0/P1.
8. Promouvoir la stable seulement après contrôle confidentialité et diagnostics.

La build locale installée ne doit jamais être confondue avec la bêta publiée.

## Lots suivants

- 1.4 : projets autorisés, Git synthétique et modes développeur sans shell ;
- 1.5 : SQLite chiffré, historique enrichi et Inbox structurée ;
- 1.6 : mémoire approuvée et profils rédactionnels explicables ;
- 1.7 : palette vocale et `ActionProposal` typées, jamais d’exécution directe ;
- 1.8 : OAuth minimal GitHub/Linear/Notion, CLI et MCP avec même politique ;
- 1.9 : compte optionnel, E2EE et repli local/BYOK ;
- 2.0 : réunions dans un pipeline et un stockage séparés ;
- 2.1 : localisation, accessibilité, diagnostics et onboarding finalisés.

Chaque lot commence après le gate du précédent, sauf exploration isolée derrière
un feature flag invisible. Aucun monitoring permanent de l’écran, du
presse-papiers, des fichiers ou des corrections n’est autorisé.
