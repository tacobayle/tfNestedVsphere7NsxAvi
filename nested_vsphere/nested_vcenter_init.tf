
resource "null_resource" "vcenter_install" {
  depends_on = [null_resource.esxi_customization_disk]

  provisioner "local-exec" {
    command = "/bin/bash iso_extract_vCenter.sh"
  }
}

resource "null_resource" "wait_vsca" {
  depends_on = [null_resource.vcenter_install]

  provisioner "local-exec" {
    command = "count=1 ; until $(curl --output /dev/null --silent --head -k https://${var.vcenter.vds.portgroup.management.vcenter_ip}); do echo \"Attempt $count: Waiting for vCenter to be reachable...\"; sleep 10 ; count=$((count+1)) ;  if [ \"$count\" = 30 ]; then echo \"ERROR: Unable to connect to vCenter\" ; exit 1 ; fi ; done"
  }
}

resource "null_resource" "vcenter_configure1" {
  depends_on = [null_resource.wait_vsca]

  provisioner "local-exec" {
    command = "/bin/bash vCenter_config1.sh"
  }
}

resource "null_resource" "vcenter_migrating_vmk_to_dvs" {
  depends_on = [null_resource.vcenter_configure1]

  provisioner "local-exec" {
    command = "ansible-playbook pb-vmk.yml --extra-vars @../variables.json"
  }
}

resource "null_resource" "migrating_vmk0" {
  depends_on = [null_resource.vcenter_migrating_vmk_to_dvs]
  count = var.esxi.count
  connection {
    host        = var.vcenter.vds.portgroup.management.esxi_ips_temp[count.index]
    type        = "ssh"
    agent       = false
    user        = "root"
    password    = var.esxi_root_password
  }

  provisioner "remote-exec" {
    inline      = [
      "portid=$(esxcfg-vswitch -l |grep vmk4 |awk '{print $1}')",
      "esxcli network ip interface remove --interface-name=vmk0",
      "esxcli network ip interface remove --interface-name=vmk4",
      "esxcli network ip interface add --interface-name=vmk0 --dvs-name=${var.vcenter.vds.basename}-0 --dvport-id=$portid",
      "esxcli network ip interface ipv4 set --interface-name=vmk0 --ipv4=${var.vcenter.vds.portgroup.management.esxi_ips[count.index]} --netmask=${var.vcenter.vds.portgroup.management.netmask} --type=static",
      "esxcli network ip interface tag add -i vmk0 -t Management",
      "esxcli network ip interface set -m 1500 -i vmk0",
      "esxcli network ip interface set -m ${var.vcenter.vds.mtu} -i vmk1",
      "esxcli network ip interface set -m ${var.vcenter.vds.mtu} -i vmk2"
    ]
  }
}

resource "null_resource" "cleaning_vmk3" {
  depends_on = [null_resource.migrating_vmk0]
  count = var.esxi.count
  connection {
    host        = var.vcenter.vds.portgroup.management.esxi_ips[count.index]
    type        = "ssh"
    agent       = false
    user        = "root"
    password    = var.esxi_root_password
  }

  provisioner "remote-exec" {
    inline      = [
      "esxcli network ip interface remove --interface-name=vmk3"
    ]
  }
}

resource "null_resource" "vcenter_configure2" {
  depends_on = [null_resource.cleaning_vmk3]

  provisioner "local-exec" {
    command = "/bin/bash vCenter_config2.sh"
  }
}

resource "null_resource" "dual_uplink_update_multiple_vds" {
  depends_on = [null_resource.vcenter_configure2]
  count = var.esxi.count
  connection {
    host        = var.vcenter.vds.portgroup.management.esxi_ips[count.index]
    type        = "ssh"
    agent       = false
    user        = "root"
    password    = var.esxi_root_password
  }

  provisioner "remote-exec" {
    inline      = [
      "esxcli network vswitch standard uplink remove -u vmnic4 -v vSwitch1",
      "esxcli network vswitch standard uplink remove -u vmnic5 -v vSwitch2",
      "portid=$(esxcfg-vswitch -l | grep -A4 ${var.vcenter.vds.basename}-0 | grep -A2 DVPort | grep -A1 vmnic0 | grep -v vmnic0 |awk '{print $1}')",
      "esxcfg-vswitch -P vmnic3 -V $portid ${var.vcenter.vds.basename}-0",
      "portid=$(esxcfg-vswitch -l | grep -A4 ${var.vcenter.vds.basename}-1-VMotion | grep -A2 DVPort | grep -A1 vmnic1 | grep -v vmnic1 |awk '{print $1}')",
      "esxcfg-vswitch -P vmnic4 -V $portid ${var.vcenter.vds.basename}-1-VMotion",
      "portid=$(esxcfg-vswitch -l | grep -A4 ${var.vcenter.vds.basename}-2-VSAN | grep -A2 DVPort | grep -A1 vmnic2 | grep -v vmnic2 |awk '{print $1}')",
      "esxcfg-vswitch -P vmnic5 -V $portid ${var.vcenter.vds.basename}-2-VSAN"
    ]
  }
}