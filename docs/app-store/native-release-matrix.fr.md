# Recette native du candidat Mac App Store

Registre initial du 15 septembre 2026. Aucun cas natif ci-dessous n'est déclaré
réussi avant son exécution sur un build installé depuis TestFlight.

## Identification obligatoire de chaque passage

- Commit source et numéro du build distribué par Apple.
- Mac, mémoire, macOS, modèle de transcription et microphone.
- Date, testeur, identifiant du cas et résultat : réussi, échec ou bloqué.
- Preuve locale non confidentielle et défaut associé en cas d'échec.

La matrice cible un Mac Apple Silicon sous macOS 14 et un Mac sous une version
récente de macOS. La synchronisation exige deux installations distinctes. Réserver
des comptes et données de recette ; ne pas supprimer le compte personnel de Yoann.
Les sessions, clés, codes de récupération et données privées ne figurent pas dans
les captures ni dans le dépôt.

## Parcours à exécuter

Tous les cas sont **à exécuter**. Le téléversement du nouveau candidat et sa
distribution TestFlight constituent leur dépendance commune. Les fonctions
conditionnelles doivent être testées sur une machine compatible et dans leur
état indisponible sur les autres machines.

| ID            | Manipulation                                                                                                           | Résultat attendu                                                                                                                                                           |
| ------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| INSTALL-01    | Installer depuis TestFlight dans un environnement sans données Pressay, ouvrir et continuer sans compte                | Pas de crash ; accès à Free et explications de première utilisation                                                                                                        |
| INSTALL-02    | Relancer après configuration, fermer/réouvrir la fenêtre puis lancer une seconde instance                              | Préférences conservées, une seule instance, fenêtre accessible                                                                                                             |
| MODEL-01      | Télécharger puis utiliser successivement Fast, Polyglot et Precise                                                     | Progression compréhensible, fichier valide, modèle utilisable et langue respectée                                                                                          |
| MODEL-02      | Interrompre le réseau pendant le téléchargement, rétablir puis reprendre                                               | Pas de modèle partiel proposé comme prêt ; reprise ou nouvel essai explicite                                                                                               |
| MODEL-03      | Simuler un espace insuffisant sur un volume de test, puis libérer de l'espace                                          | Erreur utile, application réactive, récupération sans réinstallation                                                                                                       |
| PERM-01       | Refuser le microphone, tenter une dictée, accorder l'autorisation dans macOS puis recommencer                          | Refus expliqué et récupération effective ; aucun état « écoute » bloqué                                                                                                    |
| PERM-02       | Refuser puis accorder Accessibilité ; tester l'insertion et la copie de secours                                        | Autorisation motivée ; aucun texte perdu ; insertion après autorisation ou copie explicitement disponible                                                                  |
| DICT-01       | Dicter 20 phrases FR puis 20 EN dans Notes, un navigateur et un éditeur                                                | Résultat dans la cible choisie, une seule insertion, pas de contenu dans une autre fenêtre                                                                                 |
| DICT-02       | Tester maintien, bascule, raccourci personnalisé et annulation avant/pendant transcription                             | Une seule session active ; annulation sans collage tardif                                                                                                                  |
| DICT-03       | Placer le curseur dans un champ de mot de passe et tenter une dictée                                                   | Refus avant ouverture du microphone, message compréhensible                                                                                                                |
| DICT-04       | Après installation du modèle, couper le réseau, dicter puis copier                                                     | Dictée Free fonctionnelle ; aucun besoin de compte ni basculement distant                                                                                                  |
| DICT-05       | Débrancher/changer le microphone pendant l'utilisation ; veille/reprise entre deux captures                            | Erreur récupérable ou périphérique rétabli ; nouvelle dictée fonctionnelle                                                                                                 |
| DICT-06       | Enchaîner 30 dictées puis une capture longue jusqu'à la limite documentée de l'app                                     | Pas de crash ni blocage durable ; limite expliquée et résultat récupérable                                                                                                 |
| HIST-01       | Activer/désactiver l'historique ; enregistrer, rechercher rapidement, paginer, copier et supprimer des entrées de test | Politique d'enregistrement respectée ; pas de résultats d'une ancienne recherche ; suppression persistante                                                                 |
| DICTIONARY-01 | Ajouter un mot fictif et une correction, dicter, modifier puis supprimer                                               | Correction appliquée selon les réglages ; pas de fuite vers un autre compte                                                                                                |
| VOICE-01      | Exécuter les commandes vocales déterministes et les transformations avancées sur un texte de test                      | Bonne commande/cible ; droits Free/Pro cohérents ; pas d'exécution involontaire lors d'une dictée ordinaire                                                                |
| MODE-01       | Créer, modifier, activer puis supprimer un mode personnalisé                                                           | Réglages persistants, sortie conforme au mode, pas de référence active cassée                                                                                              |
| PROFILE-01    | Associer des modes différents à Notes et au navigateur puis changer de cible                                           | Le bon profil s'applique ; cible sécurisée toujours protégée                                                                                                               |
| HUD-01        | Tester Minimal et Live, états écoute/traitement/erreur, thème clair/sombre et mouvement réduit                         | État lisible, pas de fenêtre bloquante, retour à l'état inactif                                                                                                            |
| AUTH-01       | Se connecter avec Apple, annuler une connexion, puis réussir et relancer                                               | Compte attendu ; annulation sans session partielle ; reconnexion cohérente                                                                                                 |
| AUTH-02       | Se déconnecter pendant un rafraîchissement puis relancer                                                               | Aucune réactivation tardive de l'ancienne session ; Free disponible                                                                                                        |
| DELETE-01     | Demander la suppression d'un compte de recette et vérifier les effets dans l'API et l'app                              | Confirmation explicite, session révoquée, données supprimées selon la politique annoncée ; distinction claire entre suppression du compte et gestion de l'abonnement Apple |
| IAP-01        | Charger les produits mensuel/annuel avec une connexion Apple de test                                                   | Prix et durées StoreKit corrects ; mêmes avantages ; pas d'offre externe                                                                                                   |
| IAP-02        | Acheter chaque formule en Sandbox sur les comptes de recette appropriés                                                | Transaction vérifiée par l'API ; Pro activé ; aucune double attribution                                                                                                    |
| IAP-03        | Annuler la feuille d'achat puis interrompre un achat et relancer                                                       | Annulation sans facturation/droit fictif ; transaction inachevée réconciliée au retour                                                                                     |
| IAP-04        | Restaurer après réinstallation et après échec du chargement du catalogue                                               | Action toujours accessible ; droits récupérés pour le compte attendu                                                                                                       |
| IAP-05        | Simuler renouvellement, expiration et remboursement avec les outils Sandbox Apple                                      | App, API et notifications convergent ; Free conservé ; aucun droit Sandbox prolongé artificiellement                                                                       |
| IAP-06        | Changer de compte Pressay et rejouer un événement de test dupliqué                                                     | Achat non attribué au mauvais compte ; pas de double effet ; données Production isolées                                                                                    |
| SYNC-01       | Sur deux Mac, synchroniser modes, profils, dictionnaire et préférence de mode actif                                    | Objets récupérés et utilisables ; l'historique et les enregistrements audio restent locaux                                                                                 |
| SYNC-02       | Modifier simultanément, perdre/rétablir le réseau et relancer                                                          | Conflits traités selon la règle documentée ; état stable après reprise ; pas de doublons persistants                                                                       |
| SYNC-03       | Approuver/révoquer un appareil ; récupérer avec un code de test ; essayer un autre compte                              | Contrôle d'accès et récupération fonctionnels ; absence de données déchiffrables par l'autre compte                                                                        |
| BYOK-01       | Configurer une clé de recette, transformer un texte puis simuler clé invalide, quota et timeout                        | Fournisseur choisi utilisé ; erreur utile ; pas de clé journalisée ni de basculement silencieux                                                                            |
| APPLE-INT-01  | Tester une transformation sur Mac compatible puis sur configuration indisponible                                       | Résultat local lorsque disponible ; indisponibilité expliquée sinon, sans appel Cloud implicite                                                                            |
| CLOUD-01      | Choisir explicitement Cloud, transcrire/transformer un contenu de test puis épuiser le quota de recette                | Route annoncée avant envoi, consommation correcte, quota expliqué et dictée locale toujours accessible                                                                     |
| CLOUD-02      | Interrompre une requête Cloud, réessayer, se déconnecter avant la réponse                                              | Pas de double résultat, ancienne réponse ignorée, aucune résurrection de session                                                                                           |
| PRIVACY-01    | Examiner les requêtes et diagnostics pendant les parcours Free/Pro                                                     | Pas de dictée locale envoyée ; routes distantes conformes à l'interface ; aucun secret ou contenu sensible dans les journaux                                               |
| A11Y-01       | Effectuer onboarding, compte, achat, restauration et réglages au clavier et avec VoiceOver                             | Actions identifiables, ordre de focus utilisable ; chaque éventuelle déclaration d'accessibilité appuyée par une preuve                                                    |
| UPDATE-01     | Passer d'un premier candidat TestFlight à son successeur                                                               | Mise à jour Apple, données/préférences conservées, aucune proposition de mise à jour directe                                                                               |

