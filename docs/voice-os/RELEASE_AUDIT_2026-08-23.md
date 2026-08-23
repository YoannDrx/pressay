# Audit de release — 23 août 2026

Ce registre contient uniquement des preuves techniques non sensibles. Il ne
contient ni contenu dicté, ni secret, ni donnée d'identité ou de paiement.

## Train direct `v2.0.0-beta.3`

| Preuve              | Résultat                                                           |
| ------------------- | ------------------------------------------------------------------ |
| Commit publié       | `478d145d8df1a41b5bdd8f08bfb53061a7496248`                         |
| Workflow GitHub     | `32600510835`, réussi                                              |
| Release             | prerelease publiée, non commerciale                                |
| Asset canonique     | `Pressay.dmg`, 20 439 772 octets                                   |
| SHA-256             | `89ae5d40df921a796f238e1c750c6f204beca49f0d5eea1dbf2798e5827bf9e3` |
| Checksum téléchargé | `shasum -a 256 -c` réussi                                          |
| DMG                 | ticket staplé et accepté par Gatekeeper (`Notarized Developer ID`) |
| App interne         | `codesign --deep --strict`, Gatekeeper et stapler réussis          |
| Identité            | `Developer ID Application: Yoann ANDRIEUX (G9WFV7HNV6)`            |

Les contrôles ci-dessus ont été rejoués sur les assets retéléchargés depuis la
release GitHub, après upload. La redirection de la landing vers cette prerelease
a été validée avant l'incident Vercel documenté plus bas.

Le dernier probe public confirme que `/en/download` répond `200` et référence
exactement
`v2.0.0-beta.3/Pressay.dmg`. La route support `/support/secure-input` répond
également `200`. La route générique `/download` n'est pas un contrat publié et
répond `404` ; les CTA localisés restent la source canonique.

La PR desktop #76 automatise désormais ce dernier contrôle : la release reste
en brouillon, le runner retélécharge `Pressay.dmg` et son checksum via l'API des
assets GitHub, puis vérifie checksum, Gatekeeper, signature et stapling du DMG
et de l'app montée avant de publier le brouillon. Le workflow est validé
statiquement ; sa première exécution sur un nouveau tag reste une gate de
release.

Cette PR refuse également un déclenchement manuel hors du `main` distant et un
tag dont le commit n'appartient pas à `origin/main`, afin qu'aucun artefact ne
puisse être publié depuis une branche de travail non mergée.

## Modèles

`models.press-say.app` a été rétabli avec TLS et des routes de marque limitées
aux trois artefacts audités. Le 23 août, la commande
`bun run voice-os:probe-models` valide la route primaire et le fallback, avec
HTTP 200 et tailles exactes. Un téléchargement complet supplémentaire depuis
la route primaire confirme aussi chaque SHA-256 du catalogue signé :

| Modèle   |               Taille | SHA-256 complet |
| -------- | -------------------: | --------------- |
| Fast     |   739 508 576 octets | conforme        |
| Polyglot |   269 751 136 octets | conforme        |
| Precise  | 1 161 143 008 octets | conforme        |

Les benchmarks M1 8 Go et la matrice native téléchargement
interrompu/repris restent obligatoires avant la release commerciale.

L'URL de développement historique `models.press-say.app/silero_vad_v4.onnx`,
qui retournait encore 404, est restaurée par la PR web #18. Elle rejoint une
route versionnée `v4` qui cible l'artefact exact de `v2.0.0-beta.3` et répond
avec une redirection 308 et un cache public immutable d'un an. Le preview
Vercel confirme ces en-têtes ; la route de marque ne sera publique qu'après
merge et promotion de la PR web.

Un benchmark headless reproductible a aussi été exécuté avec le binaire signé
`v2.0.0-beta.3` sur un Apple M2 16 Go/macOS 26.3.1. La fixture française est
une voix macOS synthétique de 8,647 secondes et ne contient aucune donnée
utilisateur. Chaque modèle a effectué un premier passage puis dix-neuf passages
warm, avec Metal (`MTL0`) :

