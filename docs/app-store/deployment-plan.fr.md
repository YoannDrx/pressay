# Plan de déploiement Pressay sur le Mac App Store

Établi le 15 septembre 2026. Cible : Pressay 2.0.0, macOS 14 et versions suivantes,
Apple Silicon. Ce document pilote les travaux restants ; les cases ouvertes ne
constituent pas des validations acquises.

Exécution commencée le 15 septembre avec l'accord de Yoann. La
[procédure de publication](release-runbook.fr.md) et la
[matrice native](native-release-matrix.fr.md) détaillent les commandes et recettes.
App Store Connect a été consulté en session connectée : le chiffrement attend
toujours sa validation et le formulaire DSA exige le justificatif demandé.
L'[état d'exécution](../PRE_SALE_EXECUTION_2026-09-15.md) actualise les observations
historiques du tableau ci-dessous, notamment le build 12001 retrouvé dans la
version 1.2.0 et la PR désormais prête pour revue humaine.

## Résultat attendu

Un utilisateur peut télécharger Pressay depuis le Mac App Store, effectuer sa
première dictée, utiliser Free hors ligne après installation du modèle, acheter
Pro, restaurer ses achats et obtenir de l'aide. Les fonctions annoncées sont
testées sur le binaire distribué par Apple. Le site reflète la disponibilité et
les conditions commerciales réelles.

On termine et valide les fonctions existantes avant d'élargir le périmètre.
Une fonction essentielle défaillante bloque la sortie. Une fonction facultative
non validée doit être corrigée ou retirée de la version et des promesses associées.

## État de départ et preuves

