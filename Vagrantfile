Vagrant.require_version ">= 2.0.0"

require 'json'
require 'getoptlong'

# Function that creates files for the private keys hold in config_data
def create_keys_files(config_data,external_private_key_path,internal_private_key_path)
    if !File.exist?(external_private_key_path) and !File.exist?(internal_private_key_path)
        File.open(external_private_key_path, "w") do |f|
          config_data['keys']['external_private_key'].each { |element| f.puts(element) }
        end
        File.open(internal_private_key_path, "w") do |f|
          config_data['keys']['internal_private_key'].each { |element| f.puts(element) }
        end
    end
end

# Read config properties from config file
config_data = JSON.parse(File.read('config/config.json'))
deployment_type=config_data['deployment']['type']
provider = config_data['deployment']['default_provider']

# Overwrite deploymentType and provider in case they are passed as parameters
opts = GetoptLong.new(
  [ '--provider', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--deployment-type', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--no-provision', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--provision', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '-c', GetoptLong::OPTIONAL_ARGUMENT ]
)
opts.each do |opt, arg|
  case opt
    when '--deployment-type'
      deployment_type=arg
    when '--provider'
      provider=arg
  end
end

# Set the vagrant defualt provider to the desired provider
ENV['VAGRANT_DEFAULT_PROVIDER'] = provider

mount_synced_folder='/vagrant'
external_private_key_path='keys/external/private.key'
internal_private_key_path='keys/internal/private.key'

# Set ssh username depending on provider
if provider.casecmp?("hyperv") then
    ssh_username="vagrant"
else
    ssh_username="ubuntu"
    create_keys_files(config_data,external_private_key_path,internal_private_key_path)
end


Vagrant.configure('2') do |config|

  config.vagrant.plugins = ["vagrant-openstack-provider",{"fog-ovirt" => {"version" => "1.0.1"}},"vagrant-aws"]

  config.ssh.username = ssh_username

  # Trigger to be executed before vagrant up and in charge of creating in the host machines the authentication key files from data in the config file
  config.trigger.before [:up] do |trigger|
      trigger.name = "Creating key files from config file values"
      trigger.ruby do |env,machine|
        create_keys_files(config_data,external_private_key_path,internal_private_key_path)
      end
  end

  # Default configuration for Hyper-v virtual machines
  config.vm.provider "hyperv" do |h, override|
    override.vm.box = "bento/ubuntu-18.04"
    override.vm.synced_folder ".", mount_synced_folder, type:"smb"
  end

  # Default configuration for AWS virtual machines
  config.vm.provider "aws" do |aws, override|
    override.vm.box = "FEBO/ubuntu18"
    override.ssh.private_key_path = './'+external_private_key_path
    override.vm.synced_folder ".", mount_synced_folder, type:"rsync", rsync__auto: true, rsync__exclude: [".git/","./config","./keys/external"]

    aws.access_key_id = config_data['infrastructure']['aws']['access_key_id']
    aws.secret_access_key = config_data['infrastructure']['aws']['secret_access_key']
    aws.region = "eu-west-2"
    aws.ami = "ami-04cc79dd5df3bffca"
    aws.keypair_name = "jointdemo"
  end

  # Default configuration for OpenStack virtual machines
  config.vm.provider "openstack" do |os, override|
    override.ssh.private_key_path = './'+external_private_key_path
    override.vm.synced_folder ".", mount_synced_folder, type:"rsync", rsync__exclude: [".git/","./config","./keys/external"]

    os.identity_api_version             = config_data['infrastructure']['openstack']['identity_api_version']
    os.openstack_auth_url               = config_data['infrastructure']['openstack']['auth_url']
    os.project_name                     = config_data['infrastructure']['openstack']['project_name']
    os.project_domain_name              = config_data['infrastructure']['openstack']['project_domain_name']
    os.username                         = config_data['infrastructure']['openstack']['username']
    os.user_domain_name                 = config_data['infrastructure']['openstack']['user_domain_name']
    os.password                         = config_data['infrastructure']['openstack']['password']
    os.region                           = config_data['infrastructure']['openstack']['region_name']
    os.interface_type					= config_data['infrastructure']['openstack']['interface']

    # For some reason the openstack returns the endpoint to manage the network with http but it needs https
    os.openstack_network_url			= config_data['infrastructure']['openstack']['network_url']

    # Common Openstack attributes for all machines
    os.image = 'Ubuntu Server 18.04.2'
    os.networks = [{'name': 'alexnet'}]
    os.keypair_name = 'jointdemo'
  end

  # Script that copies a ssh key to the guest machine so it can access and be accessible by the other guest machines (required for ansible to be able to run commands on them)
  $ssh_keys_script = <<-SCRIPT
    SSH_USERNAME=$1
    PRIVATE_KEY_PATH=$2
    cp $PRIVATE_KEY_PATH /home/$SSH_USERNAME/.ssh/id_rsa
    chmod 700 /home/$SSH_USERNAME/.ssh/id_rsa
    LINE=$(ssh-keygen -y -f /home/$SSH_USERNAME/.ssh/id_rsa)
    LINE="$LINE"
    FILE="/home/$SSH_USERNAME/.ssh/authorized_keys"
    grep -qF -- "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
  SCRIPT

  # Script to update the ansible inventory file with the ip assigned to the machine once it has been provisioned
  $update_inventory_script = <<-SCRIPT
    INVENTORY_FILE=$1
    MACHINE_NAME=$2
    SSH_USERNAME=$3
    LINE="$MACHINE_NAME $(echo 'ansible_host=')$(hostname -I)"
    LINE="$LINE"
    sed -i "s/$MACHINE_NAME ansible_host=.*/$LINE/g" "$INVENTORY_FILE"
    sed -i "s/ansible_ssh_user=.*/ansible_ssh_user=$SSH_USERNAME/g" "$INVENTORY_FILE"
  SCRIPT

  # Script to allow ssh with ufw
  $ufw_ssh_script = <<-SCRIPT
    apt-get update
    apt-get -y install ufw
    ufw allow ssh/tcp
    echo 'y' | ufw enable
    export ANSIBLE_HOST_KEY_CHECKING=False
  SCRIPT

  # Script to enable ssh with ufw
  $pre_ansible_script = <<-SCRIPT
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install python-pip
    export ANSIBLE_HOST_KEY_CHECKING=False
  SCRIPT

  # Provisioner that runs the script that copies the ssh keys to the guest machine
  config.vm.provision "setup_ssh_keys", type: "shell" do |s_keys|
    s_keys.inline        = $ssh_keys_script
    s_keys.args          = [ssh_username,mount_synced_folder+'/'+internal_private_key_path]
    s_keys.privileged    = false
  end

  # Provisioner that runs the script to enable ssh with ufw
  config.vm.provision "ufw_ssh", type: "shell" do |s_ufw_ssh|
    s_ufw_ssh.inline        = $ufw_ssh_script
  end

  if deployment_type.casecmp?("single") then
      # Definition of the virtual machine that will be hosting everything
      config.vm.define "cordra_nsidr_server", autostart:true do |cordra_nsidr_server|
           machine_name = 'cordra_nsidr_server'

          if !provider.casecmp?("hyperv") then
              cordra_nsidr_server.trigger.after [:up] do |trigger|
                trigger.info = "Updating ansible inventory in host machine with a vagrant triggger before provision"
                trigger.only_on = "cordra_nsidr_server"
                trigger.ruby do |env,machine|
                    path_inventory_file = './ansible/inventory.ini'
                    inventory_content = File.read(path_inventory_file)
                    inventory_content = inventory_content.gsub(/ansible_ssh_user=(.*)/,"ansible_ssh_user="+ssh_username)
                    cordra_nsidr_server_ip = %x(vagrant ssh cordra_nsidr_server -c "hostname -I")
                    inventory_content = inventory_content.gsub(/cordra_nsidr_server ansible_host=(.*)/, "cordra_nsidr_server ansible_host="+cordra_nsidr_server_ip)
                    File.open(path_inventory_file, "w") {|file| file.puts inventory_content }
                end
              end
          end

          # Specific setup for this virtual machine when using the hyper-v provider
          cordra_nsidr_server.vm.provider "hyperv" do |h|
            h.vmname = machine_name
            h.maxmemory = 4096
            h.memory = 2048
            h.cpus = 2
          end

          # Specific setup for this virtual machine when using the aws provider
          cordra_nsidr_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.large'
            aws.security_groups = ['ssh','nsidr_server_single_machine']
          end

          # Specific setup for this virtual machine when using the openstack provider
          cordra_nsidr_server.vm.provider :openstack do |os|
            os.server_name = machine_name
            os.flavor = 'm1.large'
            os.floating_ip = '131.251.172.22'
            os.security_groups = ['ssh','nsidr_server_single_machine']
          end

          # Provisioner that run the script that updates the ansible inventory with the IP assigned to this virtual machine
          cordra_nsidr_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end

          # Provisioner that runs the script that installs ansible local in the guest machine
          cordra_nsidr_server.vm.provision "prepare_machine_for_ansible", type: "shell"  do |s_pre_ansible|
            s_pre_ansible.inline = $pre_ansible_script
          end

          # Provisioner that will run the ansible playbook in the guest machine
          cordra_nsidr_server.vm.provision "ansible_local" do |ansible|
            ansible.verbose = true
            ansible.install_mode = "pip"
            ansible.version = "2.8.5"
            ansible.playbook = "ansible/site_single_machine.yml"
            ansible.inventory_path = "ansible/inventory.ini"
            ansible.config_file = "ansible/ansible.cfg"
            ansible.limit = "all"
            ansible.tags = config_data['deployment']['ansible_tags']
            ansible.extra_vars = {
              "server_user": ssh_username,
              "config": config_data['software']
            }
          end
      end
  else
      # Definition of the virtual machine that will be hosting the monitoring software like prometheus, kibana, grafana, etc.
      config.vm.define "monitoring_server", autostart:true do |monitoring_server|
          machine_name = 'monitoring_server'

          # Specific setup for this virtual machine when using the hyper-v provider
          monitoring_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 1536
            h.memory = 1024
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          monitoring_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.small'
            aws.security_groups = ['ssh','monitoring_agent','monitoring_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          monitoring_server.vm.provider :openstack do |os, override|
            os.server_name = machine_name
            os.flavor = 'm1.medium'
            os.floating_ip_pool = "public"
            os.security_groups = ['ssh','monitoring_agent','monitoring_server']
          end

          # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
          monitoring_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end
      end

      # Definition of the virtual machine that will be hosting mongodb
      config.vm.define "database_server", autostart:true do |database_server|
          machine_name = 'database_server'

          # Specific setup for this virtual machine when using the hyperv provider
          database_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 1536
            h.memory = 1024
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          database_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.small'
            aws.security_groups = ['ssh','monitoring_agent','mongodb_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          database_server.vm.provider :openstack do |os, override|
            os.server_name = machine_name
            os.flavor = 'm1.medium'
            os.floating_ip_pool = "public"
            os.security_groups = ['ssh','monitoring_agent','mongodb_server']
          end

          # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
          database_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end
      end

      # Definition of the virtual machine that will be hosting elasticsearch and logstash
      config.vm.define "search_engine_server", autostart:true do |search_engine_server|
          machine_name = 'search_engine_server'

          # Specific setup for this virtual machine when using the hyperv provider
          search_engine_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 2560
            h.memory = 1536
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          search_engine_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.medium'
            aws.security_groups = ['ssh','monitoring_agent','elk_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          search_engine_server.vm.provider :openstack do |os, override|
            os.server_name = 'search-engine-server'
            os.flavor = 'm1.large'
            os.image = 'Ubuntu Server 18.04.2'
            os.floating_ip_pool = "public"
            os.security_groups = ['ssh','monitoring_agent','elk_server']
          end

          # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
          search_engine_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end
      end

      # Definition of the virtual machine that will be hosting cordra provenance server
      config.vm.define "ds_viewer_server", autostart:true do |ds_viewer_server|
          machine_name = 'ds_viewer_server'

          # Specific setup for this virtual machine when using the hyper-v provider
          ds_viewer_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 1536
            h.memory = 1024
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          ds_viewer_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.small'
            aws.security_groups = ['ssh','monitoring_agent','web_server','rails_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          ds_viewer_server.vm.provider :openstack do |os, override|
            os.server_name = machine_name
            os.flavor = 'm1.medium'
            os.floating_ip_pool = "public"
            os.security_groups = ['ssh','monitoring_agent','web_server','rails_server']
          end

          # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
          ds_viewer_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end
      end

      # Definition of the virtual machine that will be hosting cordra provenance server
      config.vm.define "cordra_prov_server", autostart:true do |cordra_prov_server|
          machine_name = 'cordra_prov_server'

          # Specific setup for this virtual machine when using the hyper-v provider
          cordra_prov_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 1536
            h.memory = 1024
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          cordra_prov_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.small'
            aws.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          cordra_prov_server.vm.provider :openstack do |os, override|
            os.server_name = machine_name
            os.flavor = 'm1.medium'
            os.floating_ip_pool = "public"
            os.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
          end

          # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
          cordra_prov_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end
      end

      # Definition of the virtual machine that will be hosting cordra repository server
      config.vm.define "cordra_nsidr_server", autostart:true do |cordra_nsidr_server|
          machine_name = 'cordra_nsidr_server'

          if !provider.casecmp?("hyperv") then
            cordra_nsidr_server.trigger.after [:up] do |trigger|
              trigger.info = "Updating ansible inventory in host machine with a vagrant triggger after up"
              trigger.ruby do |env,machine|
                path_inventory_file = './ansible/inventory.ini'
                inventory_content = File.read(path_inventory_file)

                inventory_content = inventory_content.gsub(/ansible_ssh_user=(.*)/,"ansible_ssh_user="+ssh_username)

                monitoring_server_ip = %x{vagrant ssh monitoring_server -c "hostname -I"}
                inventory_content = inventory_content.gsub(/monitoring_server ansible_host=(.*)/, "monitoring_server ansible_host="+monitoring_server_ip)

                database_server_ip = %x{vagrant ssh database_server -c "hostname -I"}
                inventory_content = inventory_content.gsub(/db_server ansible_host=(.*)/, "db_server ansible_host="+database_server_ip)

                search_engine_server_ip = %x{vagrant ssh search_engine_server -c "hostname -I"}
                inventory_content = inventory_content.gsub(/search_engine_server ansible_host=(.*)/, "search_engine_server ansible_host="+search_engine_server_ip)

                cordra_prov_server_ip = %x{vagrant ssh cordra_prov_server -c "hostname -I"}
                inventory_content = inventory_content.gsub(/cordra_prov_server ansible_host=(.*)/, "cordra_prov_server ansible_host="+cordra_prov_server_ip)

                cordra_nsidr_server_ip = %x{vagrant ssh cordra_nsidr_server -c "hostname -I"}
                inventory_content = inventory_content.gsub(/cordra_nsidr_server ansible_host=(.*)/, "cordra_nsidr_server ansible_host="+cordra_nsidr_server_ip)

                File.open(path_inventory_file, "w") {|file| file.puts inventory_content }
              end
            end
          end

          # Specific setup for this virtual machine when using the hyper-v provider
          cordra_nsidr_server.vm.provider "hyperv" do |h, override|
            h.vmname = machine_name
            h.maxmemory = 1536
            h.memory = 1024
            h.cpus = 1
          end

          # Specific setup for this virtual machine when using the aws provider
          cordra_nsidr_server.vm.provider :aws do |aws|
            aws.tags = {Name: machine_name}
            aws.instance_type= 't3.small'
            aws.elastic_ip = '18.130.207.21'
            aws.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
          end

          # Specific setup for this virtual machine when using the openstack provider
          cordra_nsidr_server.vm.provider :openstack do |os|
            os.server_name = machine_name
            os.flavor = 'm1.medium'
            os.floating_ip = '131.251.172.22'
            os.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
          end

          # Provisioner that run the script that updates the ansible inventory with the IP assigned to this virtual machine
          cordra_nsidr_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
            s_inventory.inline        = $update_inventory_script
            s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
            s_inventory.privileged    = false
          end

          # Provisioner that runs the script that installs ansible local in the guest machine
          cordra_nsidr_server.vm.provision "prepare_machine_for_ansible", type: "shell"  do |s_pre_ansible|
            s_pre_ansible.inline = $pre_ansible_script
          end

          # Provisioner that will run the ansible playbook in the guest machine
          cordra_nsidr_server.vm.provision "ansible_local" do |ansible|
            ansible.verbose = true
            ansible.install_mode = "pip"
            ansible.version = "2.8.5"
            ansible.playbook = "ansible/site.yml"
            ansible.inventory_path = "ansible/inventory.ini"
            ansible.config_file = "ansible/ansible.cfg"
            # Anible limit could be "all" or for example "monitoring_servers,db_servers" to run the tasks that affect machines on those 2 groups
            ansible.limit = config_data['deployment']['ansible_limit']
            ansible.tags = config_data['deployment']['ansible_tags']
            ansible.extra_vars = {
              "server_user": ssh_username,
              "config": config_data['software']
            }
          end
      end
  end

end