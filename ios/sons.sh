#!/bin/sh
# Son des notifications d'Orbismini : le même que celui d'Orbis à l'arrivée d'une demande de
# virement (trois notes montantes, virements_panel.js), choisi par Sylvian comme son commun.
# Sons/orbis.wav est fabriqué par Sons/fabriquer.py (aucune licence de tiers). Il est converti
# en CAF à la compilation, sous le nom que demandent les notifications (apns.py : orbismini.caf).
mkdir -p App/Sons
if afconvert -f caff -d LEI16@44100 -c 1 Sons/orbis.wav App/Sons/orbismini.caf; then
  ls -l App/Sons
else
  echo "::warning::Son des notifications non converti : son d'iOS par défaut dans cette version."
  rm -f App/Sons/orbismini.caf
fi
