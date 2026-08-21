# Architecture produit

## Positionnement

> Pressay est l'interface vocale privée et contrôlable du Mac.

Le produit doit donner un sentiment d'instrument système : immédiatement disponible, très clair sur ce qui écoute et où les données vont, puissant seulement quand l'utilisateur le demande.

## Benchmark orienté décisions

Les surfaces marketing et la documentation ne prouvent pas toujours le comportement de l'app. Le tableau distingue donc « visible » et « confirmé ».

| Produit        | Visible sur landing                                                                    | Confirmé par documentation/code public                                                    | Leçon pour Pressay                                                                                           |
| -------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Handy          | Gratuit, open source, privé, simple, offline.                                          | Whisper/Parakeet, push-to-talk, raccourci global et multiplateforme dans le dépôt public. | Ne pas se différencier seulement par « local et gratuit » ; Handy occupe déjà cette promesse.                |
| Superwhisper   | Esthétique sombre/cinématique, dictée dans toutes les apps, modes et modèles.          | Modes intégrés/personnalisés, activation par app, STT local/Cloud, LLM facultatif, BYOK.  | Garder la profondeur et la sensation premium, mais exposer mieux les routes et éviter sa palette dominante.  |
| Wispr Flow     | Narration éditoriale cinétique, vitesse, adaptation de style, vocabulaire et snippets. | Basic à quota, Pro avec mots illimités et Command Mode ; offre orientée Cloud.            | Reprendre la qualité de narration et le premier succès, pas la dépendance Cloud ni l'esthétique crème/verte. |
| Pressay actuel | Hero sombre bleu-violet et promesse de voix partout.                                   | Pipeline local, modèles, personnalisation, BYOK, Cloud/sync derrière gates.               | Déplacer l'identité vers Signal OS et ne mettre en landing que ce qui passe le feature ledger.               |

