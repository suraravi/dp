# Getting Started #

## [Part 1 - Get some VMs](#get_vms) ##
*NOTE: Skip to [Part 2](#configure_vms) if you already have GO VM(s) and would like to restore start over*
1. Navigate to Manhattan's Global Orchestration (GO) site: https://go.manh.com/vcac/org/prod/
2. Log in with your MA domain account
3. Select Catalog
4. Select 'Request' in the "DM 2018 Component" box
5. Enter a description, select the number of Deployments.  DO NOT click Submit yet!!!
6. You will get two emails, one indicating the VM(s) were requested and other once built.
7. After you get the second email, click on items to find your new VMs
8. Expand the VM to see it's hostname - NOTE, these VMs are all created on the manhdev.com domain.


## [Part 2 - Configure your VMs (default sudo user is *wmsadmin/wmsadmin*)](#configure_vms) ##
1. ssh into your vm - `ssh wmsadmin@*vm name*.manhdev.com`
2. Fetch the setup script from git and make it executable.
```bash
curl --user readonly:readonly -G http://stash.us.manh.com/projects/RDDEVOPS/repos/docker-production/raw/prepare-vm.sh > prepare-vm.sh
chmod +x prepare-vm.sh
./prepare-vm.sh --cleanvols
```
*Note: the `--cleanvols` will erase your existing docker data-root - images, containers, swarm cluster, etc.*  
3. One of the steps in the `prepare-vm` script is to setup docker to run without sudo.  For this to take effect, you need to exit your ssh session and log back in.  Do that now so that you don't get any errors in the subsequent setps.
4. Repeat steps 1-4 above for each VM


## [Part 3 - Create the swarm cluster](#create_swarm_cluster) ##
Swarm uses Raft for leader election - See [raft overview](http://thesecretlivesofdata.com/raft/) for a great overview of how raft works.
1. ssh into your master node and run the following:

	```bash
	IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')
	docker swarm init --advertise-addr $IP --listen-addr $IP
	```

2. Get the worker and manager tokens to add nodes to the cluster.  For production you will want atleast three manager nodes, the rest can be worker nodes.
	* For **worker nodes**, run `docker swarm join-token worker` to get the token command and run it on each worker node in your cluster.
	* For **manager nodes**, run `docker swarm join-token manager` to get the token command and run it on each manager node in your cluster (not the one you ran swarm init on).


## [Part 4 - Clone the docker-production repo to run wm order streaming (you only need to do this on one MASTER node)](#clone_docker-production) ##
1. Clone it (NOTE that my command below uses readonly user, feel free to create a new ssh key and use that instead)
	`git clone http://readonly:readonly@stash.us.manh.com/scm/rddevops/docker-production.git`
2. cd into docker-production/wm
3. Create a **setenv.sh** file - `cp setenv.sh.template setenv.sh`.
4. Edit the **setenv.sh** file as needed.  You should be able to get by with just adding a value for the `DEPLOYMENT_SUFFIX` (e.g. pa or mjf) and setting the db connection details at the bottom.
5. A few of our services need to run on a specific node to access config files that are part of the repol cloned above.  Add the following labels to your manager node.  
```bash
docker node update --label-add manh.management=true $(hostname)
docker node update --label-add manh.config=true $(hostname)
docker node update --label-add manh.elastic=true $(hostname)
```
6. DM docker images are stored on the quay.io repository.  Becasue this is a public repository, you need to first log in to it before any images can be cloned.  Run the following command from your swarm maanger node (where you are running docker-production from):
	* `docker login -u="manhrd+rdverde" -p="75V0R0GTYLDBPMT9TL82APK2WKL5CXZPKCA6GTD9B0J9P2GXOELZU4NIB5GM5BVK" quay.io/manhrd`
7. Update your tags - the command below will set the tags for the WM components in setenv.sh to be the current, latest `ROLLING_OS_TAG` set in setenv.sh.  By default, `ROLLING_OS_TAG` is set to gold for master builds.  2017 builds would have `ROLLING_OS_TAG` set to 2017-maint-gold.  
	* `./update-tags.sh`
8. Point to a valid git repo.  Click [here](http://atlconf-01.us.manh.com:10000/display/~Mfoley/2017/12/07/Configuration+through+consul) to understand details of how we get configuration data into consul to be used by the components.  You will need to set `GIT_CONFIG_SERVER_URL` in setenv.sh.  
	* If using our dockerized gogs server (`STACK_LIST` includes git) :
	
	```
	export GIT_CONFIG_SERVER_URL=http://gogs:3080/NOT_PROD/WM.git
	export GIT_CONFIG_SERVER_SOURCE_ROOT=
	```

	* To point to our development repo:

	```
	export GIT_CONFIG_SERVER_URL=http://readonly:readonly@stash.us.manh.com/scm/dockyard/ma-cp-gogs.git
	export GIT_CONFIG_SERVER_SOURCE_ROOT=seed
	```
	*NOTES:*

		* you can also change the branch by setting GIT_CONFIG_SERVER_BRANCHES
		* Gogs is only intended to be used for NON-Produciton deployments.
	

## [Part 4 - Optional - Deploy dockerized SCPP WM (along with MDA and MIP)](#WEB-Stack) ##
For non production like environments, you can use the dockerized images for WM, MDA and MIP.  These images are part of the [scpp stack](stacks/scpp/docker-compose.yml).  The following additional updates to setenv.sh are needed if you are to deploy this stack.
1. Add scpp to the STACK_LIST in setenv.sh.  For example:
	`export STACK_LIST="loadbalancer config monitoring logging warehouse-mgmt git scpp"`
2. Uncomment the following export statements in setenv.sh.  This allows the components to talk directly to the WM SCPP service over swarm's overlay network.  This is needed becasue these components do not have wm's VIP (Virtual IP) hostname in their hosts file and it's most likely not in the DNS.

```
#################################################################################
# Uncomment these lines if WM is running inside a docker container and part of this same SWARM cluster.
## export WM_SWARM_HOST=wm
## export WM_SWARM_PORT=80
## export WM_SWARM_URL=http://${WM_SWARM_HOST}:${WM_SWARM_PORT}
## export WM_APP_URL=${WM_SWARM_URL}
## export LIST_OF_WM_JAVA_SERVERS=${WM_SWARM_HOST}:${WM_SWARM_PORT}
#################################################################################
```

## [Part 5 - Task Time Estimation Configuration](#ML-vol) ##
In order to properly configure the Task Time Estimation components, service labels will need to be applied to each host that will run a TTE component. 

```bash
docker node update --label-add manh.tte.prediction=true $(hostname)
docker node update --label-add manh.tte.training=true $(hostname)
docker node update --label-add manh.tte.maintenance=true $(hostname)
```

If all the TTE components are placed on a single host, no additional configuration is required. The volumes configured in the [wm stack](stacks/warehouse-mgmt/docker-compose.yml) will work. However, if the components are on multiple hosts, some additional volume configuration is required.

This command will create a docker volume called `tasktime-estimator-model-storage`, pointing to a remote NFS server and mounting the folder to `/mnt/tte`. It is important the `tasktime-estimator-model-storage` name stays the same, as the TTE components are looking for a volume with that name.

```bash
docker volume create --driver local \
    --opt type=nfs \
    --opt o=addr=192.168.1.1,rw \
    --opt device=:/mnt/tte \
    tasktime-estimator-model-storage
```

This command will need to be run on each host that houses a TTE component in order for them to properly share files.

## [Part 6 - Start your Stacks...](#UP) ##
1. Bring up the cluster `./manage.sh -c up` (type ./manage.sh --help for other options)
    * note that manage.sh is not very sophisticated (by design).  It's sole purpose is to bring up and down docker stacks so we want to leave the heavy lifting to docker.  With that said, there is definitly room for improvements depending on how much we want to automate.
2. Copy the host entry spooled out at the end of the manage.sh scripts execution into your hosts file.

## Custom Extensions ##
See here: [extensions.md](wm/stacks/extensions/extensions.md)

# [Endpoints](#endpoints) #
 ### All environment variables referenced below would come from your setenv.sh file. ####
## Sub-domain based access ##
#### The routing for these (and others) is handled through environment variables on the services that need to be exposed.  You can see this in the compose files and read about it in the docker-cloud haproxy documentation. ###

* WM - wm.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB__HTTP_PORT}
* MDA - mda.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB__HTTP_PORT}

* Kibana (log ui) - logs.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}

* Consul (kv store) - consul.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Active MQ Web UI - activemq.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Active MQ Broker - For active MQ broker URI from external apps (not running on the backend overlay network), use < #VM NAME# >:61616
* Grafana (metrics dashboard) -  grafana.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Portainer (management console) - portainer.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}

* DCOrder - dcorder.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* DC Allocation - dcallocation.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Work Release - workrelease.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Order Streaming - orderstream.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}
* Task Time Estimator - tasktime-estimator.${DEPLOYMENT_SUFFIX}.${EXTERNAL_DOMAIN}:${LB_HTTP_PORT}


# [Integrating with WM](#wm_integration) #
Please see our [configuration guide](http://atlconf-01.us.manh.com:10000/display/MMC/Manual+Deployment)
