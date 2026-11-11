# CarShare

CarShare est une application Flutter Android pour la gestion des comptes de covoiturage. Le client mobile communique avec une API **Spring Boot** ; les comptes et sessions sont stockés dans **PostgreSQL sur Neon**.

> Les modules pris en charge sont la gestion des utilisateurs (authentification, profil, préférences, contacts d’urgence et statut du compte) et la gestion des véhicules des conducteurs. Les trajets, réservations, paiements, messages, géolocalisation et statistiques de profil ne sont pas inclus.

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

L’authentification et les comptes sont gérés par le backend CarShare et stockés dans Neon. Les comptes d’un ancien système ne sont pas transférés automatiquement : ils doivent être recréés, sauf si l’équipe organise une migration dédiée.

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
3. **Véhicules** : ajouter, consulter, modifier et supprimer ses véhicules, gérer jusqu’à quatre photos et choisir le véhicule par défaut.
4. **Préférences** : enregistrer langue, domicile, travail, campus, musique, tabac, animaux et bagages.
5. **Contacts d’urgence** : ajouter, modifier et supprimer des contacts.
6. **Statut et sanctions** : consulter son statut calculé et l’historique des sanctions. Les sanctions sont créées par le module Support.
7. **Administration** : l’espace admin regroupe les comptes, la validation des véhicules, la consultation des trajets et réservations, le support et objets trouvés, et les sanctions. Un véhicule doit être approuvé avant d’être utilisé pour un nouveau trajet. Les décisions de sanction demandent un motif et suivent les seuils existants (3 points : avertissement, 6 : suspension de 7 jours, 9 : suspension de 30 jours, 12 : bannissement) ; chaque sanction expire après 90 jours. Les trajets et réservations restent soumis à leurs règles normales de transition.
8. **Forgot password?** : demander un code à six chiffres par e-mail, puis le saisir dans l’application. SMTP doit être configuré.

Le backend chiffre les mots de passe avec BCrypt et ne stocke que les empreintes des jetons de session. L’application conserve le jeton dans le stockage sécurisé Android et l’envoie comme jeton Bearer aux routes protégées.

## Module Réservation

Le module couvre tout le trajet partagé : publier un trajet, le chercher avec un score de
correspondance, réserver une place, suivre la voiture en direct, confirmer la prise en charge
avec un code à 4 chiffres, puis noter l'autre partie une fois le trajet terminé.

Côté serveur : `com.carshare.api.reservation` (migrations `V7` à `V10`).
Côté application : `lib/pages/reservation/`, `lib/services/reservation_service.dart` et
`lib/services/tracking_service.dart`.

### Lancer la démo passager / conducteur

Il faut deux comptes : un `driver` et un `passenger` (créés via `POST /api/auth/signup`).

```powershell
# 1. le backend, port 8081
.\backend\run-local.ps1
```

```powershell
# 2. l'application sur un téléphone branché en USB
.\run-android-phone.ps1
```

Le script fait le `adb reverse tcp:8081 tcp:8081` et passe
`--dart-define=CARSHARE_API_BASE_URL=http://127.0.0.1:8081/api`. Sur un émulateur, `flutter run`
suffit : l'adresse par défaut `10.0.2.2` désigne déjà le poste hôte.

Le téléphone tient un rôle, l'autre se joue en `curl` avec le jeton du second compte : le
conducteur publie un trajet dont le départ est proche de votre position, le passager le trouve
dans la recherche et réserve, le conducteur accepte puis passe en `DRIVER_EN_ROUTE` et envoie
des positions le long de la polyline — la voiture avance alors sur la carte du passager.
L'ordre complet des appels est dans [docs/reservation-api.md](docs/reservation-api.md).

### Documentation

| Fichier | Contenu |
| --- | --- |
| [docs/reservation-spec.md](docs/reservation-spec.md) | les règles : machine à états, score de correspondance, notations |
| [docs/reservation-api.md](docs/reservation-api.md) | chaque endpoint, le JSON, les codes d'erreur, l'ordre des appels |
| [docs/CarShare-Reservation.postman_collection.json](docs/CarShare-Reservation.postman_collection.json) | collection Postman prête à l'emploi |
| [docs/mockups/](docs/mockups/) | les maquettes, numérotées par écran |

Les autres modules n'écrivent jamais dans nos tables : ils injectent `ReservationQueries`
(service en lecture seule) et passent par l'API REST pour toute modification.

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

Les migrations Flyway ajoutent les tables et champs nécessaires lors du prochain démarrage du backend. Exécuter ces changements d’abord sur une branche Neon de développement. Pour activer l’écran administrateur, le premier compte doit être promu manuellement par un administrateur de la base (`role = 'ADMIN'`) après application des migrations ; ensuite, les admins peuvent gérer les rôles depuis l’application. L’inscription mobile ne permet jamais de choisir ce rôle.

### Connexion Google et Facebook

Les connexions sociales sont vérifiées par le backend Spring, puis créent une session CarShare normale. Google vérifie l’ID token et son audience côté serveur. Facebook vérifie le jeton auprès de Meta. Aucun identifiant de fournisseur n’est fourni par le dépôt : créez/configurez les applications dans Google Cloud et Meta Developers avant d’activer les boutons.

- Backend : configurez `GOOGLE_SERVER_CLIENT_ID`, `FACEBOOK_APP_ID` et `FACEBOOK_APP_SECRET` dans votre environnement local. Gardez le secret Meta uniquement côté serveur.
- Android : définissez les variables d’environnement `GOOGLE_SERVER_CLIENT_ID`, `FACEBOOK_APP_ID` et `FACEBOOK_CLIENT_TOKEN` dans PowerShell avant `.un-android-phone.ps1`. Enregistrez aussi l’empreinte SHA-1 Android dans Google Cloud et l’empreinte de clé Android dans Meta Developers.
- Au premier accès social, l’application demande le téléphone et le rôle passager/conducteur. Un compte administrateur ne peut jamais être créé par ce parcours.
- La migration `V16__admin_operations_and_social_accounts.sql` ajoute les comptes fournisseurs, les demandes support et les informations de validation véhicule. Appliquez-la d’abord sur une branche Neon de développement.

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
| E-mail ou mot de passe refusé | Vérifier l’adresse et le mot de passe du compte CarShare. Les comptes d’un ancien système ne sont pas automatiquement disponibles dans le backend actuel. |
| Erreur Flyway ou connexion à la base | Vérifier la branche Neon liée et la présence locale de `.env.local` sans révéler ses secrets. |
| Espace disque insuffisant pendant Flutter | `run-android-phone.ps1` place les fichiers temporaires Flutter et Gradle dans `.dart_tool/codex-temp` sur le disque du projet. Vérifier l’espace libre sur ce disque. |
| Réinitialisation du mot de passe non envoyée | Configurer les variables SMTP du backend et vérifier `PUBLIC_API_URL`. |

## Références

- [Documentation Flutter](https://docs.flutter.dev/)
- [Neon CLI et liaison des projets](https://neon.com/blog/branch-first-dev-loop)
- [Guide du backend](backend/README.md)
