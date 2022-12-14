resource "dns_a_record_set" "esxi" {
  depends_on = [vsphere_virtual_machine.dns_ntp]
  count = (var.dns_ntp.create == true ? length(var.vcenter.vds.portgroup.management.esxi_ips) : 0)
  zone  = "${var.dns.domain}."
  name  = "${var.esxi.basename}${count.index + 1}"
  addresses = [element(var.vcenter.vds.portgroup.management.esxi_ips, count.index)]
  ttl = 60
}

resource "dns_a_record_set" "nsx" {
  depends_on = [vsphere_virtual_machine.dns_ntp]
  count = var.dns_ntp.create == true && var.nsx.manager.create == true ? 1 : 0
  zone  = "${var.dns.domain}."
  name  = "${var.nsx.manager.basename}"
  addresses = [var.vcenter.vds.portgroup.management.nsx_ip]
  ttl = 60
}

resource "dns_cname_record" "nsx_cname" {
  depends_on = [dns_a_record_set.nsx, vsphere_virtual_machine.dns_ntp]
  zone  = "${var.dns.domain}."
  name  = "nsx"
  cname = "${var.nsx.manager.basename}.${var.dns.domain}."
  ttl   = 300
}

resource "dns_ptr_record" "esxi" {
  depends_on = [vsphere_virtual_machine.dns_ntp]
  count = (var.dns_ntp.create == true ? length(var.vcenter.vds.portgroup.management.esxi_ips) : 0)
  zone = "${var.dns_ntp.bind.reverse}.in-addr.arpa."
  name = split(".", element(var.vcenter.vds.portgroup.management.esxi_ips, count.index))[3]
  ptr  = "${var.esxi.basename}${count.index + 1}.${var.dns.domain}."
  ttl  = 60
}

resource "dns_a_record_set" "vcenter" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  depends_on = [vsphere_virtual_machine.dns_ntp]
  zone  = "${var.dns.domain}."
  name  = var.vcenter.name
  addresses = [var.vcenter.vds.portgroup.management.vcenter_ip]
  ttl = 60
}

resource "dns_cname_record" "vcenter_cname" {
  depends_on = [dns_a_record_set.vcenter, vsphere_virtual_machine.dns_ntp]
  zone  = "${var.dns.domain}."
  name  = "vcenter"
  cname = "${var.vcenter.name}.${var.dns.domain}."
  ttl   = 300
}

resource "dns_ptr_record" "vcenter" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  depends_on = [vsphere_virtual_machine.dns_ntp]
  zone = "${var.dns_ntp.bind.reverse}.in-addr.arpa."
  name = split(".", var.vcenter.vds.portgroup.management.vcenter_ip)[3]
  ptr  = "${var.vcenter.name}.${var.dns.domain}."
  ttl  = 60
}