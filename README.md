# mKOBO

## About

mKOBO finds free, legal books, comics and audiobooks (public domain and free licences) and sends them to your Kobo e-reader over USB, or to a Google Drive folder the e-reader can read. Browse results as thumbnails or a list, filter by type and language, select titles and send. Part of the DESKTOP MAC TOOLKIT.

mKOBO hosts no books: it searches Project Gutenberg, Wikisource, Internet Archive and LibriVox. Public-domain rules vary by country; check a title's status where you live. Kobo e-readers only play audiobooks from the Kobo store, so free MP3 audiobooks are copied to Google Drive for your phone.

## Utilisation

Interface en français, anglais, espagnol et italien (langue du Mac). Branche la Kobo (USB-C, « Connecter »), choisis tes titres, « Envoyer à la Kobo » ou « Copier sur Drive ». Le dossier Google Drive se choisit dans les réglages. Pour convertir les EPUB en KEPUB (pagination et statistiques Kobo) : `brew install kepubify`.

```bash
DEV=1 NO_INSTALL=1 ./build_app.sh   # édition de développement
./build_app.sh                       # compile, signe et installe
```

## Support / Soutenir

Facultatif : https://github.com/sponsors/starbudweiser
