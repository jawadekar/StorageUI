all: main.cgi storage

install: install_bin install_sh install_get_info install_html install_js

install_bin: storage main.cgi
	cp storage main.cgi /usr/lib/cgi-bin/
	chmod +x /usr/lib/cgi-bin/main.cgi /usr/lib/cgi-bin/storage
	chmod +s /usr/lib/cgi-bin/main.cgi

install_sh:
	cp functions.sh main.sh visualization.sh /usr/lib/cgi-bin
	chmod +x /usr/lib/cgi-bin/*.sh

install_get_info:
	cp getluntarginfo getlvinfo getmdinfo getpvinfo getsessioninfo /usr/lib/cgi-bin/
	chmod +x /usr/lib/cgi-bin/get*info

main.cgi: main.c
	gcc -o main.cgi main.c

storage: storage.c
	gcc -g -o storage storage.c

install_html:
	cp index.html /var/www/

install_js:
	cp tabber.js /var/www/jscripts
	cp storageui.css /var/www/css

clean:
	rm -f *.cgi storage
