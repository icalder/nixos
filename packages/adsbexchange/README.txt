Setup:

sudo machinectl shell adsbexchange

copy this file from any previous installation: /usr/local/share/adsbexchange/adsbx-uuid

Then follow instructions at https://github.com/ADSBexchange/feedclient

NB - if setting up a new env copy /usr/local/share/adsbexchange/adsbx-uuid in place before running setup!!

For trixie:
BUT
modify /tmp/axfeed.sh to use https://github.com/icalder/feedclient (readsb-makefile-updates branch) until readsb build issue (ncurses?) is solved

Also install stats package:
curl -L -o /tmp/axstats.sh https://adsbexchange.com/stats.sh
bash /tmp/axstats.sh
adsbexchange-showurl

https://adsbexchange.com/myip/
MLAT map:
https://map.adsbexchange.com/mlat-map/
MLAT region 21 sync details:
https://map.adsbexchange.com/sync/21
My MLAT sync details:
https://map.adsbexchange.com/sync/feeder.html?21&icalder-egbj