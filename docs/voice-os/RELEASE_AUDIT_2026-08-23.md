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

## Cloud isolé

| Environnement         | Commit                                     | Base                                     | État                                                                 |
| --------------------- | ------------------------------------------ | ---------------------------------------- | -------------------------------------------------------------------- |
| production temporaire | `0eccad0ad574e6315bab961ecd4157453cdf374a` | Neon production EU, schéma 0014          | `/health` et `/ready` verts derrière Deployment Protection           |
| staging temporaire    | `0eccad0ad574e6315bab961ecd4157453cdf374a` | branche Neon staging dédiée, schéma 0014 | validation publique health, DB, Apple, JWKS et frontières auth verte |

Le domaine `api.press-say.app` reste sur l'ancien backend. Le domaine
`api-staging.press-say.app` ne sera déplacé qu'après ajout et validation de
Google OAuth, puis smoke tests complets. Stripe et le traitement Cloud restent
désactivés.

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

## Baseline native disponible

`bun run voice-os:native-baseline` est vert sur un Mac Apple M2 avec 16 Go sous
macOS 26.3.1. Mail, Messages, Notes, Safari, Chrome, Slack et Terminal y sont
disponibles pour la matrice ; Notion, Word et Cursor n'y sont pas installés.

Un cycle silencieux sur la bêta signée a atteint successivement l'écoute,
`no_audio`, puis l'état `Ready` sans laisser la pipeline active. Cette
observation ne remplace pas les scénarios audio/insertion. Le Mac M1 8 Go et les
applications absentes restent requis avant validation commerciale.

## Gates encore ouverts

- matrice native sur les machines et applications de référence ;
- surveillance du budget Vercel et alerte avant une nouvelle suspension ;
- Google OAuth app/web, puis Google et Apple de bout en bout sur le build signé ;
- suppression de compte et E2EE sur deux Macs ;
- Stripe KYC/fiscalité/catalogue/Test Clocks et entitlements commerciaux ;
- StoreKit, conformité chiffrement, Sandbox et TestFlight ;
- revue crypto externe et validation fiscale externe.

La réussite de cette prerelease ne constitue donc pas une autorisation d'ouvrir
le checkout ni de soumettre le binaire Mac App Store.
