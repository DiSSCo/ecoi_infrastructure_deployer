Vagrant.require_version ">= 2.0.0"

require 'json'
require 'getoptlong'

# A change to the i18n package which was upgraded with Vagrant 2.2.7. causes an error running vagrant up
# As temportal workaround, we define the method except in the class Hash
class Hash
  def slice(*keep_keys)
    h = {}
    keep_keys.each { |key| h[key] = fetch(key) if has_key?(key) }
    h
  end unless Hash.method_defined?(:slice)
  def except(*less_keys)
    slice(*keys - less_keys)
  end unless Hash.method_defined?(:except)
end

# Function that creates files for the private keys hold in config_data
def create_keys_files(config_data,external_private_key_path,internal_private_key_path)
    if !File.exist?(external_private_key_path) and !File.exist?(internal_private_key_path)
        File.open(external_private_key_path, "w") do |f|
          config_data['keys']['external_private_key'].each { |element| f.puts(element) }
        end
        File.chmod(0600,external_private_key_path)
        File.open(internal_private_key_path, "w") do |f|
          config_data['keys']['internal_private_key'].each { |element| f.puts(element) }
        end
        File.chmod(0600,internal_private_key_path)
    end
end

# Read config properties from config file
config_data = JSON.parse(File.read('config/config.json'))
deployment_type=config_data['deployment']['type']
provider = config_data['deployment']['default_provider']
deployment_environment = config_data['deployment']['environment']

