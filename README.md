# Composants Linux de Velka

Ce dépôt fabrique et publie les deux composants libres que l'application Velka télécharge sous Linux (x86_64).
Il ne contient que des scripts de fabrication ; le code de Velka n'est pas ici.

| Archive | Contenu | Licence |
|---|---|---|
| `streamlink-<version>-linux-x86_64.zip` | [Streamlink](https://streamlink.github.io) et ses dépendances (PyPI), dans le Python autonome de [python-build-standalone](https://github.com/astral-sh/python-build-standalone). Lanceur : `streamlink/bin/streamlink` | Streamlink : BSD 2 clauses ; Python : PSF ; dépendances : voir `VERSIONS.txt` dans l'archive |
| `libmpv-lgpl-<version>-linux-x86_64.zip` | libmpv compilée ici depuis les sources : [mpv](https://github.com/mpv-player/mpv) avec `-Dgpl=false`, [FFmpeg](https://ffmpeg.org) sans `--enable-gpl` ni `--enable-nonfree`, et libplacebo, libass, FriBidi, HarfBuzz, FreeType, zlib liés dans une seule `libmpv.so.2` | GNU LGPL 2.1 ou plus récente (autres bibliothèques : licences libres permissives ou LGPL, textes dans `licences/`) |

Chaque archive a son fichier `.sha256`. Velka n'installe une archive que si son empreinte figure dans un manifeste signé
par l'éditeur.

## Ce qui est modifié
- Streamlink : rien dans le code. Python allégé (tests, Tk, IDLE, en-têtes C, pip, bibliothèque `libpython` inutilisée
  retirés ; symboles de débogage retirés), liens symboliques remplacés par des copies, lanceur `bin/streamlink` ajouté.
- libmpv : rien dans le code. Compilée sans aucune bibliothèque du système à part la glibc et le son (PulseAudio,
  ALSA), sans décodage matériel ; sortie vidéo par l'API de rendu OpenGL de l'application.

## Sources
- `sources.txt` : dépôt, étiquette et commit exact de chaque projet compilé (Git vérifie l'empreinte à la récupération).
- Streamlink : https://github.com/streamlink/streamlink ; Python : https://github.com/astral-sh/python-build-standalone.

## Refaire une version
Onglet Actions > « Fabrication » > « Run workflow ». Pour changer de version : modifier `sources.txt` (étiquette et
commit) et les valeurs en tête de `.github/workflows/fabrication.yml` (Streamlink, Python et son empreinte), puis
relancer. Sur une machine Ubuntu : `bash libmpv.sh libmpv.zip` et `bash streamlink.sh <archive Python> <version>
streamlink.zip` (outils demandés : voir l'en-tête de chaque script).
Vous pouvez aussi remplacer `libmpv.so.2` par votre propre version de libmpv dans Velka (Réglages > Avancé et Système >
Chemins personnalisés).
