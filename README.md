# README

Vagrant project to automatize the deployment of the DiSSCo digital object repository infrastructure 

## 1. Pre-requisites
- Vagrant (https://www.vagrantup.com/downloads.html)
- Rsync (https://www.vagrantup.com/docs/synced-folders/rsync.html). On Windows can be installed with Cygwin (https://cygwin.com/install.html)

## 2. Configuration
1. Copy the file ```config/config_template.json``` as ```config/config.json``` and edit its values to match your deployment. 
This file will contain:
    - The passwords to be used when setting up the different applications (cordra, mongodb, elk, etc.)
    - The type of deployment (simple or distributed) and the default cloud provider (aws, openstack, hyperv) 
    - Credentials to connect to the cloud provider (openstack, aws, etc). 
    - The internal and external private keys to be installed in the virtual machines, so ansible can run commands on them.    

2. Configuration about the specifications of the different VMs (type, IPs, etc.) are defined in the Vagrant file

3. Configuration of the different applications to be install in the VMs, like what version of the applications we use or on 
what ports they will be listening can be edited inside the ansible variables files (eg: ansible/group_vars/all.yml) 

## 2. Provision and execution 
1. Modify the files  ```config/config.json```, ```Vagrantfile``` and ```ansible/group_vars/all``` to match your deployment
 
2. Make sure that in your desired cloud provider you have set up the following aspects and they are available for the credentials that
vagrant will use to connect to that cloud provider:
    - the public key pair configured in the desired ***provider-region***
    - the security groups
    - elastic/public IPs    
 
3. Open an admin command line console in your machine
 
4. Go to folder where the vagrant file and run the command ```vagrant up --no-provision``` for creating the machines in the cloud provider 
and updating the ansible/inventory.ini with their ips. After that run ```vagrant reload --provision``` so all the provisioners will be run
including the ansible provisioner that will run in the cordra_nsidr_server which is responsible to install all the software in the VMs

## 3. Adding new CORDRA instances.
If we want to add a new CORDRA instance, for example for CDIDR, we need to do the following:
- Edit ```Vagrantfile``` to add configuration for new VM
- Edit ```ansible\inventory.ini``` to add new line for the new server under the section called cordra_servers
- Edit ```ansible\group_vars\all.yml``` to add information of new Cordra instance (handle_prefix, db_name, index_name, etc )
- Edit ```ansible\roles\basic\main.yml``` to include in the task "Copying certificates" the certificate of the new server
- Edit ```ansible\roles\prometheus\templates\prometheus\prometheus.yml.j2``` to add as new target for node and blackbox exporters the new VM
- Edit ```ansible\roles\logstash\templates\logstash\cordra_pipeline.conf.j2``` to include the certificate of the new VM in the input.beats.ssl_certificate_authorities
- Edit ```ansible\roles\mongodb\templates\mongodb\initial_setup.js.j2``` to create the db for the new Cordra instance  
- Create new folder ```ansible\roles\cordra\files\NEW_CORDRA_INSTANCE``` and set the handle keys and the initial_data.json
- Create new folder ```ansible\roles\cordra\templates\NEW_CORDRA_INSTANCE``` and set repoInit.json.j2 
- Under ```ansible\roles\grafana\templates\datasources``` create datasources for connecting to Cordra_Elasticsearch index and Cordra logstash index
- Under ```ansible\roles\grafana\templates\dashboards``` create new dashboard for showing object information of new Cordra instance    

### Funding
This code was created to deploy the dsviewer demonstrator onto a Virtual Machine, as part of the ICEDIG project 
https://icedig.eu/ ICEDIG a DiSSCo Project H2020-INFRADEV-2016-2017 – Grant Agreement No. 777483 Funded by the Horizon 
2020 Framework Programme of the European Union