# Overwrite deploymentType and provider in case they are passed as parameters
opts = GetoptLong.new(
  [ '--provider', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--deployment-type', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--no-provision', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--provision', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--provision-with', GetoptLong::OPTIONAL_ARGUMENT ],
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
if provider.casecmp?("virtualbox") then
    ssh_username="vagrant"
else
    ssh_username="ubuntu"
    create_keys_files(config_data,external_private_key_path,internal_private_key_path)
end


Vagrant.configure('2') do |config|

  config.vagrant.plugins = [{"fog-ovirt" => {"version" => "1.0.1"}},"vagrant-aws"]

  config.ssh.username = ssh_username

  # Trigger to be executed before vagrant up and in charge of creating in the host machines the authentication key files from data in the config file
  config.trigger.before [:up] do |trigger|
      trigger.name = "Creating key files from config file values"
      trigger.ruby do |env,machine|
        create_keys_files(config_data,external_private_key_path,internal_private_key_path)
      end
  end

  # Default configuration for virtualbox machines
  config.vm.provider "virtualbox" do |h, override|
    override.vm.box = "bento/ubuntu-20.04"
    override.vm.synced_folder ".", mount_synced_folder, type:"rsync", rsync__auto: true, rsync__exclude: [".git/","/config/","/keys/external/"]
  end

  # Default configuration for AWS virtual machines
  config.vm.provider "aws" do |aws, override|
    override.vm.box = "FEBO/ubuntu20"
    override.ssh.private_key_path = './'+external_private_key_path
    override.vm.synced_folder ".", mount_synced_folder, type:"rsync", rsync__auto: true, rsync__exclude: [".git/","/config/","/keys/external/"]

    aws.access_key_id = config_data['infrastructure']['aws']['access_key_id']
    aws.secret_access_key = config_data['infrastructure']['aws']['secret_access_key']
    aws.region = "eu-west-2"
    aws.ami = "ami-04cc79dd5df3bffca"
    aws.keypair_name = "jointdemo"
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
    DEBIAN_FRONTEND=noninteractive apt-get -y install python3-pip
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


  # Definition of the virtual machine that will be hosting the monitoring software like prometheus, kibana, grafana, etc.
  monitoring_server_name = 'monitoring_server'
  if deployment_environment.casecmp?("test") then
    monitoring_server_name.prepend('test_')
  end
  config.vm.define monitoring_server_name, autostart:true do |monitoring_server|
      machine_name = monitoring_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      monitoring_server.vm.provider "virtualbox" do |h, override|
        monitoring_server.vm.network "private_network", ip: "172.28.128.3", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      monitoring_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        if !deployment_environment.casecmp?("test") then
          aws.elastic_ip = '18.130.121.175'
        end
        aws.security_groups = ['ssh','monitoring_agent','monitoring_server','web_server']
      end

      # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
      monitoring_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
        s_inventory.inline        = $update_inventory_script
        s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
        s_inventory.privileged    = false
      end
  end


  # Definition of the virtual machine that will be hosting mongodb
  db_server_name = 'db_server'
  if deployment_environment.casecmp?("test") then
    db_server_name.prepend('test_')
  end
  config.vm.define db_server_name, autostart:true do |db_server|
      machine_name = db_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      db_server.vm.provider "virtualbox" do |h, override|
        db_server.vm.network "private_network", ip: "172.28.128.4", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      db_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        aws.security_groups = ['ssh','monitoring_agent','mongodb_server']
      end

      # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
      db_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
        s_inventory.inline        = $update_inventory_script
        s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
        s_inventory.privileged    = false
      end

      if !provider.casecmp?("virtualbox") && !deployment_environment.casecmp?("test") then
        db_server.trigger.before :destroy do |trigger|
          trigger.warn = "Backing up database before destroying machine"
          trigger.run_remote = {inline: "/opt/mongodb_backup/mongodb-s3-backup.sh"}
        end
      end
  end


  # Definition of the virtual machine that will be hosting elasticsearch and logstash
  search_engine_server_name = 'search_engine_server'
  if deployment_environment.casecmp?("test") then
    search_engine_server_name.prepend('test_')
  end
  config.vm.define search_engine_server_name, autostart:true do |search_engine_server|
      machine_name = search_engine_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      search_engine_server.vm.provider "virtualbox" do |h, override|
        search_engine_server.vm.network "private_network", ip: "172.28.128.5", adapter: 2
        h.memory = 1536
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      search_engine_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.medium'
        aws.security_groups = ['ssh','monitoring_agent','elk_server']
      end

      # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
      search_engine_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
        s_inventory.inline        = $update_inventory_script
        s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
        s_inventory.privileged    = false
      end
  end


  # Definition of the virtual machine that will be hosting cordra ds viewer server
  ds_viewer_server_name = 'ds_viewer_server'
  if deployment_environment.casecmp?("test") then
    ds_viewer_server_name.prepend('test_')
  end
  config.vm.define ds_viewer_server_name, autostart:true do |ds_viewer_server|
      machine_name = ds_viewer_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      ds_viewer_server.vm.provider "virtualbox" do |h, override|
        ds_viewer_server.vm.network "private_network", ip: "172.28.128.6", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      ds_viewer_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        if !deployment_environment.casecmp?("test") then
          aws.elastic_ip = '18.130.207.21'
        end
        aws.security_groups = ['ssh','monitoring_agent','web_server','rails_server']
      end

      # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
      ds_viewer_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
        s_inventory.inline        = $update_inventory_script
        s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
        s_inventory.privileged    = false
      end
  end


  # Definition of the virtual machine that will be hosting cordra provenance server
  cordra_prov_server_name = 'cordra_prov_server'
  if deployment_environment.casecmp?("test") then
    cordra_prov_server_name.prepend('test_')
  end
  config.vm.define cordra_prov_server_name, autostart:true do |cordra_prov_server|
      machine_name = cordra_prov_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      cordra_prov_server.vm.provider "virtualbox" do |h, override|
        cordra_prov_server.vm.network "private_network", ip: "172.28.128.7", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      cordra_prov_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        if !deployment_environment.casecmp?("test") then
          aws.elastic_ip = '3.11.185.90'
        end
        aws.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
      end

      # Provisioner that runs the script that updates the ansible inventory with the IP assigned to this virtual machine
      cordra_prov_server.vm.provision "update_inventory", type: "shell" do |s_inventory|
        s_inventory.inline        = $update_inventory_script
        s_inventory.args          = [mount_synced_folder+'/ansible/inventory.ini',machine_name,ssh_username]
        s_inventory.privileged    = false
      end
  end


  cordra_nsidr_server_name = 'cordra_nsidr_server'
  if deployment_environment.casecmp?("test") then
    cordra_nsidr_server_name.prepend('test_')
  end
  # Definition of the virtual machine that will be hosting cordra repository server
  config.vm.define cordra_nsidr_server_name, autostart:true do |cordra_nsidr_server|
      machine_name = cordra_nsidr_server_name

      # Specific setup for this virtual machine when using the virtualbox provider
      cordra_nsidr_server.vm.provider "virtualbox" do |h, override|
        cordra_nsidr_server.vm.network "private_network", ip: "172.28.128.8", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      cordra_nsidr_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        if !deployment_environment.casecmp?("test") then
          aws.elastic_ip = '3.9.186.140'
        end
        aws.security_groups = ['ssh','monitoring_agent','web_server','cordra_server']
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
        ansible.install_mode = "pip_args_only"
        ansible.pip_args = "ansible==4.0.0"
        ansible.compatibility_mode = "2.0"
        ansible.playbook = "ansible/site.yml"
        ansible.inventory_path = "ansible/inventory.ini"
        ansible.config_file = "ansible/ansible.cfg"
        # Anible limit could be "all" or for example "monitoring_servers,db_servers" to run the tasks that affect machines on those 2 groups
        ansible.limit = config_data['deployment']['ansible_limit']
        ansible.tags = config_data['deployment']['ansible_tags']
        ansible.extra_vars = {
          "server_user": ssh_username,
          "software_config": config_data['software'],
          "deployment_config": config_data['deployment']
        }
        ansible.pip_install_cmd = "sudo apt-get install -y python3-distutils && curl -s https://bootstrap.pypa.io/get-pip.py | sudo python3"
      end

      if !provider.casecmp?("virtualbox") && !deployment_environment.casecmp?("test") then
        cordra_nsidr_server.trigger.before :destroy do |trigger|
          trigger.warn = "Deleting handle ids in handle server before destroying machine"
          trigger.run_remote = {inline: "/opt/cordra/bin/delete_handle_ids_from_handle_server.sh"}
        end
      end

      if !provider.casecmp?("virtualbox") then
        config.trigger.after [:up] do |trigger|
          trigger.info = "Updating ansible inventory in host machine with a vagrant trigger after up"
          trigger.ruby do |env,machine|
      			puts("Obtaining private ip for machine: #{machine.name}")
      			machine.communicate.execute('hostname -I') do |type, hostname_i|
      				puts("#{machine.name} ip = " + hostname_i.to_s)
      				path_inventory_file = './ansible/inventory.ini'
      				inventory_content = File.read(path_inventory_file)
      				inventory_content = inventory_content.gsub(/ansible_ssh_user=(.*)/,"ansible_ssh_user="+ssh_username)
              _machine_name = machine.name.to_s
              if deployment_environment.casecmp?("test") then
                _machine_name = _machine_name.delete_prefix("test_")
              end
      				inventory_content = inventory_content.gsub(/#{_machine_name} ansible_host=(.*)/, "#{_machine_name} ansible_host="+hostname_i)
      				File.open(path_inventory_file, "w") {|file| file.puts inventory_content }
            end
    			end
        end
      end

  end

end
