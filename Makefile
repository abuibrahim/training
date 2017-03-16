HOST    ?= ftp.eng.viptela.com
RELEASE ?= next
BUILD   ?= 4050
VMRELEASE ?= $(RELEASE)
VMBUILD ?= 2901
MACHINE ?= genericx86-64
IMAGES   = vedge.qcow2 vsmart.qcow2 vmanage.qcow2 video.qcow2
CONFS   := $(wildcard *.conf)
VEDGES  := $(wildcard ve*.conf)
VSMARTS := $(wildcard vs*.conf)
VBONDS  := $(wildcard vb*.conf)
VMANAGES:= $(wildcard vm*.conf)
ISOS    := $(CONFS:.conf=.iso) video1.iso
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

vmanage.qcow2:
	@wget ftp://$(HOST)/builds/bamboo/nms/$(VMRELEASE)/$(VMBUILD)/viptela-vmanage-$(MACHINE).qcow2 -O $@

video.qcow2:
	@wget ftp://$(HOST)/ruslan/video.qcow2 -O $@

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

$(VMANAGES:.conf=.iso): vsmart_serial_numbers vedge_serial_numbers

$(VSMARTS:.conf=.iso): vedge_serial_numbers

%.uuid:
	@uuidgen > $@

vsmart_serial_numbers: $(VSMARTS:.conf=.srl) $(VMANAGES:.conf=.srl)
	@for s in $^; do echo "`cat $$s`,valid"; done > $@

vedge_serial_numbers: $(VEDGES:.conf=.srl) $(VEDGES:.conf=.uuid)
	@for s in $(VEDGES:.conf=.srl); do echo "`cat $${s%.*}.uuid`,`cat $$s`,valid"; done > $@

video1.iso: video1-user-data video1-meta-data
	@cp video1-user-data user-data
	@cp video1-meta-data meta-data
	@echo "Generating $@"
	@genisoimage -quiet -volid cidata -joliet -rock -output $@ user-data meta-data
	@rm user-data meta-data

clean:
	@testbed destroy network.xml
	@rm -f .done

mrclean: clean
	@rm -f $(IMAGES)