| Modèle   |     Cold | Médiane warm | p95 warm | Meilleur RTF |          Mémoire max |
| -------- | -------: | -----------: | -------: | -----------: | -------------------: |
| Fast     |   265 ms |       199 ms |   344 ms |       44,57× | 1 060 749 312 octets |
| Polyglot |   770 ms |       458 ms |   540 ms |       18,96× |   540 213 248 octets |
| Precise  | 2 984 ms |     2 643 ms | 2 892 ms |        3,56× | 1 226 194 944 octets |

Ces mesures prouvent les trois chemins modèle→texte et leur ordre de grandeur
sur cette machine. Elles ne prouvent ni la précision sur corpus humain, ni la
cohabitation sur M1 8 Go, ni les performances d’une session interactive.

## Redaction locale

Un scan par motifs du journal release local (123 334 octets) ne trouve aucune
occurrence de préfixe de clé OpenAI, bearer token, en-tête d’autorisation,
`transcription text`, `prompt`, `clipboard` ou `api key`. Le store JSON ne
contient aucun préfixe de secret ; il conserve uniquement le booléen
`post_process_api_keys_configured.openai` et les métadonnées d’usage BYOK
prévues (fournisseur, modèle, tokens, coût estimé et version tarifaire).

Ce scan est une preuve négative ciblée, pas une preuve d’absence universelle.
Les tests automatisés de redaction et la revue externe restent obligatoires.

## Cloud isolé

| Environnement         | Commit                                     | Base                                     | État                                                                 |
| --------------------- | ------------------------------------------ | ---------------------------------------- | -------------------------------------------------------------------- |
| production temporaire | `0eccad0ad574e6315bab961ecd4157453cdf374a` | Neon production EU, schéma 0014          | `/health` et `/ready` verts derrière Deployment Protection           |
| staging temporaire    | `0eccad0ad574e6315bab961ecd4157453cdf374a` | branche Neon staging dédiée, schéma 0014 | validation publique health, DB, Apple, JWKS et frontières auth verte |

Le domaine `api.press-say.app` reste sur l'ancien backend. Le domaine
`api-staging.press-say.app` ne sera déplacé qu'après ajout et validation de
Google OAuth, puis smoke tests complets. Stripe et le traitement Cloud restent
désactivés.

Le réglage Vercel du projet `pressay-cloud-production`, qui surchargeait encore
le manifeste avec Node 24, a été réaligné sur Node 22. Le preview protégé
`dpl_8yGdMqv9YaG9YKnbqnut6uHrumhQ` est `READY` et `/health` expose le commit
Cloud `7c027947622485cf5a8e0289b6999b163135ea92`. Il reste volontairement sans
base de production : `/ready` renvoie 503 au lieu de connecter une preview à
Neon production.

Sur la tête de PR Cloud `161cad1892fe6ccf1884a31c1ec50cce2ddfe8e3`, `bun run
verify` passe 24 fichiers et 104 tests, Secretlint ne trouve aucun secret et
l’audit runtime ne trouve aucun avis high/critical. Le validateur staging passe
huit contrôles : health, readiness DB, configuration desktop auth, Apple,
issuer OAuth 2.1 PKCE, clé publique d’entitlement et refus 401 des endpoints
entitlement/sync sans session. Le nouveau contrat refuse aussi une clé Stripe
test en production, une clé live en staging/développement, un projet Vercel
inattendu et une transaction App Store Sandbox en production (ou Production en
staging). Ces preuves sont portées par la PR Cloud #27 et ne sont pas encore
mergées. Cette tête ajoute également des événements strictement agrégés pour les
webhooks Stripe/Apple et les suppressions, un logger refusant les noms de champs
sensibles composés, ainsi qu'un runbook de rollback et d'incident. Le `db:check`
local n’est pas présenté comme une preuve : il reste
volontairement impossible sans `DATABASE_URL` injectée dans un environnement
autorisé.

Le Checkout utilise l'API Stripe `2026-07-29.dahlia`, omet explicitement
`payment_method_types` et porte désormais un `integration_identifier` stable
avec le suffixe aléatoire de huit lettres demandé par le contrat Stripe actuel.
La même tête aligne aussi l'état de facturation affiché sur la source
d'entitlement autoritative : un ancien abonnement Stripe ne peut plus masquer
un abonnement App Store qui accorde réellement Pro, ou inversement.

## Frontière commerciale web