| Élément                      | État connu                                                                                                                                                                                        | Conséquence                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Application native           | [PR 94](https://github.com/YoannDrx/pressay/pull/94), ouverte et en brouillon ; les 12 contrôles de la révision `1fa94587cb8abb5fdc79d9591602143227f2cd15` sont réussis, vérifiés le 15 septembre | Revue humaine puis intégration à effectuer                              |
| API                          | Correctifs de la PR 40 déployés le 10 septembre, commit `bc31eb1814c47d0887e7cb0d2508f65b40ccada7`                                                                                                | Refaire les contrôles de disponibilité au moment de la recette finale   |
| Site                         | Correctifs de la PR 23 déployés le 10 septembre, commit `c5fdaa62cb0a0a9a29ce38a3699ef6d23650df53`                                                                                                | Préparer l'ouverture commerciale et vérifier la version publique finale |
| Archive 2.0.4                | Construite et signée ; téléversement refusé le 10 septembre pour code de conformité du chiffrement manquant                                                                                       | Nouvelle archive nécessaire après obtention du code Apple               |
| Ancien build 2.0.3           | Traité par Apple puis détaché du brouillon ; remplacé par les corrections suivantes                                                                                                               | Ne pas le sélectionner pour publication                                 |
| Dossier Apple de chiffrement | En vérification, sans code délivré lors du contrôle du 10 septembre                                                                                                                               | Recontrôler son état avant toute action dépendante                      |
| Adresse DSA                  | Correction préparée mais non soumise : justificatif requis au dernier contrôle du 10 septembre                                                                                                    | Finaliser avec un document réel accepté par Apple                       |
| TestFlight et App Review     | Aucun parcours natif TestFlight validé, aucune soumission App Review effectuée                                                                                                                    | Recette Apple complète encore à réaliser                                |

Les états Apple ci-dessus sont historiques, et ne sont pas présentés comme
revérifiés le 15 septembre. Détails : [rapport des corrections](../PRE_SALE_REMEDIATION_2026-09-10.md),
[notes de review](review-notes.md) et [recette TestFlight](testflight.fr-FR.md).
Les tests automatisés réussis ne prouvent pas à eux seuls les permissions macOS,
la dictée dans d'autres applications ou les achats distribués par Apple.

## Ordre d'exécution

Les lots A, B et C peuvent progresser indépendamment. D dépend de la revue du code
et du code de conformité Apple. E dépend du traitement du nouveau build par Apple.
F exige les validations A à E. G dépend de l'acceptation par Apple.

### A — Fermer les dossiers administratifs et commerciaux

- [x] Relever l'état actuel du chiffrement, du DSA, des contrats, des données
      bancaires et fiscales, sans relancer les démarches déjà validées.
- [ ] Obtenir la décision Apple sur le chiffrement et son code de conformité.
      Utiliser la [relance préparée](export-compliance-follow-up.fr.md) après
      autorisation d'envoi. Si Apple demande un complément ANSSI, fournir le
      document effectivement requis ; un accusé de réception n'est pas assimilé
      à une attestation finale.
- [ ] Finaliser l'adresse DSA avec un justificatif authentique : **7 allée des
      Jonquilles, 95130 Franconville, France**. Vérifier l'adresse après soumission
      et après validation. Le 11 rue de la Chine est l'ancienne adresse ; ne pas
      poursuivre le changement vers Paris du dossier `20000144124147`.
- [ ] Conserver le contact validé `yoann.andrieux@gmail.com` et `+33663434665`.
      Vérifier les liens de contact et le filtre Gmail `Apps/Pressay`. Ne remplacer
      ce contact par `hello@pressay.fr` qu'après configuration et preuve de réception.
- [ ] Vérifier la cohérence de l'identité de l'éditeur, des conditions de vente,
      des informations de confidentialité, des abonnements et des remboursements
      entre app, site et Store. Résoudre la question du dispositif de médiation
      applicable avant l'ouverture commerciale ; ne pas déclarer une affiliation
      non souscrite. Tout contrat payant nécessite une décision de Yoann.

**Critère de sortie :** code de conformité disponible, correction DSA acceptée ou
état Apple explicitement documenté, absence de blocage contractuel de distribution
et informations commerciales vérifiées. Distinguer un blocage Apple confirmé d'une
obligation commerciale à clarifier ; ne pas les confondre dans le suivi.

### B — Stabiliser la version et préparer une construction reproductible

- [ ] Faire relire et approuver la PR 94 par un contributeur humain, puis intégrer
      les corrections. Cette étape est imposée par [AGENTS.md](../../AGENTS.md).
      Si le code change, relancer les contrôles concernés et ceux requis pour fusionner.
- [x] Vérifier la configuration de l'environnement GitHub `app-store-production`,
      ses protections et la présence du matériel de signature sans exposer les secrets.
      L'absence de variables au niveau du dépôt ne permet pas de conclure sur celles
      de l'environnement protégé.
- [x] Vérifier et, si nécessaire, corriger le numéro de build du
      [workflow de publication](../../.github/workflows/app-store-release.yml).
      Le compteur GitHub a été remplacé par un numéro explicite, comparé numériquement
      au plus grand build relevé dans Apple ; les archives jusqu'à `2.0.4` sont réservées.
      Tests ajoutés pour les premiers lancements CI, les relances, les comparaisons
      et les formats invalides. La lecture de l'état Apple reste une étape obligatoire.
- [ ] Choisir le chemin de téléversement opérationnel : workflow protégé si la clé
      App Store Connect est configurée, sinon Xcode connecté avec la même traçabilité.
      La clé API n'est pas une condition nécessaire au chemin Xcode existant.
- [ ] Préparer les preuves de version : commit, version publique, numéro de build,
      empreinte du paquet, signature, profil et correspondance des symboles dSYM.

**Critère de sortie :** source approuvée sur `main`, contrôles requis réussis et
chemin de construction/signature/téléversement documenté, avec un numéro compatible
avec l'historique Apple.

### C — Compléter les recettes et le dossier de présentation

- [x] Transformer la [recette TestFlight](testflight.fr-FR.md) en registre de cas
      avec résultat attendu, machine, macOS, build, preuve et anomalie éventuelle.
- [x] Préparer les cas natifs : première installation, permissions accordées/refusées
      puis rétablies, raccourcis, annulation, microphone débranché, veille/reprise,
      téléchargements interrompus, disque insuffisant et dictée sans réseau.
- [ ] Préparer la matrice macOS 14 et une version récente, sur Apple Silicon ;
      identifier l'accès à un second Mac pour la synchronisation. Un environnement
      indisponible reste une couverture manquante, sans résultat inventé.
- [x] Préparer un corpus non confidentiel français et anglais, court et long,
      pour mesurer précision, latence après fin de parole, mémoire et stabilité.
      Fixer les seuils d'acceptation par modèle et machine avant la recette ; les
      mesures synthétiques du build 2.0.3 restent une référence partielle.
      Les 40 phrases de référence et les seuils sont dans la matrice native ;
      concaténer les phrases pour la capture longue. Les enregistrements naturels
      et les mesures sur le candidat Apple restent à réaliser.
- [ ] Relire les métadonnées FR/EN, mots-clés, catégories, territoires, prix,
      captures, URLs de support/confidentialité et déclarations de collecte.
      Confronter les déclarations aux flux réels Free, Pro, synchronisation et
      fonctions utilisant un service distant. Revérifier les exigences Apple
      actuelles dans sa documentation officielle lors de cette préparation.
- [ ] Préparer les notes App Review et le scénario vidéo : première dictée,
      permissions, connexion Apple, achat, restauration et solution de copie.
      Produire les captures et la vidéo finales depuis le candidat réellement testé.

**Critère de sortie :** matrice exécutable, moyens de test identifiés, seuils écrits
et dossier prêt à recevoir les preuves natives. Cette préparation peut avancer
pendant l'examen du chiffrement.

### D — Produire et distribuer le nouveau candidat Apple

- [ ] Construire depuis le commit approuvé avec `storekit-purchases`, configuration
      App Store, API de production et le code de conformité réellement délivré.
      Conserver `ITSAppUsesNonExemptEncryption=true`.
- [ ] Vérifier App Sandbox, microphone, signature, profil, identifiant
      `fr.yodev.pressay`, numéro de build et symboles de crash. Contrôler l'absence
      des chemins de paiement direct, de mise à jour directe et des API privées.
- [ ] Valider et envoyer le paquet ; conserver le résultat et l'identifiant Apple.
      Attendre son traitement effectif et résoudre toute erreur de validation.
- [ ] Rendre ce build accessible aux testeurs autorisés dans TestFlight, puis
      vérifier son installation. Documenter toute étape Apple supplémentaire requise.

**Critère de sortie :** nouveau candidat traité par Apple et installé depuis
TestFlight. Une archive locale signée ou un envoi démarré ne suffisent pas.

### E — Tester les parcours réels et corriger jusqu'à validation

| Domaine                   | Validation nécessaire sur le candidat Apple                                                                                                                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Free et dictée            | Première dictée sans compte ; saisie dans Notes, navigateur et éditeur ; refus des champs sécurisés ; copie de secours ; hors ligne ; reprise après erreurs et changement de périphérique                                |
| Modèles et historique     | Téléchargement/reprise/intégrité, sélection et chargement ; recherche rapide, pagination, copie, suppression et persistance après redémarrage                                                                            |
| Compte et confidentialité | Connexion Apple, déconnexion, relancement sans ancienne session ; suppression du compte et vérification des données concernées ; secrets absents des journaux ; envoi distant conforme à l'interface et aux déclarations |
| Achats                    | Produits mensuel/annuel, prix Apple, achat Sandbox, annulation, interruption/reprise, restauration même après échec de chargement du catalogue, renouvellement, expiration et remboursement                              |
| Droits Pro                | Droits cohérents dans l'app et l'API ; notifications Apple reçues ; événements dupliqués sans double effet ; séparation Sandbox/Production et absence d'attribution au mauvais compte                                    |
| Synchronisation           | Deux Mac avec le même compte ; récupération chiffrée ; perte/rétablissement réseau et opérations concurrentes ; autre compte sans accès aux données                                                                      |
| Robustesse et performance | Cas du lot C sur les versions macOS prévues ; mesures de bout en bout comparées aux seuils fixés ; absence de crash et de croissance mémoire anormale lors des sessions répétées                                         |

- [ ] Consigner chaque défaut reproductible, corriger à sa source et ajouter une
      régression automatisée lorsqu'elle vérifie un comportement pertinent.
- [ ] Après modification du binaire, produire un nouveau build et reprendre les
      parcours affectés ainsi que le parcours critique complet sur ce build.
- [ ] Compléter les preuves et retirer les placeholders des notes App Review.

**Critère de sortie :** aucun défaut bloquant connu sur installation, dictée,
confidentialité, paiement, restauration ou récupération des données ; tous les
parcours annoncés ont une preuve sur le candidat final. Une simulation StoreKit
ou des tests API seuls ne remplacent pas un achat Sandbox natif.

### F — Soumettre l'application et les abonnements à App Review

- [ ] Recontrôler les états administratifs et la disponibilité de l'API, des modèles,
      de la connexion Apple et des pages publiques.
- [ ] Sélectionner le candidat validé, finaliser les abonnements à joindre à la
      soumission, les métadonnées, les déclarations et les pièces de review.
- [ ] Vérifier que le reviewer peut utiliser Free sans compte et tester Pro avec
      son compte Apple, selon le parcours réellement validé, sans droit caché.
- [ ] Soumettre ; conserver date, version, build et état Apple. Traiter les retours
      par une correction testée ou une clarification appuyée sur des preuves.
      Obtenir l'autorisation d'envoi si une réponse à Apple doit être transmise.
- [ ] Préparer la sortie de façon à coordonner disponibilité Store et site après
      l'acceptation. Ne pas promettre un délai de validation Apple.

**Critère de sortie :** application et produits nécessaires acceptés par Apple,
avec les conditions de mise en vente satisfaites.

### G — Ouvrir la distribution et vérifier l'expérience publique

- [ ] Déclencher la publication autorisée par Yoann et constater la disponibilité
      réelle sur les territoires choisis.
- [ ] Vérifier une installation depuis la fiche publique, le parcours Free et
      l'affichage des offres réelles. Un achat réel de contrôle nécessite un accord
      explicite sur la dépense ; ne pas assimiler Sandbox à une transaction réelle.
- [ ] Mettre à jour la landing page avec le lien Store vérifié, les prix et les
      fonctions disponibles ; retirer les annonces d'indisponibilité devenues fausses.
      Contrôler mobile/desktop, navigation, support et pages légales en production.
- [ ] Vérifier les diagnostics disponibles, les erreurs de connexion/paiement et
      la réception des demandes de support, sans collecter le contenu des dictées.
- [ ] Documenter la conduite à tenir en cas d'incident : responsable, diagnostic,
      interruption d'une ouverture commerciale si nécessaire et correctif. Un
      ancien binaire ne remplace pas automatiquement les installations Store.
      Prévoir des contrôles à J+1 et J+7 ; aucune automatisation n'est créée par ce plan.

**Critère de sortie :** téléchargement public constaté, parcours commercial vérifié
au niveau réellement testé, site aligné et moyens de support opérationnels. Le
rapport final doit distinguer les validations réalisées des limites restantes.

## Interventions de Yoann à regrouper

| Intervention                                                                         | Pourquoi elle est nécessaire                                                              | Travail préparé ou réalisable sans attendre                                         |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Justificatif actuel de Franconville, via un fichier accessible                       | Le dernier formulaire DSA exigeait une pièce avant soumission                             | Adresse et coordonnées confirmées ; reprise du dossier et vérifications préparables |
| Autorisation de transmettre la relance Apple si elle reste utile                     | L'envoi d'un message à un tiers nécessite une autorisation explicite                      | Texte déjà rédigé, avec app, dossier et erreur de téléversement                     |
| Revue humaine et approbation de la PR 94                                             | Règle explicite du dépôt avant fusion                                                     | Diff disponible et 12 contrôles réussis                                             |
| Confirmation d'un contrat de médiation existant, ou choix d'un contrat si nécessaire | Impossible de publier une affiliation ni de souscrire un contrat payant sans fondement    | Vérification des mentions et préparation des modifications                          |
| Accès ponctuel aux machines, sessions ou validations Apple indisponibles             | Certaines recettes exigent un vrai environnement et parfois une confirmation du titulaire | Cas de test, scripts et procédure préparables                                       |

Les corrections de code, tests disponibles, préparation des builds et documents
restent exécutables de façon autonome. Les demandes à Yoann doivent porter sur un
élément concret au moment où il devient nécessaire, sans redemander les choix déjà
confirmés concernant l'adresse, les contacts ou l'objectif de publication.

## Suivi pendant l'exécution

Pour chaque lot, consigner : état (`à faire`, `en cours`, `bloqué`, `validé`),
prochaine action, dépendance éventuelle et lien vers la preuve. Pour chaque recette,
enregistrer le commit, le build, la machine, macOS, la date et le résultat observé.
Une correction rend obsolètes les preuves des comportements qu'elle affecte.

La prochaine séquence est : actualiser les dossiers Apple, préparer la revue de la
PR 94, vérifier le numéro de build du workflow et compléter la matrice de recette.
Le chemin critique externe reste l'obtention du code de conformité, puis le
traitement du build et la décision App Review. Aucun délai externe ni absence
absolue de bugs ne peut être garanti par ce plan.
