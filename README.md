# README

Vagrant project to automatize the deployment of the DiSSCo digital object repository infrastructure

## 1. Pre-requisites
- Vagrant (https://www.vagrantup.com/downloads.html)
- Rsync (https://www.vagrantup.com/docs/synced-folders/rsync.html). On Windows can be installed with Cygwin (https://cygwin.com/install.html)

## 2. Configuration
1. Copy the file ```config/config_template.json``` as ```config/config.json``` and edit its values to match your deployment.
This file will contain:
    - The passwords to be used when setting up the different applications (cordra, mongodb, elk, etc.)
    - The provider of the virtual machines (aws, virtualbox) and the deployment environment (prod/test/dev, see more below)
    - Credentials to connect to the cloud provider (aws) in "infrastructure->aws". AWS credentials must also be provided in "software->general->aws_access", these should be from an accound that only has the permission to interact with S3 (download Cordra software & upload backup)
    - The internal and external private keys to be installed in the virtual machines, so ansible can run commands on them.    

2. Configuration about the specifications of the different VMs (type, IPs, etc.) are defined in the Vagrant file

3. Configuration of the different applications to be install in the VMs, like what version of the applications we use or on
what ports they will be listening can be edited inside the ansible variables files (eg: ansible/group_vars/all.yml)

4. Copy the cordra_privatekey to be used by the Cordra instance to communicate with the handle server (http://hdl.handle.net/)
into the directory **ansible/roles/cordra/files/cordra/cordra_nsidr_server/**

## 2. Separating production, test and dev environment
Test and production environments are ought to be on AWS, dev environment locally on your machine with the VM software Virtualbox. You need the following configuration:

#### For Production:
```json
{
  "deployment":{
    "environment": "production",
    "domain_prefix": "",
    "default_provider": "aws",
    "..."
  }
}
```

#### For test:
```json
{
  "deployment":{
    "environment": "test",
    "domain_prefix": "test.",
    "default_provider": "aws",
    "..."
  }
}
```

#### For local dev:
For the dev environment on your local machine make sure you have [Virtualbox](https://www.virtualbox.org/wiki/Downloads) installed.
```json
{
  "deployment":{
    "environment": "test",
    "default_provider": "virtualbox",
    "..."
  }
}
```
For the local setup to work a host-only network is needed. For this open the Virtualbox application, go to "File -> Host-only network manager" and create an adapter with the name "vboxnet0" and the following configuration:

- IPv4 Address: 172.28.128.1
- IPv4 Mask: 255.255.255.0
- DHCP not enabled

Then, copy the whole content of the file config/local_dev_inventory.ini and use it to replace the content of ansible/inventory.ini. With this you have a default configuration for the IP addresses of the VMs. You can skip the next step and start the setup directly with ```vagrant up```

If any of the configuration above conflicts with your host machine config, you can adjust the IP addresses to your need and update the changes in the Vagrantfile.

#### Note:
After creation of the VMs, Vagrant stores the information related to the instances in the .vagrant/ folder. Therefore, when you change the deployment environment you have to delete the .vagrant/ folder.


## 3. Provision and execution on AWS
1. Modify the files  ```config/config.json```, ```Vagrantfile``` and ```ansible/group_vars/all``` to match your deployment

2. Make sure that in your desired cloud provider you have set up the following aspects and they are available for the credentials that
vagrant will use to connect to that cloud provider:
    - the public key pair configured in the desired ***provider-region***
    - the security groups
    - elastic/public IPs    

3. Open an admin command line console in your machine. Vagrant always requires a 'box' to run, even though in the case of aws provider all configuration can be given in the Vagrantfile. Run `vagrant box add aws-empty-box https://github.com/mitchellh/vagrant-aws/raw/master/dummy.box` to install the dummy box on your machine.

4. Now, the further process is different for production and test:

###### Note:
If an error occurs when Vagrant trys to auto-install the specified plugins, try to install them manually from the command line, i.e. run `vagrant plugin install fog-ovirt --plugin-version 1.0.1 && vagrant plugin install aws-sdk-s3 && vagrant plugin install vagrant-aws`

#### Production environment:
1. Go to the folder where the vagrant file is and run the command ```vagrant up --no-provision``` for creating the machines in the cloud provider
and updating the ansible/inventory.ini with their private IPv4 IPs. After that run ```vagrant reload --provision``` so all the provisioners will be executed
including the ansible provisioner inside the cordra_nsidr_server that is responsible to install all the software in the VMs
Note: This Vagrantfile won't work if we try to execut it inside a Linux VM running on Hyper-V on a windows host, because can't change permissions
of private ssh keys

#### Test environment:
The problem is that now Elastic IPs are defined for the test environment and the public IPv4 addresses of the machines change on every reboot. Therefore:

1. Go to the folder where the vagrant file is and run the following command to create and provision the machines (without the VM that functions as ansible control node)
```
vagrant up test_monitoring_server test_db_server test_search_engine_server test_ds_viewer_server test_cordra_prov_server
```
2. The run ```vagrant up --no-provision test_cordra_nsidr_server```
3. Make sure the values of the private IPv4 addresses are correct in ansible/inventory.ini
4. Manually set the routes for test.nsidr.org, test.prov.nsidr.org, test.demo.nsidr.org, test.monitoring.nsidr.org to the corresponding public IP addresses in AWS
5. Run ```vagrant rsync test_cordra_nsidr_server``` to sync the folder (with the updated IPv4 addresses) because otherwise vagrant only syncs upon restarting the VM
5. Run ```vagrant provision test_cordra_nsidr_server``` to execute the ansible script which installs the software.


#### Restoring data from the backup:
By default no data is restored after the deployment - a fresh install. If desired, the data can be restored automatically after the setup is finished from the AWS backup with the following configuration:
```json
{
  "deployment":{
    "restore_db_backup_after_setup": true
    "..."
  }
}
```
If the servers are running already and the ansible script should only restore the data from the backup and nothing else, put the following config:
```json
{
  "deployment":{
    "restore_db_backup_after_setup": true,
    "ansible_tags": ["restore_backup"]
    "..."
  }
}
```

#### Finally
Check that all the services are up and running correctly. To see the list of the services running in each machine have a look at
docs/ECOIS_subcomponents_deployment_diagram.pdf


### Side note: Starting vagrant from a new host computer (while VMs are running)
If you copy this repository and want to execute a command like `vagrant provision monitoring_server` (while the VM is running on AWS) Vagrant will return the error "Instance is not created" because it cannot connect to the VM. This is because the .vagrant folder is ignored in the github repository. To make Vagrant understand that the VMs are actually already running on AWS and know where to find them (so that Vagrant does not create new instances), the following workaround must be applied (only once at the beginning):
```bash
# Initially run from the root of this directory (make sure you created the config as described above 2.)
vagrant status
# This will return that no instances are created yet
# However, this also creates the .vagrant directory with the structure we need
```
We now need the Instance-IDs of all virtual machines running on AWS. You can either extract them from the Web interface or if you have the [AWS-cli](https://aws.amazon.com/de/cli/) installed with this command: `aws ec2 describe-instances --query "Reservations[*].Instances[*].{Instance:InstanceId,Name:Tags[?Key=='Name']|[0].Value}"`. Instance-IDs usually start with 'i-0...'

Then, for each of the VMs run (replace with the correct Instance-ID)
```bash
echo i-0INSTANCEID_MONITORING > .vagrant/machines/monitoring_server/aws/id
echo i-0INSTANCEID_NSIDR > .vagrant/machines/cordra_nsidr_server/aws/id
# ... and so on for all 6 VMs with the names given by vagrant status
# If your are working on the test environment, use the 'test_' prefix e.g.
echo i-0INSTANCEID_NSIDR > .vagrant/machines/test_cordra_nsidr_server/aws/id
```
Run `vagrant status` again to verify that Vagrant detects the VMs correctly and displays their status as 'running'. You can now run other Vagrant command to manage these VMs. For rsync and ssh access to work it might be necessary to run `vagrant reload` to completely synchronize Vagrant with the current state of the VM.


## 4. Updating Handle records
Once the cordra instance inside the cordra_nsidr_server is running and its initial configuration and objects have been created
through the ansible script, we should update the handle records when the service is set up using a domain (eg: nsidr.org)
To do so, log in as "admin" and go to Admin->Handle Records and there click in the button Update All Handles

## 5. Digitise some Digital Specimen from DWC-A
 We can use the java project openDS_CRUD_operator https://github.com/DiSSCo/openDS_CRUD_operator to digitise specimen describe in dwc-a files
 obtained from gbif like https://www.dropbox.com/s/36ni250j6iryf0x/0034622-190918142434337_Pygmaepterys_pointieri.zip?dl=0

 After running the digitiser, we should not only have digital specimen in the codra_nsidr instance but also provenance records
 in the cordra_prov instance. As well as if codra_nsidr was set with a domain name, being able to resolve the digital specimens
 with http://hdl.handle.net/

## 6. Adding new CORDRA instances.
If we want to add a new CORDRA instance, for example for CDIDR, we need to do the following:
- Edit ```Vagrantfile``` to add configuration for the new VM
- Edit ```ansible\inventory.ini``` to add new line for the new server under the section called cordra_servers
- Edit ```ansible\group_vars\all.yml``` to add information of new Cordra instance (handle_prefix, db_name, index_name, etc )
- Edit ```ansible\roles\basic\main.yml``` to include in the task "Copying certificates" the certificate of the new server
- Edit ```ansible\roles\prometheus\templates\prometheus\prometheus.yml.j2``` to add as new target for node and blackbox exporters the new VM
- Edit ```ansible\roles\logstash\templates\logstash\cordra_pipeline.conf.j2``` to include the certificate of the new VM in the input.beats.ssl_certificate_authorities
- Edit ```ansible\roles\mongodb\templates\mongodb\initial_setup.js.j2``` to create the db for the new Cordra instance  
- Create new folder ```ansible\roles\cordra\files\NEW_CORDRA_INSTANCE``` and set the handle keys (cordra_publickey and cordra_privatekey)
- Create new folder ```ansible\roles\cordra\templates\NEW_CORDRA_INSTANCE``` and set repoInit.json.j2 and the initial_data.json.j2
- Under ```ansible\roles\grafana\templates\datasources``` create datasources for connecting to Cordra_Elasticsearch index and Cordra logstash index
- Under ```ansible\roles\grafana\templates\dashboards``` create new dashboard for showing object information of new Cordra instance    

### Funding
This code was created to deploy the dsviewer demonstrator onto a Virtual Machine, as part of the ICEDIG project
https://icedig.eu/ ICEDIG a DiSSCo Project H2020-INFRADEV-2016-2017 – Grant Agreement No. 777483 Funded by the Horizon
2020 Framework Programme of the European Union
