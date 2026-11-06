# CarShare

CarShare est une application Flutter Android pour la gestion des comptes de covoiturage. Le client mobile communique avec une API **Spring Boot** ; les comptes et sessions sont stockés dans **PostgreSQL sur Neon**.

> Le module pris en charge est la gestion des utilisateurs : authentification, profil, photo, préférences, contacts d’urgence, statut du compte et consultation de l’historique des sanctions. Les trajets, réservations, paiements, messages, géolocalisation et statistiques de profil ne sont pas inclus.

## Architecture

```text
Application Flutter  →  API REST Spring Boot  →  PostgreSQL (Neon)
      Android                  port 8081                 données
```

- `lib/` : pages Flutter, validation des formulaires, client HTTP et stockage sécurisé du jeton de session.
- `backend/` : API REST Spring Boot, sécurité des sessions, accès PostgreSQL et migrations Flyway.
- `backend/src/main/resources/db/migration/` : migrations versionnées du schéma.
- `run-android-phone.ps1` : démarrage Flutter sur un téléphone USB avec redirection vers l’API locale.
- `backend/run-local.ps1` : démarrage local de l’API à partir de la configuration Neon.

Firebase n’est plus utilisé par le code actuel. Les anciens comptes Firebase ne sont pas transférés automatiquement vers Neon : il faut créer un compte dans CarShare, sauf si l’équipe organise une migration des comptes.

## Prérequis

- Flutter SDK compatible avec la version déclarée dans `pubspec.yaml` (Dart `^3.13.3`).
- Android Studio avec Android SDK et un émulateur, ou un téléphone Android avec débogage USB activé.
- JDK 17 ou plus récent.
- Accès au projet Neon partagé par l’équipe et Neon CLI pour la première configuration.
- Git et une connexion réseau pour télécharger les dépendances la première fois.

Vérifier les outils :

```powershell
flutter doctor
flutter --version
java -version
```

## Première configuration du poste

### 1. Récupérer les dépendances Flutter

Depuis la racine du dépôt :

```powershell
flutter pub get
```

### 2. Lier le dépôt au projet Neon de l’équipe

Si Neon CLI n’est pas installé :

```powershell
npm install -g neon@latest
```

Se connecter si nécessaire, puis lier ce dépôt au **projet Neon existant de l’équipe** :

```powershell
neon auth
neon link
```

Dans les choix interactifs, sélectionner l’organisation, le projet CarShare et la branche décidée par l’équipe. La liaison crée le fichier local `.neon` et récupère les variables de connexion dans `.env.local` à la racine. Ces fichiers sont ignorés par Git : ne les ajoutez jamais au dépôt et ne partagez pas leur contenu dans les tickets ou messages.

Pour le travail qui modifie le schéma ou les données, utiliser une branche Neon de développement convenue avec l’équipe. La branche Neon doit correspondre à la tâche et aux migrations Flyway en cours ; évitez de tester des migrations sur une branche partagée ou de production.

### 3. Démarrer le backend

Dans un premier terminal PowerShell, depuis la racine :

```powershell
.\backend\run-local.ps1
```

L’API démarre sur `http://localhost:8080`. Le script lit `.env.local`, convertit les URL Neon en URL JDBC en mémoire, utilise la connexion poolée pour les requêtes et l’URL directe pour Flyway. Il ne doit pas afficher les identifiants de base de données.

Au premier démarrage, Flyway crée les tables à partir des migrations du dossier backend. Hibernate vérifie le schéma sans le modifier. Pour changer la base, ajoutez une nouvelle migration Flyway versionnée ; ne modifiez pas manuellement la base pour contourner une migration.

Si la commande échoue, vérifiez que `.env.local` contient les variables Neon attendues (`DATABASE_URL` et, si disponible, `DATABASE_URL_UNPOOLED`) et que le compte peut joindre Neon. Ne collez pas les valeurs de ces variables dans le dépôt.

### 4. Lancer l’application Flutter

Laissez le backend actif.

**Émulateur Android** : dans un second terminal à la racine :

```powershell
flutter run
```

La configuration par défaut utilise `http://10.0.2.2:8080/api`, l’adresse de l’hôte depuis l’émulateur Android.

**Téléphone Android connecté en USB** :

```powershell
.\run-android-phone.ps1
```

Le script vérifie la connexion ADB, redirige le port 8080 du téléphone vers l’ordinateur et démarre Flutter avec l’adresse locale adaptée. Gardez le backend actif dans son terminal. Autorisez le débogage USB sur le téléphone si Android affiche une demande.

