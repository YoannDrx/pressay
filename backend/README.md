# Pressay API

Backend minimal et portable devant Neon Postgres. L’application macOS ne se
connecte jamais directement à la base.

## Responsabilités

- comptes et appareils ;
- droits actifs `free`, `pro_byok` et `lifetime_byok` ; les codes Cloud/Teams
  restent réservés mais ne sont ni achetables ni annoncés ;
- compteurs d’usage idempotents ;
- synchronisation future de réglages chiffrés de bout en bout ;
- projection de facturation Stripe / App Store.

Hors périmètre de stockage : audio, dictées, texte sélectionné, contenu des
transformations et clés API BYOK.

## Démarrage local

1. Copier `.env.example` vers `.env` et renseigner une chaîne Neon poolée.
2. Exécuter la migration `db/migrations/0001_initial.sql` sur une branche Neon de développement.
3. Lancer `pnpm install`, puis `pnpm dev`.

Les routes métier sous `/v1/*` exigent un JWT OIDC signé. Les endpoints
`/v1/health`, `/v1/ready` et le webhook Stripe vérifié sont publics. Le choix
du fournisseur d’identité est découplé de Neon ; la configuration produit
attend Clerk, avec validation standard issuer/audience/JWKS dans cette API.

Le client macOS utilise Authorization Code + PKCE et les callbacks
`pressay://oauth/callback` (distribution directe) et
`pressay-companion://oauth/callback` (App Store). L’API accepte n’importe quel fournisseur OIDC dont
les tokens contiennent un `sub`, à condition que l’issuer, l’audience et le
JWKS soient configurés côté serveur.

## Facturation

Stripe est désactivé tant que les variables BYOK, Lifetime, webhook et URLs de
retour ne sont pas fournies. Les Price IDs Pro Cloud ne sont pas requis. Le
client n’envoie jamais de Price ID : il envoie
un plan et une périodicité, puis l’API sélectionne un Price ID allowlisté.

Endpoints :

- `POST /v1/accounts/bootstrap` : provisionne le compte et le droit Free ;
- `GET /v1/entitlements` : renvoie le contrat complet et sa signature Ed25519 ;
- `GET /v1/devices` / `DELETE /v1/devices/:id` : liste et révoque les Mac ;
- `POST /v1/founding/claim` : consomme une preuve locale 1.2.3 une seule fois ;
- `DELETE /v1/me` : supprime le compte produit et son client Stripe ;
- `POST /v1/billing/checkout` : crée une Checkout Session ;
- `POST /v1/billing/portal` : ouvre le Customer Portal ;
- `POST /v1/webhooks/stripe` : vérifie le corps brut et la signature Stripe.
- `GET /v1/internal/reconcile` : cron protégé qui réconcilie les abonnements et
  purge les anciennes fenêtres de rate limit.

Les événements sont dédupliqués avec l’ID Stripe et projetés selon leur date
fournisseur afin qu’un événement ancien ne puisse pas écraser un état récent.
Appliquer les migrations `0001` à `0004` dans l’ordre. La migration `0004`
autorise un essai lié au compte depuis le site lorsque aucun identifiant de Mac
n'est encore disponible ; les checkouts natifs continuent d'associer l'essai à
un appareil enregistré.

En production, `CLERK_SECRET_KEY` est requis pour que `DELETE /v1/me` supprime
aussi l’identité externe. `PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY` signe les
octets exacts exposés dans `snapshot.payload`, et `CRON_SECRET` protège la
réconciliation quotidienne déclarée dans `vercel.json`.

## Vérification

```sh
pnpm typecheck
pnpm test
TEST_DATABASE_URL='postgresql://…' pnpm test
```

## Environnements Neon

Projet actuel : `snowy-meadow-52007899`, région `aws-eu-central-1`.
La migration initiale est appliquée uniquement sur `development`
(`br-summer-flower-as8fzs30`). La branche `main` reste volontairement vide
jusqu'à la validation de l'authentification et du déploiement API.

- une branche `development` pour le travail quotidien ;
- une branche éphémère par pull request ;
- une branche `staging` avant migration de production ;
- la branche de production protégée, avec autoscaling, pooling et sauvegardes configurés.

Ne jamais exposer `DATABASE_URL` dans l’application macOS ni dans une variable
préfixée comme publique côté frontend.

## Déploiement

Le dossier est lié au projet Vercel `yoanndrxs-projects/pressay-api`. Le point
d’entrée `src/index.ts` exporte directement l’application Hono pour Vercel ;
`src/local.ts` conserve le serveur Node local. Aucun déploiement ne doit être
effectué avant d’avoir configuré `DATABASE_URL`, l’issuer OIDC, le JWKS et les
variables Stripe dans les environnements Preview et Production.