Sources consultées : [Handy](https://github.com/cjpais/Handy/blob/main/README.md), [Superwhisper](https://superwhisper.com/), [modes Superwhisper](https://superwhisper.com/docs/modes/modes), [modèles Superwhisper](https://superwhisper.com/models), [Wispr Flow](https://wisprflow.ai/), [plans Flow](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included), [Flow Business](https://wisprflow.ai/business).

### Matrice par axe

`Landing` signifie observé dans une page marketing ; `confirmé` signifie documenté ou visible dans un dépôt public. `Non confirmé` ne signifie pas que la fonction n'existe pas, seulement que l'investigation n'a pas obtenu de preuve suffisante.

| Axe                            | Handy                                                                         | Superwhisper                                                                   | Wispr Flow                                                                                  | Décision Pressay                                                                                      |
| ------------------------------ | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Proposition/audience           | Gratuit, open source et offline — confirmé.                                   | Power users Mac, créateurs et équipes voulant modèles/modes — landing + docs.  | Productivité grand public/équipes, rapidité et style par app — landing + offre Business.    | « Voice OS local » pour utilisateurs Mac qui veulent puissance et contrôle, pas seulement vitesse.    |
| Premier succès                 | Setup modèle/raccourci visible dans le code ; performance UX non mesurée.     | Démonstration simple voix→texte ; détail onboarding non confirmé publiquement. | Promesse d'usage immédiat très scénarisée ; détail des permissions non confirmé.            | Premier texte inséré avant compte/Pro, avec exercice réel et récupération des permissions.            |
| Push-to-talk/toggle/annulation | Push-to-talk et raccourci — confirmé ; matrice d'annulation non auditée ici.  | Usage global et modes confirmés ; gestes exacts à revérifier dans l'app.       | Barre Flow montrée ; Command Mode Pro confirmé, gestes précis non confirmés.                | Hold/release, toggle et cancel sont des contrats testés, pas des conventions d'UI.                    |
| Overlay/menu bar/sons/erreurs  | Overlay et tray hérités dans le code Pressay/Handy ; qualité native à tester. | Overlay compact premium visible ; états d'erreur non confirmés.                | Barre/waveform très présente en marketing ; erreurs non confirmées.                         | Une machine `VoiceSurfaceState` pour Voice Bar et tray, avec actions de reprise explicites.           |
| STT local/Cloud/BYOK           | Local Whisper/Parakeet confirmé.                                              | Local et Cloud confirmés ; BYOK Pro confirmé.                                  | Expérience orientée Cloud ; fonctionnement offline non confirmé et non promis.              | Local par défaut ; Apple/BYOK/Cloud visibles comme routes facultatives, jamais fallback silencieux.   |
| Modes/contexte/profils         | Fonctionnalités de base ; profondeur à auditer dans Handy si nécessaire.      | Modes built-in/custom, modèles vocaux/IA et activation par app confirmés.      | Style par app, dictionnaire appris, snippets et Command Mode visibles/confirmés selon docs. | Modes, profils et dictionnaire deviennent contrôlables/expliqués ; commandes déterministes en Free.   |
| Historique/fichiers/réunions   | Non confirmé dans les sources retenues.                                       | Réunions et transcription de fichiers présentes dans l'offre publique.         | Usage réunion/équipes mis en avant ; portée exacte à revérifier.                            | Historique local optionnel ; fichiers après V1 ; réunions/diarisation ne bloquent pas la refonte.     |
| Multi-appareils/sync           | Non confirmé.                                                                 | Non confirmé dans les sources retenues.                                        | Offre multi-plateforme/équipe visible ; détails de sync à revérifier.                       | Sync E2EE limitée aux préférences, jamais aux dictées, derrière revue externe.                        |
| Compte/paywall/quota           | Produit gratuit open source ; aucun paywall principal.                        | Free permanent ; Pro mensuel/annuel/lifetime affiché au moment de l'étude.     | Basic avec quota hebdomadaire ; Pro illimité/Command Mode et Business.                      | Free local sans compte ; abonnement mensuel/annuel ; pas de lifetime initial.                         |
| Niveau de contrôle             | Code ouvert et traitement local, contrôle élevé.                              | Choix riche de modèles/modes/providers.                                        | Forte automatisation de style, contrôle technique moins central dans la narration.          | Route, mode, cible, preview, risque et confirmation visibles au moment de l'action.                   |
| DA/motion                      | Fonctionnelle, héritée ; faible différenciation de marque.                    | Sombre, cinématique, premium, proche de la palette Pressay actuelle.           | Crème/vert, éditoriale, cinétique et très narrative.                                        | Graphite/minéral + signal spectral ; profondeur de Superwhisper, narration de Flow, grammaire propre. |
| Accessibilité/charge cognitive | Non évaluée publiquement.                                                     | Site visuellement sobre ; conformité app non confirmée.                        | Site animé et expressif ; reduced motion à auditer.                                         | Contraste, VoiceOver, reduced motion, RTL et textes longs sont des critères de sortie.                |

Avant toute utilisation commerciale de ce benchmark, rejouer les parcours dans les apps concurrentes avec des comptes de test et enregistrer version, OS, plan et date. Les landing pages ne permettent pas de conclure sur la fiabilité, la latence ou les erreurs.

## Architecture Free / Pro

Le paywall ne doit pas punir l'acte de base. Il monétise l'orchestration, la personnalisation et les services récurrents.

| Capability                           | Free sans compte                                          | Pro                          | Enterprise ultérieur         |
| ------------------------------------ | --------------------------------------------------------- | ---------------------------- | ---------------------------- |
| Dictée locale illimitée              | Oui                                                       | Oui                          | Oui                          |
| Fast / Polyglot de lancement         | Oui                                                       | Oui                          | Oui                          |
| Precise                              | À valider selon coût disque/performance ; recommandé Free | Oui                          | Oui                          |
| Raccourci, overlay, insertion        | Oui                                                       | Oui                          | Oui                          |
| Dictionnaire de base                 | Oui                                                       | Oui                          | Oui                          |
| Historique local optionnel           | Oui                                                       | Oui                          | Oui, politique administrable |
| Commandes déterministes              | Oui                                                       | Oui                          | Oui                          |
| Voice Bar : dictée et état           | Oui                                                       | Oui                          | Oui                          |
| Voice Bar : transformations avancées | Aperçu limité ou non                                      | Oui                          | Oui                          |
| Correction vocale                    | Non                                                       | Oui                          | Oui                          |
| Modes personnalisés                  | 1 à 3 pour découverte                                     | Illimités                    | Illimités + politique        |
| Profils par application              | 1 ou non                                                  | Illimités                    | Administrables               |
| Apple Intelligence                   | Non                                                       | Oui si appareil compatible   | Selon politique              |
| BYOK                                 | Non                                                       | Oui                          | Providers allowlistés        |
| Pressay Cloud                        | Non, sauf essai explicite après succès                    | Quota inclus                 | Contrat/quotas dédiés        |
| Sync E2EE                            | Non                                                       | Oui                          | Optionnelle, administrable   |
| Compte                               | Facultatif                                                | Requis pour entitlement/sync | SSO ultérieur                |
| Support                              | Communauté                                                | Prioritaire                  | SLA ultérieur                |

Décisions commerciales : mensuel et annuel au lancement ; aucun lifetime tant que Cloud/sync entraînent des coûts permanents. Le Free ne requiert jamais de compte. Les utilisateurs DMG paient via Stripe ; les utilisateurs MAS via StoreKit, sans différence fonctionnelle artificielle.

## Routes de traitement

| Route                | Usage                                 | Données sortantes                                      | Disponibilité                            | Fallback                                                 |
| -------------------- | ------------------------------------- | ------------------------------------------------------ | ---------------------------------------- | -------------------------------------------------------- |
| `local_stt`          | Audio → texte                         | Aucune                                                 | Tous les Macs supportés, modèle installé | Erreur locale explicite.                                 |
| `apple_intelligence` | Réécriture/intention locale           | Selon garanties Apple et API employée                  | Matériel/OS/langue compatibles           | Demander une autre route ; jamais silencieux.            |
| `byok`               | Transformation via fournisseur choisi | Texte sélectionné/transcription + instruction minimale | Pro, clé configurée                      | Réessayer ou repasser local sans transformation.         |
| `pressay_cloud`      | STT/LLM géré et quota                 | Payload explicitement décrit avant première requête    | Pro connecté, entitlement valide         | Revenir au local si possible après consentement visible. |

Le badge de route apparaît dans la Voice Bar, les réglages et l'historique local si celui-ci est activé. Il ne doit jamais être déduit seulement de la couleur.

## Capacités locales par palier

### Palier A — aucun nouveau LLM

Priorité produit immédiate :

- ponctuation, nouvelle ligne, nouvelle liste, annulation et mode suivant via parseur déterministe ;
- snippets avec expansion, aperçu et échappement ;
- mode/profil temporaire pendant la dictée ;
- dictionnaire explicable : règle appliquée visible et réversible ;
- transcription locale de fichiers audio/vidéo ;
- redaction locale de motifs sensibles avant une route externe ;
- diagnostic de qualité audio et recommandation modèle/micro.

Ces fonctions sont compatibles macOS 14 et ne doivent pas être vendues comme du raisonnement génératif.

### Palier B — Apple Intelligence

- réécriture de sélection ;
- résumé, ton, structure, traduction et extraction de tâches ;
- parsing d'intentions simples ;
- état `unavailable` explicite si modèle, région, langue ou OS incompatibles.

### Palier C — LLM local téléchargeable

Spike séparé, sans promesse commerciale : comparer MLX et llama.cpp au minimum ; mesurer taille, RAM résidente, cold start, tokens/s, énergie et coexistence avec STT. Cibles obligatoires : M1 8 Go, Mac médian, Mac récent. Commencer par un petit modèle spécialisé commandes/réécriture. Abandonner si le couple STT + LLM compromet la latence ou la stabilité de la cible minimale.

### Palier D — après V1

Actions macOS ouvertes, réunions/diarisation, mémoire de style, agents multi-étapes et adaptation de modèle. Leur surface de sécurité, stockage et consentement les exclut de la refonte initiale.

## Principes de contrôle

- L'utilisateur voit toujours la phase, la route et l'application cible.
- Les commandes de texte sont réversibles ; l'original reste récupérable pendant la session.
- Une action système possède un niveau de risque, un aperçu et, si nécessaire, une confirmation.
- Aucune transcription, clé ou prompt dans la télémétrie technique.
- Une panne de compte, Cloud ou paiement n'interrompt pas la dictée locale Free.
