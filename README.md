# Convertor

Media file converter for macOS.

This application allows you to convert your audio (FLAC) and video (MKV, MP4) files to Apple-compatible formats (AAC/ALAC for audio, MOV for video). It's a powerful and efficient tool for preparing your media files for your Apple devices, with hardware acceleration for fast conversions.

## Features

### Audio Conversion
- Convert FLAC files to AAC or Apple Lossless (ALAC).
- Customizable audio bitrate (256k or 320k).
- Preserves metadata (including album art).

### Video Conversion
- Convert MKV, MP4, and WebM files to MOV or MP4 format.
- Hardware-accelerated encoding using VideoToolbox (H.264/H.265).
- Customizable video codec (H.264 or H.265 HEVC).
- Adjustable resolution (720p, 1080p, 4K).
- Custom video bitrate or quality presets (1-6 Mbps).
- Adaptive bitrate to fit maximum file size.
- Audio language selection.
- Subtitle language selection and embedding.

### General Features
- Drag and drop files or select them through a file dialog.
- Concurrent conversions to speed up the process.
- Progress indicators for each conversion.
- Cancellation of individual or all conversions.
- Per-file settings customization.
- Notifications on conversion completion.
- English and French localization.

## Requirements

- macOS 13.0 or later (for VideoToolbox hardware acceleration)
- Xcode (for building)

## How to Build

1.  Clone the repository.
2.  Open `Convertor.xcodeproj` in Xcode.
3.  Select the `Convertor` scheme.
4.  Build and run the application.

## Screenshots

![Main Window](screenshots/screenshot-main.png)
![Settings](screenshots/screenshot-settings.png)

## License


---

# Convertor (Français)

Convertisseur de fichiers multimédia pour macOS.

Cette application vous permet de convertir vos fichiers audio (FLAC) et vidéo (MKV, MP4) vers des formats compatibles Apple (AAC/ALAC pour l'audio, MOV pour la vidéo). C'est un outil puissant et efficace pour préparer vos fichiers multimédia pour vos appareils Apple, avec accélération matérielle pour des conversions rapides.

## Fonctionnalités

### Conversion Audio
- Conversion des fichiers FLAC en AAC ou Apple Lossless (ALAC).
- Débit audio personnalisable (256k ou 320k).
- Préserve les métadonnées (y compris les pochettes d'album).

### Conversion Vidéo
- Conversion des fichiers MKV, MP4 et WebM vers le format MOV ou MP4.
- Encodage accéléré matériellement utilisant VideoToolbox (H.264/H.265).
- Codec vidéo personnalisable (H.264 ou H.265 HEVC).
- Résolution ajustable (720p, 1080p, 4K).
- Débit vidéo personnalisé ou préréglages de qualité (1-6 Mbps).
- Débit adaptatif pour respecter la taille maximale du fichier.
- Sélection de la langue audio.
- Sélection et incorporation des sous-titres.

### Fonctionnalités Générales
- Glisser-déposer les fichiers ou les sélectionner via une boîte de dialogue.
- Conversions simultanées pour accélérer le processus.
- Indicateurs de progression pour chaque conversion.
- Annulation des conversions individuelles ou de toutes les conversions.
- Personnalisation des paramètres par fichier.
- Notifications à la fin des conversions.
- Localisation en anglais et en français.

## Prérequis

- macOS 13.0 ou ultérieur (pour l'accélération matérielle VideoToolbox)
- Xcode (pour la compilation)

## Comment compiler

1.  Clonez le dépôt.
2.  Ouvrez `Convertor.xcodeproj` dans Xcode.
3.  Sélectionnez le schéma `Convertor`.
4.  Compilez et exécutez l'application.

## Captures d'écran

![Fenêtre principale](screenshots/screenshot-main.png)
![Paramètres](screenshots/screenshot-settings.png)

## Licence