Pour une autre cible Android ou une API distante, fournissez une adresse accessible depuis l’appareil :

```powershell
flutter run --dart-define=CARSHARE_API_BASE_URL=https://ADRESSE_DE_VOTRE_API/api
```

Ne mettez pas une URL locale `localhost` dans l’application pour un téléphone physique : `localhost` désignerait le téléphone lui-même. Le manifeste Android n’autorise HTTP en clair que pour le débogage local ; utiliser HTTPS pour une API publiée.

## Parcours utilisateur disponible

1. **Sign Up / Sign In / Sign Out** : gérer le compte Neon ; cinq mots de passe incorrects verrouillent la connexion pendant 15 minutes.
2. **Profil** : consulter et modifier nom, téléphone, e-mail et rôle, ajouter ou retirer une photo, ou supprimer le compte après confirmation du mot de passe.
3. **Préférences** : enregistrer langue, domicile, travail, campus, musique, tabac, animaux et bagages.
4. **Contacts d’urgence** : ajouter, modifier et supprimer des contacts.
5. **Statut et sanctions** : consulter son statut calculé et l’historique des sanctions. Les sanctions sont créées par le module Support.
6. **Administration** : un compte promu `ADMIN` peut consulter la liste des comptes. Le statut reste calculé à partir des points de sanction.
7. **Forgot password?** : demander un code à six chiffres par e-mail, puis le saisir dans l’application. SMTP doit être configuré.

Le backend chiffre les mots de passe avec BCrypt et ne stocke que les empreintes des jetons de session. L’application conserve le jeton dans le stockage sécurisé Android et l’envoie comme jeton Bearer aux routes protégées.

## Configuration de la récupération du mot de passe

La demande **Forgot password?** nécessite un fournisseur SMTP. Définir ces variables dans l’environnement du backend, ou dans la configuration locale appropriée :

```text
MAIL_HOST
MAIL_PORT
MAIL_USERNAME
MAIL_PASSWORD
MAIL_FROM
PUBLIC_API_URL
```

Le courriel contient un code à six chiffres valable 30 minutes. Après cinq codes incorrects, il faut demander un nouveau code. Aucun lien public ni tunnel n’est nécessaire. Sans SMTP configuré, les autres fonctions de compte restent disponibles.

Les migrations Flyway ajoutent les tables et champs nécessaires lors du prochain démarrage du backend. Exécuter ces changements d’abord sur une branche Neon de développement. Pour activer l’écran administrateur, un administrateur de la base doit promouvoir explicitement un compte existant (`role = 'ADMIN'`) après application des migrations ; l’inscription mobile ne permet jamais de choisir ce rôle.

## Vérifications de développement

Depuis la racine du dépôt :

```powershell
flutter analyze
flutter build apk --debug
```

Pour démarrer l’API seule depuis son dossier :

```powershell
Set-Location .\backend
.\gradlew.bat bootRun
```

La méthode recommandée reste `backend/run-local.ps1`, qui charge les variables Neon de `.env.local` automatiquement.

## Dépannage

| Symptôme | Vérifications |
| --- | --- |
| L’inscription ou la connexion expire | Vérifier que le backend tourne sur le port 8080, que Neon est joignable et que le téléphone utilise `run-android-phone.ps1`. |
| `Connection problem` sur émulateur | Démarrer d’abord le backend ; vérifier que l’émulateur utilise la configuration par défaut `10.0.2.2`. |
| `Connection problem` sur téléphone USB | Vérifier ADB et le débogage USB, puis lancer `run-android-phone.ps1` depuis la racine. |
| E-mail ou mot de passe refusé | Vérifier l’adresse et le mot de passe du compte Neon. Un ancien compte Firebase n’est pas automatiquement disponible dans le nouveau backend. |
| Erreur Flyway ou connexion à la base | Vérifier la branche Neon liée et la présence locale de `.env.local` sans révéler ses secrets. |
| Espace disque insuffisant pendant Flutter | `run-android-phone.ps1` place les fichiers temporaires Flutter et Gradle dans `.dart_tool/codex-temp` sur le disque du projet. Vérifier l’espace libre sur ce disque. |
| Réinitialisation du mot de passe non envoyée | Configurer les variables SMTP du backend et vérifier `PUBLIC_API_URL`. |

## Références

- [Documentation Flutter](https://docs.flutter.dev/)
- [Neon CLI et liaison des projets](https://neon.com/blog/branch-first-dev-loop)
- [Guide du backend](backend/README.md)
