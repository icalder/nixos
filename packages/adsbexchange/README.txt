Setup:

sudo machinectl shell adsbexchange

copy this file from any previous installation: /usr/local/share/adsbexchange/adsbx-uuid

Then follow instructions at https://github.com/ADSBexchange/feedclient
BUT
modify /tmp/axfeed.sh to use https://github.com/icalder/feedclient until readsb build issue (ncurses?) is solved

Also install stats package:
curl -L -o /tmp/axstats.sh https://adsbexchange.com/stats.sh
bash /tmp/axstats.sh
adsbexchange-showurl

https://adsbexchange.com/myip/