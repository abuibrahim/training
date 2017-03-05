#!/bin/sh

if [ $# -ne 1 ]; then
    echo "usage: $0 <hostname>"
    exit 1
fi

host=$1
out=$(mktemp -d cloudinit.XXXX)
trap "rm -rf $out" EXIT

cat >$out/meta-data <<EOF
instance-id: $host
local-hostname: $host
EOF

cat > $out/user-data <<EOF
Content-Type: multipart/mixed; boundary="===============4222881261212792538=="
MIME-Version: 1.0

--===============4222881261212792538==
MIME-Version: 1.0
Content-Type: text/cloud-boothook; charset="us-ascii"
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cli"

#cloud-boothook
EOF

cat $host.conf >> $out/user-data

cat >> $out/user-data <<EOF
--===============4222881261212792538==
MIME-Version: 1.0
Content-Type: text/cloud-config; charset="us-ascii"
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="bootstrap"

#cloud-config
ssh_authorized_keys:
- $(cat ~/.ssh/id_rsa.pub)

write_files:
- path: /home/root/root-ca.crt
  content: |
EOF
sed 's/^/    /' ca.crt >> $out/user-data

cat >> $out/user-data <<EOF

- path: /home/root/server.crt
  content: |
EOF
sed 's/^/    /' $host.crt >> $out/user-data

cat >> $out/user-data <<EOF

- path: /usr/share/viptela/server.key
  permissions: '0600'
  content: |
EOF
sed 's/^/    /' $host.key >> $out/user-data

case $host in
    ve*) csr=/usr/share/viptela/device_cert.csr ;;
    *)   csr=/usr/share/viptela/server.csr ;;
esac
cat >> $out/user-data <<EOF

- path: $csr
  content: |
EOF
sed 's/^/    /' $host.csr >> $out/user-data

cat >> $out/user-data <<EOF

- path: /etc/viptela/uuid
  content: $(cat $host.uuid)
EOF

case $host in
    vb*|vs*|vm*)
	cat >> $out/user-data <<EOF

- path: /usr/share/viptela/vedge_serial_numbers
  content: |
EOF
	sed 's/^/    /' vedge_serial_numbers >> $out/user-data
	;;
esac

case $host in
    vb*|vm*)
	cat >> $out/user-data <<EOF

- path: /usr/share/viptela/vsmart_serial_numbers
  content: |
EOF
	sed 's/^/    /' vsmart_serial_numbers >> $out/user-data
	;;
esac

cat >> $out/user-data <<EOF

runcmd:
  - export CONFD_IPC_ACCESS_FILE=/etc/confd/confd_ipc_secret
  - vconfd_script_upload_root_ca_crt_chain.sh path /home/root/root-ca.crt
  - vconfd_script_cert.sh path /home/root/server.crt
EOF

case $host in
    vb*)
	cat >> $out/user-data <<EOF
  - cp /home/root/server.crt /usr/share/viptela/server.crt
EOF
	;;
esac

case $host in
    vm*)
	cat >> $out/user-data <<EOF
  - cp /home/root/root-ca.crt /usr/share/viptela/vmanage_root.crt
  - keytool -importcert -trustcacerts -file /home/root/root-ca.crt -keystore /usr/lib/cacerts -storepass changeit -alias acme -noprompt
EOF
	;;
    *)
	cat >> $out/user-data <<EOF
  - reboot

EOF
	;;
esac

cat >> $out/user-data <<EOF

--===============4222881261212792538==--

EOF

echo "Generating $host.iso"
genisoimage -quiet -volid cidata -joliet -rock -output $host.iso $out
