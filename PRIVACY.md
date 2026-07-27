# Politique de confidentialité

Dernière mise à jour : 27 juillet 2026

Pressay est une application macOS locale de dictée vocale. Elle ne contient aucun
outil publicitaire, traqueur ou service de télémétrie distant.

## Données traitées

- **Audio** : l'enregistrement reste dans un fichier temporaire sur le Mac. Il
  n'est envoyé à l'API OpenAI que si une activité vocale est détectée localement,
  puis il est supprimé après la réponse ou l'annulation.
- **Texte transcrit** : il est reçu depuis l'API OpenAI, inséré dans l'application
  choisie et, si l'historique est activé, conservé uniquement sur le Mac.
- **Clé API** : elle est stockée dans le Trousseau macOS et transmise uniquement
  à l'API OpenAI pour authentifier les requêtes de transcription.
- **Historique** : il est optionnel, chiffré localement avec AES-256-GCM et
  automatiquement supprimé selon la durée choisie (24 heures, 7 jours ou 30 jours).
- **Mesures de performance** : si l'option est activée, seules des moyennes de
  durées par étape sont conservées dans les préférences locales. Aucun audio,
  texte, identifiant personnel ou contenu de presse-papiers n'est enregistré.
- **Mises à jour** : Sparkle contacte le flux public de versions et GitHub pour
  vérifier ou télécharger une mise à jour. Pressay ne joint aucun profil système
  à cette requête.

## Destinataires

L'audio et le contexte de vocabulaire actif sont envoyés exclusivement à
l'endpoint de transcription OpenAI sélectionné par l'utilisateur. Leur traitement
est alors soumis aux conditions et politiques d'OpenAI. Pressay n'envoie aucune
donnée à l'auteur du projet.

Le téléchargement de l'application est gratuit. L'utilisation de la clé API
personnelle peut être facturée directement par OpenAI selon ses tarifs. Yodev ne
reçoit ni paiement, ni contenu de dictée, ni métrique d'utilisation.

## Permissions macOS

- Le microphone sert uniquement à capturer la dictée.
- L'accessibilité sert uniquement à simuler le collage dans l'application cible.
- Les événements clavier globaux servent uniquement à détecter le raccourci choisi.

## Contrôle par l'utilisateur

L'utilisateur peut désactiver et effacer l'historique, réinitialiser les mesures
locales et supprimer sa clé API depuis les réglages. Désactiver l'historique
supprime immédiatement son fichier local.

Pour toute question, utiliser les issues du dépôt
[YoannDrx/pressay](https://github.com/YoannDrx/pressay/issues).

Pressay par Yodev est une application indépendante utilisant l'API OpenAI. Elle
n'est ni éditée ni approuvée par OpenAI.