La tête de PR web `2ec9c9b2a1feb56261bd82ab088da51dc8239ae0` maintient le
checkout fermé par défaut et exige simultanément :

- le manifeste `PRESSAY_WEB_ENVIRONMENT=production` ;
- un déploiement Vercel de type production ;
- le projet Vercel canonique `pressay-web` ;
- l'origine publique `https://press-say.app` ;
- l'API `https://api.press-say.app` ;
- le kill switch commercial et toutes les capacités de release requises.

Les matrices Playwright fermée et commerciale passent chacune 40 scénarios,
avec deux scénarios distants volontairement ignorés. Les tests négatifs refusent
une preview, un mauvais projet, l'origine staging et l'API staging. Le preview
`dpl_8AYd1QvwpAW9MGVoJtLzDx1J1VoV` est `READY` sous Node 22 ; via l'accès
Vercel protégé, sa landing n'expose que la route locale et son endpoint checkout
retourne `503 commercial_launch_not_enabled`. Le réglage projet, auparavant
forcé sur Node 24 malgré le manifeste, a été réaligné sur Node 22. Ces preuves
sont portées par la PR web #18 et ne sont pas encore mergées.

Cette même tête restaure le contrat public du VAD : l'ancienne URL
`/silero_vad_v4.onnx` redirige vers une route versionnée, puis vers l'artefact
immuable du tag `v2.0.0-beta.3`. Le fichier source mesure 1 807 522 octets et
porte le SHA-256
`a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28` ; la
route versionnée expose un cache immutable d'un an. La production continue de
répondre `404` sur l'ancienne URL tant que la PR #18 n'est pas mergée puis
promue.

Les appels checkout et parrainage créent désormais le compte par
`accounts/web-bootstrap`, qui ne consomme aucun des trois slots Mac. Un fallback
vers l'ancien endpoint n'est permis que lorsque le Cloud répond explicitement 404. Les erreurs de validation et les erreurs serveur ne déclenchent aucun
fallback silencieux. Deux contrats Playwright couvrent le chemin moderne et la
compatibilité de cutover.

## Incident Vercel résolu

À 22:22 UTC, Spend Management a automatiquement suspendu les projets de
l'équipe après atteinte du budget mensuel. L'activité Vercel identifie
explicitement l'événement `project-paused`. Les projets Pressay ont depuis été
réactivés et toutes les surfaces concernées ont été rejouées : landing,
`/support/secure-input`, métadonnées OAuth, portfolio, CDN primaire et fallback,
Cloud staging et Cloud production protégé. La landing production correspond au
déploiement `dpl_2ToTEREweHfySB55EbuTkdgMiBGq` et ses 22 scénarios distants
applicables passent ; les scénarios commerce/identité privée restent fermés.

Le budget Vercel conserve une marge limitée et doit rester surveillé pour éviter
une nouvelle suspension. Ce risque opérationnel n'autorise pas le cutover Cloud
production : `api.press-say.app` sert toujours l'ancien backend jusqu'à la
validation native du compte et du rollback.

## Spike Mac App Store

Le workflow `32602095878` a compilé avec succès le bundle Apple Silicon
`fr.yodev.pressay` avec la feature `mas`. Les contrôles CI confirment App
Sandbox, audio input et l'absence des dépendances/API privées interdites dans le
graphe Store.

L'artefact retéléchargé a ensuite été signé localement avec le certificat
`3rd Party Mac Developer Application` et le provisioning profile
`Pressay Mac App Store Distribution`. `codesign --verify --deep --strict`
réussit et les entitlements effectifs couvrent :

- App Sandbox et microphone ;
- réseau sortant et fichiers explicitement choisis ;
- Keychain limité à l'équipe ;
- Sign in with Apple ;
- identifiant d'application `G9WFV7HNV6.fr.yodev.pressay`.

Cette preuve valide le chemin de compilation et de signature de l'application,
pas encore l'upload App Store. Le certificat Mac Installer Distribution, les
métadonnées d'abonnement, le Sandbox StoreKit, TestFlight et la déclaration de
chiffrement restent des gates.

Le poste local possède le certificat application MAS et le provisioning profile
Pressay, mais pas encore le certificat Mac Installer Distribution. Par ailleurs,
l'environnement GitHub protégé `app-store-production` ne contient encore aucun
secret ni variable : aucun export de clé privée ou upload App Store ne peut être
lancé tant que le matériel manquant n'a pas été créé puis injecté explicitement.

