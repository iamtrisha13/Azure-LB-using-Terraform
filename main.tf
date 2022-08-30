data "azurerm_client_config" "current" {}

# Resource group created
resource "azurerm_resource_group" "task-resource-group" {
  name     = "trisha-rg"
  location = "East US"
}

#virtual network created in above rg

resource "azurerm_virtual_network" "task-virtual-network" {
  name                = "trisha-vnet"
  resource_group_name = azurerm_resource_group.task-resource-group.name
  location            = azurerm_resource_group.task-resource-group.location
  address_space       = ["10.0.0.0/16"]
}

#created subnet in above vnet

resource "azurerm_subnet" "task-subnet" {
  name                 = "trisha-subnet"
  resource_group_name  = azurerm_resource_group.task-resource-group.name
  virtual_network_name = azurerm_virtual_network.task-virtual-network.name
  address_prefixes     = ["10.0.1.0/24"]
}

#craeting nsg 

resource "azurerm_network_security_group" "task-nsg" {
  name                = "trisha-nsg"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name

  security_rule {
    name                       = "test123"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# creating availability set for vms

resource "azurerm_availability_set" "task-availability-set" {
  name                = "trisha-aset"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name

}

# creating random keyvault id

resource "random_id" "kvname" {
  byte_length = 5
  prefix = "trisha"
}

# craeting keyvault

resource "azurerm_key_vault" "task-key-vault" {
  name                        = random_id.kvname.hex
  location                    = azurerm_resource_group.task-resource-group.location
  resource_group_name         = azurerm_resource_group.task-resource-group.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get", "Backup", "Delete", "List", "Purge", "Recover", "Restore", "Set",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}


# creating random admin_password

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  upper            = true
  lower            = true
  numeric          = true
}

#Create Key Vault Secret

resource "azurerm_key_vault_secret" "vmpassword" {
  name         = "vmpassword"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.task-key-vault.id
}

#created nic for the linux vm

resource "azurerm_network_interface" "task-nic-linux" {
  name                = "trisha-linux-nic"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.task-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# craeting nsg association with nic

resource "azurerm_network_interface_security_group_association" "task-linux-association" {
  network_interface_id      = azurerm_network_interface.task-nic-linux.id
  network_security_group_id = azurerm_network_security_group.task-nsg.id
}

# Data template Bash bootstrapping file

data "template_file" "linux-vm-cloud-init" {
  template = file("install_apache.sh")
}

#created linux vm

resource "azurerm_linux_virtual_machine" "task-linux-vm" {
  name                = "trisha-linux-vm"
  resource_group_name = azurerm_resource_group.task-resource-group.name
  location            = azurerm_resource_group.task-resource-group.location
  size                = "Standard_F2"
  admin_username      = "trisha"
  admin_password      = azurerm_key_vault_secret.vmpassword.value
  availability_set_id = azurerm_availability_set.task-availability-set.id
  custom_data         = base64encode(data.template_file.linux-vm-cloud-init.rendered)
  network_interface_ids = [
    azurerm_network_interface.task-nic-linux.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  disable_password_authentication = false
}

#created nic for windows vm

resource "azurerm_network_interface" "task-nic-windows" {
  name                = "trisha-windows-nic"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.task-subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

#creating nsg association with nic for windows

resource "azurerm_network_interface_security_group_association" "task-win-association" {
  network_interface_id      = azurerm_network_interface.task-nic-windows.id
  network_security_group_id = azurerm_network_security_group.task-nsg.id
}

#created windows vm

resource "azurerm_windows_virtual_machine" "task-windows-vm" {
  name                = "trisha-win-vm"
  resource_group_name = azurerm_resource_group.task-resource-group.name
  location            = azurerm_resource_group.task-resource-group.location
  size                = "Standard_F2"
  admin_username      = "trisha"
  admin_password      = azurerm_key_vault_secret.vmpassword.value
  availability_set_id = azurerm_availability_set.task-availability-set.id
  network_interface_ids = [
    azurerm_network_interface.task-nic-windows.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

# configuring iis on windows vm
resource "azurerm_virtual_machine_extension" "iis" {
  name                 = "install-iis"
  virtual_machine_id   = azurerm_windows_virtual_machine.task-windows-vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
    { 
      "commandToExecute": "powershell Add-WindowsFeature Web-Asp-Net45;Add-WindowsFeature NET-Framework-45-Core;Add-WindowsFeature Web-Net-Ext45;Add-WindowsFeature Web-ISAPI-Ext;Add-WindowsFeature Web-ISAPI-Filter;Add-WindowsFeature Web-Mgmt-Console;Add-WindowsFeature Web-Scripting-Tools;Add-WindowsFeature Search-Service;Add-WindowsFeature Web-Filtering;Add-WindowsFeature Web-Basic-Auth;Add-WindowsFeature Web-Windows-Auth;Add-WindowsFeature Web-Default-Doc;Add-WindowsFeature Web-Http-Errors;Add-WindowsFeature Web-Static-Content;"
    } 
SETTINGS
}

#creating public ip for lb

resource "azurerm_public_ip" "task-public-ip-lb" {
  name                = "trishaPublicIPForLB"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name
  allocation_method   = "Static"
}

# creating lb

resource "azurerm_lb" "task-load-balancer" {
  name                = "trishaloadbalancer"
  location            = azurerm_resource_group.task-resource-group.location
  resource_group_name = azurerm_resource_group.task-resource-group.name

  frontend_ip_configuration {
    name                 = "frontendip"
    public_ip_address_id = azurerm_public_ip.task-public-ip-lb.id
  }
}

# craeting health probe

resource "azurerm_lb_probe" "task-health-probe" {
  loadbalancer_id = azurerm_lb.task-load-balancer.id
  name            = "trisha-probe"
  port            = 80
}


#creating lb rule

resource "azurerm_lb_rule" "example" {
  loadbalancer_id                = azurerm_lb.task-load-balancer.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontendip"
  backend_address_pool_ids = azurerm_lb_backend_address_pool.task-backend-pool.id[*]
  probe_id = azurerm_lb_probe.task-health-probe.id
}

#creating backend pool

resource "azurerm_lb_backend_address_pool" "task-backend-pool" {
  loadbalancer_id = azurerm_lb.task-load-balancer.id
  name            = "BackEndAddressPool"
}

# creating backend pool association for windows

resource "azurerm_network_interface_backend_address_pool_association" "task-backend-pool-association-win" {
  network_interface_id    = azurerm_network_interface.task-nic-windows.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.task-backend-pool.id
}

# creating backend pool association for linux

resource "azurerm_network_interface_backend_address_pool_association" "task-backend-pool-association-linux" {
  network_interface_id    = azurerm_network_interface.task-nic-linux.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.task-backend-pool.id
}

output "vm_password" {
  value = azurerm_key_vault_secret.vmpassword.value
  sensitive = true
}

output "backend-pool-id" {
  value = azurerm_lb_backend_address_pool.task-backend-pool.id
}