//Code soruce: https://docs.microsoft.com/en-us/azure/developer/terraform/create-vm-cluster-with-infrastructure?fbclid=IwAR3XCDGgqcmK6slf4j-UuSaABNhAulVy1S6215F4JZrc_CGxPMPbiKkq3M0
resource "azurerm_resource_group" "main" {
  name     = "systemAdmin-Eksam"
  location = "West Europe"
}

output "west_europe" {
  value = azurerm_resource_group.main.location
}

provider "azurerm" {
    # The "feature" block is required for AzureRM provider 2.x.
    # If you're using version 1.x, the "features" block is not allowed.
    version = "~>2.0"
    features {}
}

variable "defaultName" {
  default = "Tryms"
}

variable "clusterCount" {
  type = number
  default = 3
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.defaultName}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "main" {
 name                         = "publicIPForLB"
 location                     = azurerm_resource_group.main.location
 resource_group_name          = azurerm_resource_group.main.name
 allocation_method            = "Static"
}

resource "azurerm_lb" "main" {
 name                = "loadBalancer"
 location            = azurerm_resource_group.main.location
 resource_group_name = azurerm_resource_group.main.name

 frontend_ip_configuration {
   name                 = "publicIPAddress"
   public_ip_address_id = azurerm_public_ip.main.id
 }
}

resource "azurerm_lb_backend_address_pool" "main" {
 resource_group_name = azurerm_resource_group.main.name
 loadbalancer_id     = azurerm_lb.main.id
 name                = "BackEndAddressPool"
}

resource "azurerm_network_interface" "main" {
  count               = var.clusterCount
  name                = "${var.defaultName}-nic${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_managed_disk" "main" {
 count                = var.clusterCount
 name                 = "datadisk_existing_${count.index}"
 location             = azurerm_resource_group.main.location
 resource_group_name  = azurerm_resource_group.main.name
 storage_account_type = "Standard_LRS"
 create_option        = "Empty"
 disk_size_gb         = "1023"
}

resource "azurerm_availability_set" "avset" {
 name                         = "avset"
 location                     = azurerm_resource_group.main.location
 resource_group_name          = azurerm_resource_group.main.name
 platform_fault_domain_count  = var.clusterCount
 platform_update_domain_count = var.clusterCount
 managed                      = true
}

resource "azurerm_virtual_machine" "main" {
  count                = var.clusterCount
  name                = "acctvm${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  availability_set_id   = azurerm_availability_set.avset.id
  network_interface_ids = [element(azurerm_network_interface.main.*.id, count.index)]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "myosdisk${count.index}"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

 # Optional data disks
 storage_data_disk {
   name              = "datadisk_new_${count.index}"
   managed_disk_type = "Standard_LRS"
   create_option     = "Empty"
   lun               = 0
   disk_size_gb      = "1023"
 }

 storage_data_disk {
   name            = element(azurerm_managed_disk.main.*.name, count.index)
   managed_disk_id = element(azurerm_managed_disk.main.*.id, count.index)
   create_option   = "Attach"
   lun             = 1
   disk_size_gb    = element(azurerm_managed_disk.main.*.disk_size_gb, count.index)
 }

 os_profile {
   computer_name  = "${var.defaultName}-machine"
   admin_username = "trymv"
   admin_password = "Trymv360!"
 }

 os_profile_linux_config {
   disable_password_authentication = false
 }

 tags = {
   environment = "staging"
 }
}