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
release GitHub, après upload. La landing et le portfolio redirigent vers
`https://press-say.app/download/pressay`, qui résout désormais cette prerelease.

## Modèles

`models.press-say.app` est rétabli avec TLS et des routes de marque limitées aux
trois artefacts audités. `bun run voice-os:probe-models` valide la route primaire
et le fallback, avec HTTP 200 et tailles exactes :

| Modèle   |               Taille |
| -------- | -------------------: |
| Fast     |   739 508 576 octets |
| Polyglot |   269 751 136 octets |
| Precise  | 1 161 143 008 octets |

Les benchmarks M1 8 Go et la matrice téléchargement interrompu/repris restent
des preuves natives obligatoires avant de déclarer les modèles entièrement
validés.

## Cloud isolé

| Environnement         | Commit                                     | Base                                     | État                                                           |
| --------------------- | ------------------------------------------ | ---------------------------------------- | -------------------------------------------------------------- |
| production temporaire | `edd6628a0a6be13fde3388d8d5bcb2f3eb915282` | Neon production EU, schéma 0014          | `/health` et `/ready` verts, kill switches fermés              |
| staging temporaire    | `edd6628a0a6be13fde3388d8d5bcb2f3eb915282` | branche Neon staging dédiée, schéma 0014 | validateur pré-cutover vert pour Apple et les routes protégées |

Le domaine `api.press-say.app` reste sur l'ancien backend. Le domaine
`api-staging.press-say.app` ne sera déplacé qu'après ajout et validation de
Google OAuth, puis smoke tests complets. Stripe et le traitement Cloud restent
désactivés.

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

## Gates encore ouverts

- matrice native sur les machines et applications de référence ;
- Google OAuth app/web, puis Google et Apple de bout en bout sur le build signé ;
- suppression de compte et E2EE sur deux Macs ;
- Stripe KYC/fiscalité/catalogue/Test Clocks et entitlements commerciaux ;
- StoreKit, conformité chiffrement, Sandbox et TestFlight ;
- revue crypto externe et validation fiscale externe.

La réussite de cette prerelease ne constitue donc pas une autorisation d'ouvrir
le checkout ni de soumettre le binaire Mac App Store.
