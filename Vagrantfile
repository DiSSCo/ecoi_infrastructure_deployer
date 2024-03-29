Vagrant.require_version ">= 2.0.0"

require 'json'
require 'getoptlong'
require 'net/http'

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
def create_keys_files(config_data,external_private_key_path,internal_private_key_path,internal_public_key_path)
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
    if !File.exist?(internal_public_key_path)
        shell_cmd = "ssh-keygen -y -f #{internal_private_key_path}"
        generated_key = %x[ #{shell_cmd} ]
        File.open(internal_public_key_path, "w") do |f|
          f.puts(generated_key)
        end
    end
end

def run_api_tests_on_server(config_data)
  # To-Do: Several variables (like AWS bucket name, handle prefix, etc.) should
  # be moved to a separate config file to avoid duplication (also defined in
  # file ansible/groupe_vars/all.yml)
  if !File.directory?('test_suite')
    Dir.mkdir('test_suite')
  end
  test_config_path = File.join('test_suite', 'config.properties')
  test_jar_path = File.join('test_suite', 'nsidr-api-tests-0.1-test-jar-with-dependencies.jar')
  junit_jar_path = File.join('test_suite', 'junit-platform-console-standalone.jar')
  File.open(test_config_path, 'w') do |f|
    cert_validation = 'true'
    if config_data['deployment']['environment'] == 'test'
      if config_data['deployment']['default_provider'] == 'virtualbox'
        cordra_nsidr_url = 'https://172.28.128.8'
        cordra_prov_url = 'https://172.28.128.7'
        cert_validation = 'false'
      elsif config_data['deployment']['default_provider'] == 'aws'
        cordra_nsidr_url = 'https://test.nsidr.org'
        cordra_prov_url = 'https://test.prov.nsidr.org'
      end
      cordra_nsidr_handle_prefix = 'test.20.5000.1025'
      cordra_prov_handle_prefix = 'test.prov.994'
    else
      cordra_nsidr_url = 'https://nsidr.org'
      cordra_nsidr_handle_prefix = '20.5000.1025'
      cordra_prov_url = 'https://prov.nsidr.org'
      cordra_prov_handle_prefix = 'prov.994'
    end
    cordra_user_name = 'admin'
    cordra_password = config_data['software']['cordra']['admin_password']
    cordra_doip_port = '9000'
    cordra_search_page_size = '10'

    f.puts('digitalObjectRepository.url=' + cordra_nsidr_url)
    f.puts('digitalObjectRepository.handlePrefix=' + cordra_nsidr_handle_prefix)
    f.puts('digitalObjectRepository.username=' + cordra_user_name)
    f.puts('digitalObjectRepository.password=' + cordra_password)
    f.puts('digitalObjectRepository.doipPort=' + cordra_doip_port)
    f.puts('digitalObjectRepository.searchPageSize=' + cordra_search_page_size)
    f.puts('provenanceRepository.url=' + cordra_prov_url)
    f.puts('provenanceRepository.handlePrefix=' + cordra_prov_handle_prefix)
    f.puts('provenanceRepository.username=' + cordra_user_name)
    f.puts('provenanceRepository.password=' + cordra_password)
    f.puts('provenanceRepository.doipPort=' + cordra_doip_port)
    f.puts('provenanceRepository.searchPageSize=' + cordra_search_page_size)
    f.puts('cert_validation=' + cert_validation)
  end
  if !File.exist?(test_jar_path)
    bucket_name = 'dissco-cordra-distributions'
    object_key = 'nsidr-api-tests-0.1-test-jar-with-dependencies.jar'
    region = config_data['software']['mongodb']['backup']['s3']['region']
    access_key_id = cordra_password = config_data['software']['general']['aws_access']['access_key_id']
    secret_access_key = config_data['software']['general']['aws_access']['secret_access_key']
    s3_client = Aws::S3::Client.new(
      region: region,
      credentials: Aws::Credentials.new(access_key_id, secret_access_key)
    )
    s3_client.get_object(
      response_target: test_jar_path,
      bucket: bucket_name,
      key: object_key
    )
  end
  if !File.exist?(junit_jar_path)
    Net::HTTP.start("repo1.maven.org", 443, use_ssl:true) do |http|
      resp = http.get("/maven2/org/junit/platform/junit-platform-console-standalone/1.7.2/junit-platform-console-standalone-1.7.2.jar")
      open(junit_jar_path, "wb") do |file|
        file.write(resp.body)
      end
    end
  end
  if config_data['deployment']['environment'] == 'test'
    intrusive_tests = 'true'
  else
    intrusive_tests = 'false'
  end
  shell_cmd = "java -Dconfig.path=#{test_config_path} -DintrusiveTests=#{intrusive_tests} " +
    "-jar #{junit_jar_path} -cp #{test_jar_path} --select-package eu.dissco.nsidr.testing"
  puts 'running command:'
  puts shell_cmd
  test_result = %x[ #{shell_cmd} ]
  puts 'Test results:'
  puts test_result
end

# Read config properties from config file
config_data = JSON.parse(File.read('config/config.json'))
deployment_type=config_data['deployment']['type']
provider = config_data['deployment']['default_provider']
deployment_environment = config_data['deployment']['environment']
# Since we define a subnet_id for the VMs, aws-sdk requires the security_groups
# to be passes with their IDs instead of name tags
aws_sg = {
  'ssh': 'sg-0100638bf5044bd52',
  'elk_server': 'sg-03b1bd88aadc7f924',
  'web_server': 'sg-04252c0b6177f0479',
  'cordra_server': 'sg-04b50bd157ad8b4ff',
  'mongodb_server': 'sg-0d26b81c844926313',
  'monitoring_agent': 'sg-0eaf617263763ee13',
  'image_detection_server': 'sg-0716ad8697ced2bed'
}

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
internal_public_key_path='keys/internal/public.key'

# Set ssh username depending on provider
if provider.casecmp?("virtualbox") then
    ssh_username="vagrant"
else
    ssh_username="ubuntu"
end


Vagrant.configure('2') do |config|

  config.vagrant.plugins = ["aws-sdk-s3", {"fog-ovirt" => {"version" => "1.0.1"}}, "vagrant-aws"]

  config.ssh.username = ssh_username

  # Trigger to be executed before vagrant up and in charge of creating in the host machines the authentication key files from data in the config file
  config.trigger.before [:up] do |trigger|
      trigger.name = "Creating key files from config file values"
      trigger.ruby do |env,machine|
        create_keys_files(config_data,external_private_key_path,internal_private_key_path,internal_public_key_path)
      end
  end

  # We disable vagrants default behavior which syncs the whole folder, instead
  # rsync only minimal needed (config) data: more for the ansible control node
  # (ie. cordra_nsidr_server) and less for the managed nodes
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Default configuration for virtualbox machines
  config.vm.provider "virtualbox" do |h, override|
    override.vm.box = "bento/ubuntu-20.04"
  end

  # Default configuration for AWS virtual machines
  config.vm.provider "aws" do |aws, override|
    override.vm.box = "aws-empty-box"
    override.ssh.private_key_path = './'+external_private_key_path

    aws.access_key_id = config_data['infrastructure']['aws']['access_key_id']
    aws.secret_access_key = config_data['infrastructure']['aws']['secret_access_key']
    aws.region = "eu-west-2"
    # Official Ubuntu 20.04 LTS (built 2021-04-30) AMI image from Canonical, no additional costs:
    aws.ami = "ami-0194c3e07668a7e36"
    aws.keypair_name = "jointdemo"
    aws.subnet_id = config_data['infrastructure']['aws']['subnet_id']
  end

  # Script that copies a ssh key to the guest machine so it can access and be accessible by the other guest machines (required for ansible to be able to run commands on them)
  $ssh_keys_script_control_node = <<-SCRIPT
    SSH_USERNAME=$1
    PRIVATE_KEY_PATH=$2
    cp $PRIVATE_KEY_PATH /home/$SSH_USERNAME/.ssh/id_rsa
    chmod 700 /home/$SSH_USERNAME/.ssh/id_rsa
  SCRIPT

  $ssh_keys_script_managed_node = <<-SCRIPT
    SSH_USERNAME=$1
    PUBLIC_KEY_PATH=$2
    cat $PUBLIC_KEY_PATH >> /home/$SSH_USERNAME/.ssh/authorized_keys
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
    SSH_USERNAME=$1
    MOUNT_SYNCED_FOLDER=$2
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install python3-pip
    export ANSIBLE_HOST_KEY_CHECKING=False
    chown -R $SSH_USERNAME $MOUNT_SYNCED_FOLDER
  SCRIPT

  # Provisioner that runs the script that copies the ssh keys to the guest machine
  config.vm.provision "setup_ssh_public_key", type: "shell" do |s_keys|
    s_keys.inline        = $ssh_keys_script_managed_node
    s_keys.args          = [ssh_username,mount_synced_folder+'/'+internal_public_key_path]
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
      monitoring_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

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
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:web_server]]
      end
  end


  # Definition of the virtual machine that will be hosting mongodb
  db_server_name = 'db_server'
  if deployment_environment.casecmp?("test") then
    db_server_name.prepend('test_')
  end
  config.vm.define db_server_name, autostart:true do |db_server|
      machine_name = db_server_name
      db_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

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
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:mongodb_server]]
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
      search_engine_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

      # Specific setup for this virtual machine when using the virtualbox provider
      search_engine_server.vm.provider "virtualbox" do |h, override|
        search_engine_server.vm.network "private_network", ip: "172.28.128.5", adapter: 2
        h.memory = 1536
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      search_engine_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.large'
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:elk_server]]
      end

  end


  # Definition of the virtual machine that will be hosting cordra ds viewer server
  ds_viewer_server_name = 'ds_viewer_server'
  if deployment_environment.casecmp?("test") then
    ds_viewer_server_name.prepend('test_')
  end
  config.vm.define ds_viewer_server_name, autostart:true do |ds_viewer_server|
      machine_name = ds_viewer_server_name
      ds_viewer_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

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
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:web_server]]
      end
  end


  # Definition of the virtual machine that will be hosting the plant organ detection service
  object_detection_server_name = 'object_detection_server'
  if deployment_environment.casecmp?("test") then
    object_detection_server_name.prepend('test_')
  end
  config.vm.define object_detection_server_name, autostart:true do |object_detection_server|
      machine_name = object_detection_server_name
      object_detection_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

      # Specific setup for this virtual machine when using the virtualbox provider
      object_detection_server.vm.provider "virtualbox" do |h, override|
        object_detection_server.vm.network "private_network", ip: "172.28.128.9", adapter: 2
        h.memory = 1024
        h.cpus = 1
      end

      # Specific setup for this virtual machine when using the aws provider
      object_detection_server.vm.provider :aws do |aws|
        aws.tags = {Name: machine_name}
        aws.instance_type= 't3.small'
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:image_detection_server]]
      end
  end


  # Definition of the virtual machine that will be hosting cordra provenance server
  cordra_prov_server_name = 'cordra_prov_server'
  if deployment_environment.casecmp?("test") then
    cordra_prov_server_name.prepend('test_')
  end
  config.vm.define cordra_prov_server_name, autostart:true do |cordra_prov_server|
      machine_name = cordra_prov_server_name
      cordra_prov_server.vm.synced_folder "keys/internal", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true, rsync__exclude: ["private.key"]

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
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:web_server],aws_sg[:cordra_server]]
      end
  end


  cordra_nsidr_server_name = 'cordra_nsidr_server'
  if deployment_environment.casecmp?("test") then
    cordra_nsidr_server_name.prepend('test_')
  end
  # Definition of the virtual machine that will be hosting cordra repository server
  config.vm.define cordra_nsidr_server_name, autostart:true do |cordra_nsidr_server|
      machine_name = cordra_nsidr_server_name
      # cordra_nsidr_server.vm.synced_folder ".", mount_synced_folder, type:"rsync", rsync__auto: true, rsync__exclude: [".git/","config/","keys/external/"]
      cordra_nsidr_server.vm.synced_folder "keys/internal/", mount_synced_folder + "/keys/internal", type:"rsync", rsync__auto: true
      cordra_nsidr_server.vm.synced_folder "ansible/", mount_synced_folder + "/ansible", type:"rsync", rsync__auto: true

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
        aws.security_groups = [aws_sg[:ssh],aws_sg[:monitoring_agent],aws_sg[:web_server],aws_sg[:cordra_server]]
      end

      # Provisioner that runs the script that copies the ssh keys to the guest machine
      cordra_nsidr_server.vm.provision "setup_ssh_access_key", type: "shell" do |s_keys|
        s_keys.inline        = $ssh_keys_script_control_node
        s_keys.args          = [ssh_username,mount_synced_folder+'/'+internal_private_key_path]
        s_keys.privileged    = false
      end

      # Provisioner that runs the script that installs ansible local in the guest machine
      cordra_nsidr_server.vm.provision "prepare_machine_for_ansible", type: "shell"  do |s_pre_ansible|
        s_pre_ansible.inline = $pre_ansible_script
        s_pre_ansible.args          = [ssh_username,mount_synced_folder]
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

      cordra_nsidr_server.trigger.after :provision do |trigger|
        trigger.name = "Run API tests on nsidr server"
        trigger.ruby do |env,machine|
          run_api_tests_on_server(config_data)
        end
      end

      if !provider.casecmp?("virtualbox") && !deployment_environment.casecmp?("test") then
        cordra_nsidr_server.trigger.before :destroy do |trigger|
          trigger.warn = "Deleting handle ids in handle server before destroying machine"
          trigger.run_remote = {inline: "/opt/cordra/bin/delete_handle_ids_from_handle_server.sh"}
        end
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
