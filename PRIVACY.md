# Politique de confidentialité

Dernière mise à jour : 28 juillet 2026

Pressay est une application macOS de dictée et de transformation vocale. Elle ne
contient aucun outil publicitaire, traqueur ou service de télémétrie distant.

## Données traitées

- **Audio** : l'enregistrement reste dans un fichier temporaire sur le Mac. Il
  n'est envoyé à l'API OpenAI que si une activité vocale est détectée localement,
  puis il est supprimé après la réponse ou l'annulation.
- **Texte transcrit** : il est reçu depuis l'API OpenAI, inséré dans l'application
  choisie et, si l'historique est activé, conservé uniquement sur le Mac.
- **Transformations** : pour tout mode autre que Fidèle, la dictée et les seules
  sources de contexte autorisées par ce mode sont envoyées à la Responses API
  OpenAI. Une transformation de sélection peut inclure le texte sélectionné,
  explicitement séparé de l'instruction vocale et traité comme une donnée non
  fiable. La requête utilise `store: false`. Avant un envoi soumis à
  confirmation, Pressay montre le fournisseur, le modèle, les sources, leur
  taille et leur contenu exact ; cet aperçu n'est pas persisté.
- **Contexte applicatif** : l'application, le titre de fenêtre, la sélection ou
  le contexte adjacent ne sont capturés qu'au déclenchement. Pressay n'effectue
  aucune surveillance permanente de l'écran, du presse-papiers ou des fichiers.
  Le HUD affiche le manifeste des sources avant leur envoi cloud.
- **Clé API** : elle est stockée dans le Trousseau macOS et transmise uniquement
  à l'API OpenAI pour authentifier les requêtes de transcription et de
  transformation.
- **Historique** : il est optionnel, chiffré localement avec AES-256-GCM et
  automatiquement supprimé selon la durée choisie (24 heures, 7 jours ou 30 jours).
- **Voice Inbox** : elle est désactivée par défaut. Lorsqu’elle est activée, un
  résultat sans cible éditable peut être conservé dans un fichier chiffré
  distinct, avec une clé Keychain distincte et une rétention de 7, 30 ou 90
  jours. Son contenu ne quitte pas le Mac du seul fait de son enregistrement.
- **Modes et règles d'application** : ils sont conservés localement dans un
  fichier accessible uniquement au compte utilisateur. Ce fichier n'est pas
  annoncé comme chiffré.
- **Mesures de performance** : si l'option est activée, seules des moyennes de
  durées par étape sont conservées dans les préférences locales. Aucun audio,
  texte, identifiant personnel ou contenu de presse-papiers n'est enregistré.
- **Mises à jour** : Sparkle contacte le flux public de versions et GitHub pour
  vérifier ou télécharger une mise à jour. Pressay ne joint aucun profil système
  à cette requête.
- **Fournisseurs locaux Apple** : sur les systèmes compatibles, l’utilisateur
  peut sélectionner SpeechAnalyzer pour la transcription et Foundation Models
  pour la transformation. Dans ce cas, la tâche concernée est traitée sur le
  Mac et aucun appel OpenAI n’est effectué pour cette étape.

## Destinataires

L'audio et le contexte de vocabulaire actif sont envoyés à l'endpoint de
transcription OpenAI sélectionné par l'utilisateur. Pour un mode de
transformation, le texte et le contexte explicitement autorisé sont envoyés à la
Responses API OpenAI. Leur traitement est alors soumis aux conditions et
politiques d'OpenAI. `store: false` désactive la conservation de la réponse comme
état applicatif ; ce paramètre ne constitue pas à lui seul une garantie générale
d'absence de rétention par le fournisseur. Pressay n'envoie aucune donnée à
l'auteur du projet.

Le téléchargement de l'application est gratuit. L'utilisation de la clé API
personnelle peut être facturée directement par OpenAI selon ses tarifs. Yodev ne
reçoit ni paiement, ni contenu de dictée, ni métrique d'utilisation.

## Permissions macOS

- Le microphone sert uniquement à capturer la dictée.
- L'accessibilité sert à identifier la cible, détecter les champs sécurisés,
  capturer la sélection demandée et simuler le collage dans l'application cible.
- Les événements clavier globaux servent uniquement à détecter le raccourci choisi.

## Contrôle par l'utilisateur

L'utilisateur peut désactiver et effacer l'historique ou la Voice Inbox,
réinitialiser les mesures locales, modifier ou supprimer ses modes et règles,
et supprimer sa clé API depuis les réglages. Désactiver l'historique ou la
Voice Inbox supprime immédiatement le fichier local correspondant. Les champs
sécurisés sont exclus avant le démarrage de l'enregistrement.

Pour toute question, utiliser les issues du dépôt
[YoannDrx/pressay](https://github.com/YoannDrx/pressay/issues).

Pressay par Yodev est une application indépendante utilisant l'API OpenAI. Elle
n'est ni éditée ni approuvée par OpenAI.