La PR desktop #75 aligne en outre le bridge sur l'API StoreKit AppKit actuelle :
la feuille de confirmation est attachée à la fenêtre Pressay sur macOS 15.2+,
avec l'API compatible conservée sur la cible minimale macOS 14. Le catalogue et
le graphe `mas` compilent ; aucun achat Sandbox réel n'est présenté comme validé.

## Baseline native disponible

`bun run voice-os:native-baseline` est vert sur un Mac Apple M2 avec 16 Go sous
macOS 26.3.1. Mail, Messages, Notes, Safari, Chrome, Slack et Terminal y sont
disponibles pour la matrice ; Notion, Word et Cursor n'y sont pas installés.

Un cycle silencieux sur la bêta signée a atteint successivement l'écoute,
`no_audio`, puis l'état `Ready` sans laisser la pipeline active. Cette
observation ne remplace pas les scénarios audio/insertion. Le Mac M1 8 Go et les
applications absentes restent requis avant validation commerciale.

## Stripe direct — audit live en lecture seule

Le compte Stripe dédié `Pressay` est activé pour les transactions live et
Stripe indique que la vérification du compte est terminée. Aucun paiement ni
abonnement live n'a encore été créé.

Le panneau « État du compte » ne contient aucune tâche active. Le nom du compte,
l'adresse d'entreprise, le site `press-say.app`, le téléphone de support et le
libellé bancaire `PRESSAY` sont renseignés. La vérification téléphonique du
Dashboard reste proposée séparément et nécessite une validation SMS du
propriétaire.

Le catalogue live contient un seul produit actif, `Pressay Pro`, avec deux
tarifs actifs conformes à l'offre verrouillée : 7,99 € par mois et 69 € par an.
Il n'expose aucun essai. Un tarif de création accidentelle à 799 € par mois est
présent uniquement comme tarif archivé, sans abonnement associé.

Le portail client dispose déjà des fonctions nécessaires : historique de
facturation, mise à jour des coordonnées et moyens de paiement, annulation en
fin de période avec motif demandé, ainsi qu'un retour vers le compte Pressay.
Les liens Conditions et Confidentialité pointent vers la landing.

Les éléments suivants restent des gates et empêchent l'ouverture du checkout :

- aucune destination webhook live n'est configurée ;
- aucune clé API restreinte n'existe encore ;
- le catalogue Stripe test ne contient encore ni produit ni tarif ;
- aucune matrice Test Clock ne peut donc être considérée comme exécutée ;
- Stripe Tax n'est pas configuré et ne doit pas être activé avant validation
  fiscale et confirmation des inscriptions applicables ;
- le nom commercial public affiche encore le nom légal au lieu de `YoDev` et
  doit être corrigé sans modifier l'identité légale vérifiée ;
- l'adresse et les coordonnées de support sont présentes mais doivent être
  confirmées avant le premier paiement.

Cette preuve provient uniquement des surfaces Dashboard en lecture seule. Elle
ne contient ni clé, ni donnée bancaire, ni donnée de client.

Le connecteur Stripe disponible dans Codex ne voit actuellement que le compte
RoutineKids, pas le compte Pressay. Aucune mutation Stripe ne sera donc lancée
par ce canal avant reconnexion explicite au bon compte ; le Dashboard Pressay
reste une voie distincte qui nécessite une confirmation ciblée avant création
de clés, webhooks ou objets test.

## Gates encore ouverts

- matrice native sur les machines et applications de référence ;
- surveillance du budget Vercel et alerte avant une nouvelle suspension ;
- Google OAuth app/web, puis Google et Apple de bout en bout sur le build signé ;
- suppression de compte et E2EE sur deux Macs ;
- Stripe fiscalité, clé restreinte, webhooks, catalogue test, Test Clocks et
  entitlements commerciaux ;
- StoreKit, conformité chiffrement, Sandbox et TestFlight ;
- revue crypto externe et validation fiscale externe.

La réussite de cette prerelease ne constitue donc pas une autorisation d'ouvrir
le checkout ni de soumettre le binaire Mac App Store.
