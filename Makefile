HOST    ?= ftp.eng.viptela.com
RELEASE ?= next
BUILD   ?= LATEST
MACHINE ?= genericx86-64
IMAGES   = vedge.qcow2 vsmart.qcow2
CONFS   := $(wildcard *.conf)
VEDGES  := $(wildcard ve*.conf)
VSMARTS := $(wildcard vs*.conf)
VBONDS  := $(wildcard vb*.conf)
ISOS    := $(CONFS:.conf=.iso)
CRTS    := $(CONFS:.conf=.crt)
CSRS    := $(CONFS:.conf=.csr)
SRLS    := $(CONFS:.conf=.srl)
KEYS    := $(CONFS:.conf=.key)
UUIDS   := $(CONFS:.conf=.uuid)
SUBJECT ?= /C=US/ST=CA/L=San Jose/OU=Acme/O=vIPtela Inc
DAYS    ?= 3650

.PHONY: all clean mrclean

.NOTPARALLEL:

.INTERMEDIATE: $(ISOS) $(CRTS) $(SRLS) $(KEYS) $(UUIDS) \
	ca.crt ca.key vedge_serial_numbers vsmart_serial_numbers

all: .done

.done: $(ISOS) $(IMAGES) network.xml
	@testbed create network.xml
	@touch .done

vedge.qcow2:
	@wget ftp://$(HOST)/builds/bamboo/$(RELEASE)/$(BUILD)/viptela-edge-$(MACHINE).qcow2 -O $@

vsmart.qcow2:
	@wget ftp://$(HOST)/builds/bamboo/$(RELEASE)/$(BUILD)/viptela-smart-$(MACHINE).qcow2 -O $@

ca.crt ca.key:
	@openssl req -new -x509 -nodes -keyout ca.key -out ca.crt -subj "$(SUBJECT)/CN=ca" 2>/dev/null

%.csr %.key:
	@openssl req -new -nodes -out $*.csr -keyout $*.key -subj "$(SUBJECT)/CN=$*" 2>/dev/null

%.crt %.srl: ca.crt ca.key %.csr
	@openssl x509 -req -days $(DAYS) -CA ca.crt -CAkey ca.key -CAcreateserial -in $*.csr -out $*.crt 2>/dev/null
	@mv ca.srl $*.srl

%.iso: %.crt %.key %.csr %.uuid ca.crt ca.key
	@./cidata.sh $*

$(VBONDS:.conf=.iso): vsmart_serial_numbers vedge_serial_numbers

$(VSMARTS:.conf=.iso): vedge_serial_numbers

%.uuid:
	@uuidgen > $@

vsmart_serial_numbers: $(VSMARTS:.conf=.srl)
	@for s in $^; do echo "`cat $$s`,valid"; done > $@

vedge_serial_numbers: $(VEDGES:.conf=.srl) $(VEDGES:.conf=.uuid)
	@for s in $(VEDGES:.conf=.srl); do echo "`cat $${s%.*}.uuid`,`cat $$s`,valid"; done > $@

clean:
	@testbed destroy network.xml
	@rm -f .done

mrclean: clean
	@rm -f $(IMAGES)
