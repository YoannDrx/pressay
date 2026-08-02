# Politique de confidentialité

Dernière mise à jour : 2 août 2026

Pressay est une application macOS de dictée et de transformation vocale. Elle ne
contient aucun outil publicitaire, traqueur ou service de télémétrie distant.

## Données traitées

- **Audio** : l'enregistrement reste dans un fichier temporaire sur le Mac. Si
  OpenAI est choisi, il n'est envoyé à OpenAI qu'après détection locale d'une
  activité vocale. Si WhisperKit est choisi, il ne quitte pas le Mac. Le fichier
  est supprimé après la réponse ou l'annulation.
- **Texte transcrit** : il est produit par OpenAI ou WhisperKit, puis inséré dans
  l'application choisie et, si l'historique est activé, conservé uniquement sur
  le Mac.
- **Transformations** : pour tout mode autre que Fidèle, la dictée et les seules
  sources de contexte autorisées par ce mode sont envoyées à OpenAI. Une transformation de
  sélection peut inclure le texte sélectionné,
  explicitement séparé de l'instruction vocale et traité comme une donnée non
  fiable. La requête utilise `store: false`. Avant un envoi soumis à
  confirmation, Pressay montre le fournisseur, le modèle, les sources, leur
  taille et leur contenu exact ; cet aperçu n'est pas persisté.
- **Contexte applicatif** : l'application, le titre de fenêtre, la sélection ou
  le contexte adjacent ne sont capturés qu'au déclenchement. Pressay n'effectue
  aucune surveillance permanente de l'écran, du presse-papiers ou des fichiers.
  Le HUD affiche le manifeste des sources avant leur envoi cloud.
- **Clé API OpenAI** : elle est stockée dans le Trousseau macOS et transmise
  uniquement à OpenAI pour authentifier les requêtes. OpenAI peut donc relier les requêtes au compte auquel
  appartient la clé ; Pressay ne reçoit pas cette identité.
- **Historique** : il est optionnel, chiffré localement avec AES-256-GCM et
  automatiquement supprimé selon la durée choisie (24 heures, 7 jours ou 30 jours).
- **Voice Inbox** : elle est désactivée par défaut. Lorsqu’elle est activée, un
  résultat sans cible éditable peut être conservé dans un fichier chiffré
  distinct, avec une clé Keychain distincte et une rétention de 7, 30 ou 90
  jours. Son contenu ne quitte pas le Mac du seul fait de son enregistrement.
- **Journal d’actions** : les propositions, aperçus, confirmations et résultats
  sont conservés dans un fichier local AES-256-GCM avec une clé Trousseau dédiée.
  Les brouillons de note, rappel, calendrier ou commande ne sont jamais exécutés
  directement depuis une sortie de modèle ; l’utilisateur doit les valider.
- **Modes et règles d'application** : ils sont conservés localement dans un
  fichier accessible uniquement au compte utilisateur. Ce fichier n'est pas
  annoncé comme chiffré.
- **Mesures de performance** : si l'option est activée, des moyennes et les
  trente dernières traces techniques sont conservées dans les préférences
  locales. Une trace contient uniquement les durées audio/API/traitement/
  insertion, le fournisseur, le statut de livraison et un identifiant de
  session aléatoire. Aucun audio, texte, contexte, identifiant personnel ou
  contenu de presse-papiers n'est enregistré ni envoyé.
- **Mises à jour** : Sparkle contacte le flux public de versions et GitHub pour
  vérifier ou télécharger une mise à jour. Pressay ne joint aucun profil système
  à cette requête.
- **WhisperKit** : le modèle local est téléchargé explicitement dans le dossier
  Application Support de Pressay. Il peut être supprimé depuis les réglages et
  n’exécute aucune requête de transcription vers OpenAI.

## Destinataires

Lorsque le moteur OpenAI est choisi, l'audio et le contexte de vocabulaire actif
sont envoyés à OpenAI. Pour un mode de transformation, le texte et le contexte
explicitement autorisé sont envoyés à OpenAI. Leur traitement est soumis aux
conditions et politiques d’OpenAI.
Lorsque l'API le permet, Pressay désactive la conservation applicative de la
réponse ; ce réglage ne constitue pas à lui seul une garantie générale d'absence
de rétention par le fournisseur. Le build public actuel n'envoie aucun contenu
de dictée à Yodev.

Le téléchargement de l'application est gratuit. L'utilisation d'une clé API
personnelle peut être facturée directement par son fournisseur selon ses tarifs.
Yodev ne reçoit ni paiement, ni contenu de dictée, ni métrique d'utilisation
dans le build public actuel.

## Variantes de distribution et permissions macOS

La version directe et l'édition Mac App Store sont des bundles distincts :

- **Pressay direct** utilise le microphone, Accessibility et les événements
  clavier globaux pour conserver la cible et insérer le texte ;
- **Pressay Companion (Mac App Store)** fonctionne dans App Sandbox, utilise le
  microphone et le réseau sortant, puis copie le résultat dans le presse-papiers
  et la Voice Inbox. Elle ne demande pas Accessibility et ne surveille aucun
  raccourci global.

Pour la version directe :

- Le microphone sert uniquement à capturer la dictée.
- L'accessibilité sert à identifier la cible, détecter les champs sécurisés,
  capturer la sélection demandée et simuler le collage dans l'application cible.
- Les événements clavier globaux servent uniquement à détecter le raccourci choisi.

L'édition App Store ne contient pas Sparkle : ses mises à jour sont distribuées
uniquement par le Mac App Store.

## Contrôle par l'utilisateur

L'utilisateur peut désactiver et effacer l'historique ou la Voice Inbox,
réinitialiser les mesures locales, modifier ou supprimer ses modes et règles,
et supprimer sa clé API depuis les réglages. Désactiver l'historique ou la
Voice Inbox supprime immédiatement le fichier local correspondant. Les champs
sécurisés sont exclus avant le démarrage de l'enregistrement.

Pour toute question, utiliser les issues du dépôt
[YoannDrx/pressay](https://github.com/YoannDrx/pressay/issues).

Pressay par Yodev est une application indépendante utilisant l’API OpenAI et le
projet open source WhisperKit. Elle n'est ni éditée ni approuvée par OpenAI ou Argmax.
