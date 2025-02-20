#  soulTec Deployment Appliance aka soulDeploy!

## Project Goal

- Automatisiertes Deployment von ESXi inkl Grundkonfiguration
- Packetierte Appliance (PhotonOS based, Installation beim Kunden via OVA)


## Tech

Die Appliance basiert auf PhotonOS und beinhaltet (goVIA)[https://github.com/maxiepax/go-via] als docker-container

goVIA stellt ein WebUI zur Verfügung. Nebst dem ist der goVIA Container dhcp und tfpd server.


## Architecture

tbd

## Open Tasks

Please see: https://linear.app/soultec/project/soultec-deployment-appliance-a273c6e54bec/overview


### Test Instanz:

goVIA ist als docker container auf einer photonOS prepacked.



**goVIA**
https://10.177.176.17:8443/
admin  / defaul-lab-PW

SSH: root / 2x default-lab-PW

**Docker**
/srv/stag/govia/docker

1x compose file (/srv/stag/govia/docker/docker-compose.yaml)

**INFOS** -> https://10.177.176.17:8443/help