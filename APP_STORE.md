# Publication Mac App Store

Ce document suit la variante App Store de Pressay. Elle est volontairement
séparée de la distribution directe : le Mac App Store exige App Sandbox et
interdit les mécanismes de mise à jour externes, alors que la dictée universelle
de Pressay direct dépend d'Accessibility, d'événements clavier globaux et de
Sparkle.

## Produits

| Canal | Produit | Bundle ID | Version initiale | Livraison du texte |
| --- | --- | --- | --- | --- |
| Direct | `Pressay.app` | `fr.yodev.pressay` | 1.2.2 | Insertion universelle lorsque la cible est vérifiable |
| Mac App Store | `Pressay Companion.app` | `fr.yodev.pressay` | 1.2.0 (12004) | Presse-papiers et Voice Inbox |

La variante App Store ne doit jamais promettre la dictée universelle. Elle
propose une dictée déclenchée depuis la barre des menus, les douze modes, les
modes personnalisés, l'historique chiffré et la Voice Inbox. Le résultat est
copié ; l'utilisateur le colle où il le souhaite.

## État du code et de la livraison au 3 août 2026

- cible et schéma partagés `Pressay App Store` présents dans Xcode ;
- compilation conditionnelle `APP_STORE` ;
- App Sandbox, microphone, réseau sortant et fichiers choisis par l'utilisateur ;
- aucun Sparkle, Carbon, `AXUIElement` ou événement `CGEvent` dans le binaire ;
- fenêtre principale visible au lancement et contrôle manuel de capture ;
- manifeste `PrivacyInfo.xcprivacy` inclus ;
- build Release universel vérifié par `scripts/validate-app-store.sh` ;
- tests de non-régression de la variante directe conservés.
- archive 1.2.0 (12001) signée, téléversée et acceptée par Apple en
  `BETA_INTERNAL_TESTING` ; le candidat source suivant porte désormais le build
  unique 12002, désormais obsolète ;
- les paquets 12002 et 12003 sont obsolètes ; le candidat source 12004 remplace
  le routage multi-provider par OpenAI + WhisperKit local et doit recevoir une
  nouvelle archive avant téléversement ;
- textes français publiés dans App Store Connect ;
- trois captures 1440 × 900 sans transparence prêtes dans
  `AppStoreAssets/Screenshots/Final` ;
- PR de fondation App Store fusionnée dans `main`.

La cible est alignée sur la fiche App Store Connect `6795505605`, qui utilise
le bundle historique `fr.yodev.pressay`. La distribution directe et la variante
App Store ne sont jamais installées simultanément : installer l'une remplace
l'autre, ce qui préserve une identité produit unique dans macOS.

## Contrôle local

```bash
scripts/validate-app-store.sh

xcodebuild test -quiet \
  -project Pressay.xcodeproj \
  -scheme Pressay \
  -destination 'platform=macOS'
```

Le validateur construit une Release non signée `arm64 + x86_64`, contrôle le
sandbox, le manifeste, l'absence de Sparkle et l'absence de symboles d'API
interapplications incompatibles. Il ne remplace ni la signature de
distribution, ni la validation App Store Connect, ni un test TestFlight.

Une fois l'identifiant confirmé et le certificat Apple Distribution ainsi que
le profil disponibles :

```bash
scripts/archive-app-store.sh
```

Le script refuse d'écraser un export existant. Il ne demande rien à Apple par
défaut. Si le compte développeur est déjà connecté dans Xcode, l'option suivante
autorise explicitement Xcode à demander ou actualiser le certificat,
l'identifiant et les profils nécessaires :

```bash
ALLOW_PROVISIONING_UPDATES=1 scripts/archive-app-store.sh
```

L'export est écrit dans `build/app-store/<version>-<build>/` et reste local ;
le script ne téléverse et ne soumet rien automatiquement.

## Pré requis Apple

1. La fiche `6795505605` et l'App ID explicite `fr.yodev.pressay` sont alignés.
2. Xcode gère la signature via un certificat Apple Distribution cloud et un
   profil Mac App Store Connect valable jusqu'au 31 juillet 2027.
3. Accepter les contrats encore signalés dans Business. Le statut de commerçant
   DSA est déjà vérifié ; les contrats, informations fiscales et bancaires ne
   sont nécessaires que selon les territoires et le modèle économique choisis.
4. L’archive `Pressay App Store` a été signée, validée puis téléversée.
5. La conformité export est déclarée par `ITSAppUsesNonExemptEncryption = false`
   et le build a terminé son traitement Apple.
6. Il reste à tester une installation via TestFlight sur une session macOS
   propre.
7. Il reste à actualiser les captures si l'écran Fournisseurs a changé, publier
   les réponses de confidentialité, compléter la classification d’âge, associer
   le build et fournir une clé API temporaire à App Review avant la soumission.

Apple documente l'App Sandbox comme une exigence du Mac App Store et exige que
les mises à jour App Store passent par l'App Store. Le flux direct reste donc un
artefact distinct, construit avec d'autres entitlements, même si les deux
éditions partagent l'identité de bundle historique de Pressay.

`Info-AppStore.plist` déclare `ITSAppUsesNonExemptEncryption = false` : le
build utilise uniquement HTTPS et les primitives CryptoKit fournies par macOS.
Cette valeur évite le statut « Missing Compliance » lorsque l'usage reste
exempt ; si une bibliothèque cryptographique non système est ajoutée, la
déclaration devra être réévaluée avant l'envoi.

## Métadonnées proposées

### Français

