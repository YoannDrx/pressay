# Distribution macOS

La configuration Release active le **Hardened Runtime**. Le sandbox reste
désactivé volontairement : l'application doit observer un raccourci global,
réactiver une autre application et piloter `System Events` pour y coller du texte.
Ces capacités ne sont pas compatibles avec le périmètre attendu d'une app
sandboxée sans revoir entièrement le mécanisme d'insertion.

## Préparer le Mac de publication

1. Ajouter le compte Apple Developer dans Xcode.
2. Installer un certificat `Developer ID Application`.
3. Créer un profil `notarytool` sans placer de secret dans le dépôt :

   ```bash
   xcrun notarytool store-credentials whisper-notary \
     --apple-id "adresse@example.com" \
     --team-id "TEAMID" \
     --password "mot-de-passe-spécifique-à-l-app"
   ```

4. Lancer :

   ```bash
   DEVELOPER_ID_APPLICATION="Developer ID Application: Nom (TEAMID)" \
   APPLE_TEAM_ID="TEAMID" \
   NOTARY_PROFILE="whisper-notary" \
   ./scripts/notarize.sh
   ```

Le script archive, signe, compresse, soumet à Apple, agrafe le ticket et valide le
résultat. Le zip final est produit dans `build/release/Whisper-<version>.zip`.

La notarisation elle-même ne peut pas être effectuée par CI ou par un contributeur
qui ne possède pas le certificat et les identifiants Apple Developer du
propriétaire.
