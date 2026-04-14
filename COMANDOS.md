# Comandos útiles — Acuaflex

Rutas: abrí PowerShell o CMD en la carpeta del proyecto, por ejemplo:

`cd "C:\Users\Il Gordo VC\Documents\Apps Moviles\acuaflex_v1"`

---

## Publicar la web (Firebase Hosting)

1. **Compilar la app para web (release)**  
   Genera la carpeta `build/web` que usa `firebase.json`.

   ```bash
   flutter build web --release
   ```

2. **Subir a Firebase** (necesitás [Firebase CLI](https://firebase.google.com/docs/cli) instalado y haber hecho `firebase login` al menos una vez).

   Instalación global (Node.js requerido):

   ```bash
   npm install -g firebase-tools
   ```

   Si `firebase` no se reconoce en PowerShell, cerrá y volvé a abrir la terminal, o usá:

   ```bash
   npx firebase-tools deploy --only hosting
   ```

   ```bash
   firebase deploy --only hosting
   ```

   - Solo hosting (recomendado cuando solo cambiaste la app web).
   - La URL suele ser la del proyecto en Firebase Console → Hosting.

3. **Si también cambiaste reglas** (Firestore / Storage):

   ```bash
   firebase deploy --only firestore:rules,storage:rules
   ```

4. **Todo junto** (hosting + reglas):

   ```bash
   firebase deploy
   ```

**Primera vez con Firebase en esta PC:** `npm install -g firebase-tools` y luego `firebase login`. Si tenés varios proyectos: `firebase use acuaflex-41372` (o el alias que uses).

**Contraseñas de usuarios:** se cambian en [Firebase Console](https://console.firebase.google.com) → tu proyecto → **Authentication** (no desde la app).

---

## APK (Android)

**APK para instalar manualmente** (un solo archivo):

```bash
flutter build apk --release
```

El archivo queda en:

`build\app\outputs\flutter-apk\app-release.apk`

**App Bundle para Google Play** (lo que pide la tienda):

```bash
flutter build appbundle --release
```

Salida típica:

`build\app\outputs\bundle\release\app-release.aab`

Antes de publicar en Play: firmar la app, versión en `pubspec.yaml` (`version: x.y.z+build`).

---

## Comandos Flutter básicos

| Comando | Uso |
|--------|-----|
| `flutter pub get` | Descargar dependencias después de clonar o cambiar `pubspec.yaml` |
| `flutter run` | Ejecutar en dispositivo/emulador conectado |
| `flutter run -d chrome` | Ejecutar versión web en Chrome (desarrollo) |
| `flutter analyze` | Revisar el código sin compilar |
| `flutter clean` | Borra `build/`; útil si algo falla raro, luego `flutter pub get` |
| `flutter doctor -v` | Ver si falta SDK, licencias Android, etc. |

---

## Resumen rápido: “subir web ahora”

```bash
cd "C:\Users\Il Gordo VC\Documents\Apps Moviles\acuaflex_v1"
flutter build web --release
firebase deploy --only hosting
```

---

## iOS (solo en Mac)

```bash
flutter build ios --release
```

Luego abrís `ios/Runner.xcworkspace` en Xcode para firmar y subir a App Store Connect.