- **Nom** : Pressay
- **Sous-titre** : Dictée vocale pour macOS
- **Catégorie principale** : Productivité
- **Catégorie secondaire** : Utilitaires
- **Mots-clés** : dictée,vocal,transcription,texte,productivité,notes,IA
- **Texte promotionnel** : Dictez, reformulez et retrouvez vos idées depuis la
  barre des menus, avec une clé API personnelle et un historique local chiffré.

Description courte à développer dans App Store Connect :

> Pressay Companion transforme votre voix en texte sans imposer de compte
> Pressay. Démarrez une dictée depuis la barre des menus, choisissez un mode de
> rédaction et récupérez immédiatement le résultat dans le presse-papiers et,
> si vous le souhaitez, dans une Voice Inbox chiffrée sur votre Mac.
>
> Utilisez le mode Fidèle pour une transcription directe ou les modes Propre,
> Message, Email, Prompt IA, Note, Compte rendu, Ticket, Commit, Traduction,
> Résumé et Tâches pour adapter le résultat. Vous gardez le contrôle du contenu
> transmis. Utilisez votre propre clé API OpenAI, stockée dans le Trousseau, ou
> téléchargez WhisperKit pour une transcription Fidèle entièrement locale.

Ajouter sans ambiguïté à la description :

> En raison des règles de sécurité du Mac App Store, cette édition copie le
> résultat dans le presse-papiers et ne l'insère pas automatiquement dans les
> autres applications. La version directe de Pressay propose séparément cette
> capacité et nécessite l'autorisation Accessibilité.

### Anglais

- **Name**: Pressay Companion
- **Subtitle**: Controlled voice dictation
- **Keywords**: dictation,voice,transcription,text,productivity,notes,AI

L'interface n'est pas encore entièrement localisée en anglais. Ne publier la
fiche anglaise qu'après validation de chaque chaîne visible, ou conserver le
français comme langue principale pour le premier build.

## Captures produites

Apple demande entre une et dix captures macOS sans transparence. Les trois
captures prêtes à charger sont :

1. `01-dictee.png` : réglages et garanties locales ;
2. `02-menu.png` : parcours de dictée depuis la barre des menus ;
3. `03-modes.png` : modes de rédaction.

Elles mesurent 1440 × 900, ne contiennent ni transparence, ni clé API, ni texte
personnel, ni notification d’une autre app.

Les captures doivent montrer le comportement réel de l'édition App Store. Ne
pas montrer ni mentionner un collage automatique dans une app tierce.

## Confidentialité App Store Connect

La fiche doit contenir une URL publique stable vers `PRIVACY.md` rendu sur le
site ou vers une page équivalente. Les réponses de collecte couvrent OpenAI ;
WhisperKit traite l’audio localement et n’entraîne pas de collecte distante.

Réponses prudentes pour le premier build :

- collecte déclarée : **Audio Data** et **Other User Content** ;
- finalité : **App Functionality** uniquement ;
- données non utilisées pour le tracking ;
- données potentiellement liées au compte OpenAI par la clé API ; le build
  12004 ne les lie pas à une identité Pressay ;
- aucune publicité, analytique distante, crash reporter tiers ou marketing ;
- clé API conservée dans le Trousseau et jamais envoyée à Yodev ;
- historique et Inbox conservés localement et chiffrés.

Apple définit la « collecte » selon la durée et l'accès au-delà du traitement
temps réel. Les réponses finales doivent néanmoins rester prudentes et refléter
les pratiques réelles des fournisseurs au moment de la soumission. Toute
modification de fournisseur, de rétention ou de télémétrie impose une mise à
jour de la fiche.

## Notes destinées à App Review

Préparer une note explicite :

1. Pressay Companion est une app de barre des menus ; une fenêtre de réglages
   s'ouvre au premier lancement et l'icône reste visible en haut de l'écran.
2. Suivre l’onboarding, autoriser le microphone, saisir une clé API OpenAI de
   test, choisir Fidèle,
   cliquer **Démarrer une dictée**, parler, puis cliquer **Terminer la dictée**.
3. Le résultat est copié dans le presse-papiers et ajouté à la Voice Inbox. Le
   comportement est volontaire et résulte du sandbox ; aucune permission
   Accessibilité n'est demandée.
4. Les transformations cloud utilisent la clé personnelle et affichent le mode
   et les sources pertinentes. Aucun compte Pressay n'est requis.
5. L'app ne télécharge ni code exécutable ni mécanisme de mise à jour externe.
   Le téléchargement WhisperKit est une ressource Core ML non exécutable,
   déclenchée explicitement et supprimable dans les réglages.

Apple doit pouvoir tester le parcours complet. Créer pour la revue une clé API
temporaire, limitée à un projet et à un budget faible, la transmettre uniquement
dans les informations privées d'App Review, puis la révoquer après décision. Ne
jamais embarquer cette clé dans l'app ou le dépôt.

## Gate avant « Submit for Review »

- `scripts/validate-app-store.sh` vert ;
- suite Swift verte et analyse statique sans erreur ;
- archive signée validée par Xcode ;
- build traité et sans avertissement bloquant dans App Store Connect ;
- TestFlight testé sur un Mac sans environnement de développement ;
- microphone refusé puis accordé, hors-ligne et clé invalide testés ;
- texte toujours récupérable après une erreur réseau ;
- suppression Historique/Inbox vérifiée ;
- aucune permission Accessibilité ou Automatisation demandée ;
- aucune mention de dictée universelle dans les métadonnées App Store ;
- captures sans données privées ;
- URL d'assistance et politique de confidentialité publiques ;
- classification d'âge, droits sur le contenu et conformité export complétés ;
- prix/disponibilité et méthode de publication choisis ;
- clé de revue temporaire OpenAI valide et notes de revue complètes.
