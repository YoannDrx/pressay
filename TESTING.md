# Plan de test

## Automatisé

```bash
xcodebuild test \
  -project Pressay.xcodeproj \
  -scheme Pressay \
  -configuration Debug \
  -destination 'platform=macOS'
```

La cible `PressayTests` couvre :

- silence et enregistrement trop court ;
- pic sonore bref rejeté et voix détectée au-dessus du bruit ambiant ;
- voix au-dessus d'un bruit ambiant adaptatif ;
- réponse vide ou égale au vocabulaire/prompt français ou anglais ;
- assemblage multipart et délimiteur final ;
- expiration de l'historique ;
- migration idempotente depuis `fr.yodev.whisper` et `com.hyrak.whisper` ;
- priorité des données Pressay et reprise après une erreur Keychain ;
- déplacement atomique de `Application Support/Whisper` ;
- configuration Sparkle sans profil système et action manuelle ;
- transitions valides et invalides de la machine d’état ;
- restriction et manifeste stable des sources de contexte ;
- priorité des modes explicite, application, manuel et défaut ;
- persistance des modes personnalisés et règles d’application ;
- migration des modes v1 vers le schéma v2 et cycle de vie de la sauvegarde ;
- requête Responses API sans stockage et exclusion du contexte non autorisé ;
- file de session, cible initiale, historique et annulation d’insertion ;
- refus du silence et des champs sécurisés avant tout traitement ;
- refus du cloud tant que le consentement n’est pas obtenu, payload exact
  autorisé et parcours « Utiliser le brut » ;
- transformation de sélection, fallback presse-papiers, aperçu obligatoire et
  application du résultat édité ;
- replay audio : capacité, taille maximale et expiration.
- cinquante variantes d’injection passive confinées aux sections de données,
  sans déclaration d’outil dans la requête.
- conflits de raccourcis et conservation de l’ancienne combinaison ;
- validation stricte de la plage et du hash de sélection, y compris lorsqu’un
  élément AX est détruit ;
- refus défensif de tout fournisseur cloud sous `localOnly`, y compris lorsqu’il
  est explicitement configuré ;
- invalidation du consentement persistant après changement de fournisseur,
  modèle ou sources ;
- export de diagnostics par liste blanche sans contenu utilisateur ni clé ;
- fusion de trois releases stables et cinq bêtas dans l’appcast.

La suite contient actuellement **77 tests Swift et 2 tests Python**. Cette suite ne remplace ni les
tests AX réels ni la matrice interapplications.

## Vérifications de release automatisées

```bash
scripts/validate-app-store.sh
zsh -n scripts/archive-app-store.sh scripts/validate-app-store.sh
RELEASE_TAG=v1.2.0-beta.1 scripts/validate-release.sh
zsh -n scripts/notarize.sh scripts/validate-release.sh
python3 -m py_compile scripts/merge-appcast.py
python3 scripts/test-merge-appcast.py
xcodebuild build \
  -project Pressay.xcodeproj \
  -target PressayAXFixture \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO
xcodebuild analyze \
  -project Pressay.xcodeproj \
  -scheme Pressay \
  -configuration Release \
  -destination 'platform=macOS'
xcodebuild build \
  -project Pressay.xcodeproj \
  -scheme Pressay \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO
```

`validate-app-store.sh` construit séparément `Pressay Companion.app` en Release
universelle, vérifie App Sandbox et le manifeste de confidentialité, puis refuse
Sparkle et les symboles Accessibility/Carbon/CGEvent. Cette validation statique
ne remplace pas une archive signée, l'analyse d'App Store Connect ni TestFlight.

Ces commandes valident le code et le paquet universel non signé. Elles ne
remplacent ni l’archive Developer ID, ni la notarisation, ni Gatekeeper, ni les
tests sur un Mac Intel réel.

La cible `PressayAXFixture` fournit `NSTextField`, `NSTextView`,
`NSSecureTextField`, `SwiftUI.TextField`, `TextEditor` et `SecureField`, ainsi
que des boutons pour modifier une sélection ou détruire l’élément focalisé.
Elle est construite par la CI et sert de référence reproductible à la matrice
AX manuelle.

## Matrice manuelle avant une release

| Scénario | Résultat attendu |
| --- | --- |
| Appuyer sur Fn sans parler puis relâcher | Aucun appel utile, aucun collage, message « Aucune parole détectée » |
| Dictée courte après le signal | Texte inséré dans l'application initialement active |
| Démarrer une seconde dictée pendant la transcription | Seconde dictée mise en file, sans écraser la première cible |
| Annuler pendant l'appel API | Fichier temporaire supprimé, aucun collage |
| Refuser le microphone | Aucun prompt au lancement, explication dans les réglages |
| Refuser l'accessibilité | Résultat copié dans le presse-papiers, aucun texte perdu |
| Autoriser l'accessibilité puis relancer | Collage natif Cmd+V sans permission Automatisation |
| Copier autre chose pendant l'insertion | Le nouveau presse-papiers utilisateur n'est pas écrasé |
| Mode bascule | Premier appui démarre, second appui envoie |
| Double pression du raccourci Maintenir | La capture reste active jusqu’au prochain appui |
| Appuyer sur Échap pendant capture, traitement ou aperçu | État annulé, aucun collage, audio temporaire supprimé |
| Utiliser ⌥⇧Espace sans sélection | Aucun enregistrement, message demandant une sélection |
| Transformer une sélection | Aperçu Original/Proposition avant toute modification |
| Modifier la sélection pendant le traitement | Aucun remplacement ; proposition copiée et avertissement |
| Transformer via fallback `Cmd+C` | Sélection capturée et ancien presse-papiers restauré |
| Transformer une sélection contenant une instruction | Instruction passive ignorée ; seule la parole pilote la transformation |
| Lancer Pressay dans un champ sécurisé | Micro non démarré, aucun contexte lu et aucun historique créé |
| Mode `askBeforeCloud` sans consentement | Aucun appel au processeur cloud |
| Mode excluant la sélection | Sélection absente de la requête et du manifeste cloud |
| Règle d’application | Mode correspondant au bundle ID actif, sauf mode/raccourci explicite |
| Cible AX détruite pendant le traitement | Résultat copié, aucun collage dans une autre cible |
| Annuler après insertion compatible | Texte initial restauré tant que le jeton est valide |
| Historique désactivé | Fichier local supprimé et aucune nouvelle entrée |
| Clé API restreinte à la transcription | Validation acceptée sans accès à `/v1/models` |

La matrice doit être rejouée dans TextEdit, Notes, Mail, Slack ou Discord,
Safari, Chrome, Google Docs, Notion, Xcode, Cursor, VS Code, Terminal, iTerm,
Word, un champ mot de passe natif et un champ sécurisé web. Citrix et les
bureaux distants sont documentés comme cas limités jusqu’à validation dédiée.

Les tests de qualité acoustique doivent être répétés avec le micro interne, des
AirPods et un micro USB, dans une pièce calme puis avec ventilation/bruit de
fond. Le corpus consenti FR/EN/code-switching doit mesurer WER/CER, précision du
lexique technique, latence, mémoire, énergie et hallucinations. L’historique
réel de l’utilisateur n’est jamais un corpus implicite.