## Performance : protocole et seuils internes de lancement

Ces seuils sont des objectifs de recette, pas des performances mesurées ou une
promesse marketing. Machine de référence : M2, 16 Go, alimentation branchée.
Mesurer également la machine macOS 14 et expliquer tout écart matériel.

- Corpus fixe : 20 phrases françaises et 20 anglaises de 10 à 15 secondes,
  transcrites manuellement avant le test ; trois répétitions, sans donnée personnelle.
- Mesurer séparément premier chargement et modèle chaud. La latence de bout en bout
  part du relâchement du raccourci et finit à l'insertion ou à la disponibilité de
  la copie. Conserver médiane et 95e percentile par modèle et langue.
- Seuils modèle chaud sur M2 : p95 au plus 3 s pour Fast, 5 s pour Polyglot,
  12 s pour Precise sur ce corpus. Un dépassement déclenche diagnostic et décision
  documentée avant sortie, sans réécrire le seuil après coup pour masquer le résultat.
- En environnement calme, taux d'erreur de mots visé au plus 20 % pour Fast,
  15 % pour Polyglot et 12 % pour Precise. Calculer substitutions + suppressions
  - insertions, divisées par le nombre de mots de référence, après normalisation
    de la casse et de la ponctuation. Consigner séparément nombres et termes du
    dictionnaire ; ne pas les faire disparaître par normalisation.
- Sur 30 captures, pas de crash ni d'accumulation monotone de mémoire après retour
  au repos. Consigner pic mémoire, mémoire au repos et temps de chargement ; comparer
  à modèle identique, car la mémoire du modèle chargé peut rester allouée.
- Les résultats du benchmark moteur du 10 septembre ne remplacent aucun de ces
  tests : ils excluent microphone, VAD, permissions, interface et insertion.

## Décision de soumission

Chaque cas doit avoir un résultat et une preuve pour le build soumis. Un échec
d'installation, de dictée essentielle, de confidentialité, de paiement, de
restauration ou de récupération bloque la soumission. Toute fonction optionnelle
retirée doit aussi être retirée de l'interface et des textes commerciaux ; son
absence doit être vérifiée. Une nouvelle compilation invalide les preuves des
parcours modifiés et impose un passage complet du parcours critique.
