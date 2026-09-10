# Éléments à tester — candidat 2.0.0 (2.0.4)

Candidat utilisant le service de production Pressay et les achats Sandbox Apple,
isolés des abonnements réels. La distribution de test attend la validation Apple
du dossier de chiffrement.
Utilisez un compte de test. Ce build ne valide pas encore une ouverture commerciale.

À vérifier :

- Premier lancement : téléchargement d’un modèle, autorisation du microphone et
  des fonctions d’accessibilité, puis première dictée dans une autre application.
- Dictée : raccourci, maintien de la touche, annulation, changement de microphone,
  veille/reprise et capture longue. Après téléchargement du modèle, vérifier la
  transcription locale sans connexion Internet.
- Historique : recherche, navigation entre les pages, copie et suppression ;
  vérifier que les résultats restent cohérents lors de recherches rapides.
- Compte : connexion Apple, déconnexion, relancement et absence de réactivation
  d’une ancienne session après déconnexion.
- Pro : achat mensuel et annuel Sandbox, annulation de l’achat, restauration,
  achat interrompu puis reprise au relancement. Vérifier les droits dans l’app
  après renouvellement, expiration ou remboursement de test.
- Synchronisation : récupération des données avec le même compte sur un second
  Mac et absence d’accès aux données avec un autre compte.

Pour chaque anomalie, indiquez le modèle du Mac, la version de macOS, les étapes
et le résultat attendu. N’incluez pas d’enregistrement confidentiel ni de secret
de récupération dans le retour de test.
