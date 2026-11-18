# Contributing to Scanly

## Workflow

1. Pick the next unchecked item in [TASKS.md](TASKS.md).
2. Keep each change small and focused, with one logical change per commit.
3. Before every commit, run:
   ```bash
   dart format .
   flutter analyze
   flutter test
   ```
4. Don't disable lint rules to get a build through. Fix the code instead.
5. Tick the task in TASKS.md in the same commit that finishes it.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scanner): add quadrilateral validation
fix(db): cascade delete page OCR rows
docs: document iOS signing
test(pdf): cover Legal page size
```

## Code style

- Feature-first layout. The UI talks only to providers, and providers talk to repositories and services.
- No database, filesystem, camera, or OCR access from widgets.
- Every async screen has loading, empty, and error states.
- Expensive image work runs off the UI thread (isolates or native code).

## Generated code

Drift and Riverpod generate code. After you change a table or provider, run:

```bash
dart run build_runner build
```

## Signing

Create `android/key.properties` (Git ignores it):

```
storePassword=<your password>
keyPassword=<your password>
keyAlias=upload
storeFile=<absolute path to upload-keystore.jks>
```

Generate the keystore with:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
