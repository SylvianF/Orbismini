#!/bin/sh
# Son des notifications d'Orbismini : « Melodic bonus collect » de Mixkit (n° 1938), choisi par
# Sylvian. Licence gratuite de Mixkit : utilisable dans une application, mais pas redistribuable
# seul ; il est donc téléchargé à la compilation et n'est jamais gardé dans ce dépôt public.
# Converti en CAF (PCM 16 bits), format lu par les notifications d'iOS. Sans lui (téléchargement
# impossible), l'application est faite quand même et les notifications gardent le son d'iOS.
mkdir -p App/Sons
if curl -fsSL --retry 3 -o "${RUNNER_TEMP:-/tmp}/orbismini-son.mp3" \
    https://assets.mixkit.co/active_storage/sfx/1938/1938-preview.mp3 \
  && afconvert -f caff -d LEI16@44100 -c 1 "${RUNNER_TEMP:-/tmp}/orbismini-son.mp3" App/Sons/orbismini.caf; then
  ls -l App/Sons
else
  echo "::warning::Son des notifications non téléchargé : son d'iOS par défaut dans cette version."
  rm -f App/Sons/orbismini.caf
fi
