#!/bin/bash

echo
echo "This script is used to deploy several services in Google Cloud (GCP),"
echo "install Docker on a VM, push the Spring Petclinic app image to the Artifact Registry,"
echo "and run the app in a Docker container on the VM."
echo

sleep 2

function check_gcloud() {

    echo
    echo "======= Checking if you have install 'gcloud'... ======="
    echo
    which gcloud

    if [[ $? -gt 0 ]]; then
        echo "Haven't found gcloud."
        echo "Install it (e.g. for macOS run '') and then come back"
    else
        echo "All correct!"
    fi

    sleep 2

}


function create_vpc_subnet() {

    echo
    echo "======= Create a VPC network. ======="
    echo


    while true; do
        echo -n "- Enter the name of the network (e.g. mbnet): "
        read net_name

        gcloud compute networks describe "$net_name" > /dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            echo "Network '$net_name' is already exists, please choose another one."
        else
            break
        fi
    done

    echo -n "- Region name (e.g. europe-central2): "
    read region

    echo "- Choose the name of the GCP project from the list bellow "
    echo "------------------------"
    gcloud projects list --format="value(name)"
    echo "------------------------"
    echo -n "Your choice is: "
    read gcp_project

    echo -n "- Enter a subnet-mode (custom or auto): "
    read sub_mode


    echo -n "- Enter the value of MTU (1460, 1500, 8896): "
    read mtu_val

    echo -n "- BGP routing mode (regional or global): "
    read route_mode


    echo
    echo "Creating VPC \"${net_name}\" ..."
    echo

    gcloud compute networks create $net_name --project=$gcp_project \
        --subnet-mode=$sub_mode --mtu=$mtu_val \
        --bgp-routing-mode=$route_mode \
        --bgp-best-path-selection-mode=legacy



    if [[ $sub_mode == "custom" ]]; then
        echo
        echo "===================================="
        echo "Custom subnet mode has been selected. Let's create a custom subnet:"
        echo -n "- Enter the name of your subnet (e.g. mbsubnet1): "
        read sub_name

        echo -n "- Enter the range of your subnet (e.g. 10.0.0.0/24): "
        read sub_range

        echo
        echo "Creating Subnet \"${sub_name}\" ..."
        echo

        gcloud compute networks subnets create $sub_name \
            --project=$gcp_project \
            --range=$sub_range \
            --stack-type=IPV4_ONLY \
            --network=$net_name \
            --region=$region
    else
        sub_name="default"
        echo
        echo "Auto subnet mode has been selected. Subnets have been created in each region."
        echo "Default Subnet name is \"${sub_name}\"."
    fi

    sleep 2
}


function create_firewall_rules() {

    echo
    echo "======= Create firewall rules for the network \"${net_name}\". ======="
    echo

    while true; do

        echo
        echo -n "Create a new rule for the network "${net_name}"? (y or n): "
        read option

        while [[ "$option" != "y" && "$option" != "n" ]]; do
            echo -n "--- Create new rule for the network "${net_name}"? (y or n): "
            read option
            if ! [[ "$option" != "y" && "$option" != "n" ]]; then
                echo "Please enter "y" for creating new rule or "n" for opposite."
            fi
        done

        if [[ $option == "n" ]]; then
            break
        fi

        echo
        echo "*** NEW RULE CREATION ***"

        echo -n "- Enter the name of the new rule: "
        read rule_name

        echo -n "- Enter the type of direction (INGRESS or EGRESS): "
        read rule_type

        echo -n "- Enter the priority rule (from 0 to 65535): "
        read rule_prior

        echo -n "- Enter source ranges (e.g. 10.0.0.0/24 - only CIDR format): "
        read source_range

        echo -n "- Enter action value (ALLOW or DENY): "
        read action_val

        echo -n "- Enter specific rules, for example TCP/UDP (e.g. \"tcp:55,udp:55\" or \"all\"): "
        read spec_rules

        echo
        echo "Creating a firewall-rule for \"${net_name}\" ..."
        echo

        if [[ $option == "y" ]]; then
            gcloud compute firewall-rules create $rule_name \
                --project=$gcp_project \
                --network=projects/$gcp_project/global/networks/$net_name \
                --direction=$rule_type \
                --priority=$rule_prior \
                --source-ranges=$source_range \
                --action=$action_val \
                --rules=$spec_rules 
        fi

        echo
        echo "==================================================="
        echo "Current firewall rules for the network \"$net_name\":"
        echo "---------------------------------------------------"
        echo
        gcloud compute firewall-rules list --quiet --filter="network:$net_name"
        echo
        echo "==================================================="
    done

    sleep 2

}


function create_dock_artif_registry() {

    echo
    echo "======= Creating of Docker Artifact Reggistry. ======="
    echo

    echo "- Region name used: ${region}"

    echo -n "- Enter the repository name: "
    read repo_name

    echo
    echo "Creating the repository \"${repo_name}\" ..."
    echo
    gcloud artifacts repositories create $repo_name \
        --repository-format=docker \
        --location=$region \
        --disable-vulnerability-scanning

    sleep 2
}


function prepare_local_image() {

    echo
    echo "======= Prepare the image. ======="
    echo
    echo "=== 1. Authenticate your repository for your local Docker Engine. ==="

    echo 
    echo -n "Do you want to authenticate your repository \"${region}-docker.pkg.dev\"? (y or n): "
    read option1

    if [[ $option1 == "y" ]]; then
        gcloud auth configure-docker "${region}-docker.pkg.dev"
    elif [[ $option1 == "n" ]]; then
        echo "Authentication skipped."
    fi

    sleep 2

}


function push_img_to_artif_registry() {

    echo
    echo "======= Push your image to the Artifact registry. ======="
    echo
 
    echo "Please provide the name of your image"
    echo -n "(e.g. REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY_NAME/IMAGE_NAME:TAG): "
    read img_name

    echo "Pushing ..."
    docker push $img_name

    if [[ $? -eq 0 ]]; then
        echo
        echo "Image is pushed."
        echo
    else
        echo
        echo "Image hasn't been pushed."
        echo
    fi

    sleep 2
}



function create_vm() {

    echo
    echo "======= Create a Virtual Machine. ======="
    echo

    echo -n "- Enter the VM name: "
    read vm_name


    echo "- Project name used: ${gcp_project}"
    echo "- Region name used: ${region}"
    zone_name="$region-a"
    echo "- Zone name used: $zone_name"
    echo "- Subnet name used: ${sub_name}"
    echo "- Machine type used: e2-medium"


    echo -n "- Enter the Disk name for the VM: "
    read disk_name


    echo
    echo "Creating VM instance \"${vm_name}\" ..."
    echo

    echo '#!/bin/bash' > startup.sh
    echo "region=\"${region}\"" >> startup.sh
    echo "img_name=\"${img_name}\"" >> startup.sh
    cat startup_script.sh >> startup.sh


    gcloud compute instances create $vm_name \
        --project=$gcp_project \
        --zone=$zone_name \
        --machine-type=e2-medium \
        --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=$sub_name \
        --metadata-from-file=startup-script="./startup.sh" \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --service-account=71936227901-compute@developer.gserviceaccount.com \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
        --tags=http-server,https-server \
        --create-disk=auto-delete=yes,boot=yes,device-name=$disk_name,disk-resource-policy=projects/$gcp_project/regions/$region/resourcePolicies/default-schedule-1,image=projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2504-plucky-amd64-v20250708,mode=rw,size=10,type=pd-balanced \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --reservation-affinity=any 

    
    if [[ $? -eq 0 ]]; then
        echo
        echo "VM is prepared."
        echo
    else
        echo
        echo "VM hasn't been prepared."
        echo
    fi

    echo "Extracting useful data ...."

    ip_addr_pub=$( gcloud compute instances describe $vm_name \
    --project=$gcp_project \
    --zone=$zone_name \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' )
    site_with_app="http://${ip_addr_pub}:8080/"

    count=0
    while [[ $count -ne 9 ]]; do
        
        result=$( curl -Is "${site_with_app}" | head -n 1 | awk -F' ' '{ print $2 }' )
        echo "Waiting for setting up spring-petclinic ..."
        sleep 20
        if [[ $result == '200' ]]; then
            echo "Go to the $site_with_app and use the deployed app."
            break
        fi
        count=$(( $count + 1 ))

    done

    if ! [[ $result == '200' ]]; then
        echo "Something went wrong. Can't reach the app ..."
    fi

    sleep 2

}


function delete_resources() {

    echo
    echo "================================="
    echo
    echo "======= Deleting process ======="
    echo

    resources_list=( "Compute Engine Instance" "Firewall Rules" "Subnet" "VPC" "Docker Artifact Registry" )

    i=0
    while [[ $i -lt ${#resources_list[@]} ]]; do

        echo
        echo -n "Do you want to delete ${resources_list[$i]}? (y or n): "
        read option

        while [[ "$option" != "y" && "$option" != "n" ]]; do
            echo -n "Do you want to delete ${resources_list[$i]}? (y or n): "
            read option
            if ! [[ "$option" != "y" && "$option" != "n" ]]; then
                echo "Please enter "y" for deleting or "n" for opposite."
            fi
        done

        if [[ $option == "y" ]]; then

            if [[ ${resources_list[$i]} ]]

            case "${resources_list[$i]}" in
                "Compute Engine Instance")
                    gcloud compute instances delete $vm_name --zone=$zone_name --project=$gcp_project
                    if [[ $? -gt 0 ]]; then
                        echo "Resource \"${resources_list[$i]}\" hasn't been deleted!"
                    else
                        echo "Resource \"${resources_list[$i]}\" has been deleted"
                    fi
                    ;;

                "Firewall Rules")
                    all_rules=($(gcloud compute firewall-rules list --filter="network:mbnet9" --project=gd-gcp-internship-devops --format="value(name)"))
                    echo "All rules to delete: ${all_rules[@]}"

                    for item in ${all_rules[@]}; do
                        gcloud compute firewall-rules delete ${item} --project=${gcp_project}
                        if [[ $? -gt 0 ]]; then
                            echo "Rule \"${item}\" hasn't been deleted!"
                        else
                            echo "Rule \"${item}\" has been deleted."
                        fi
                    done
                    ;;

                "Subnet")
                    gcloud compute networks subnets delete $sub_name --region=$region --project=$gcp_project
                    if [[ $? -gt 0 ]]; then
                        echo "Resource \"${resources_list[$i]}\" hasn't been deleted!"
                    else
                        echo "Resource \"${resources_list[$i]}\" has been deleted"
                    fi
                    ;;
                
                "Docker Artifact Registry")
                    gcloud artifacts repositories delete $repo_name --location=$region --project=$gcp_project
                    if [[ $? -gt 0 ]]; then
                        echo "Resource \"${resources_list[$i]}\" hasn't been deleted!"
                    else
                        echo "Resource \"${resources_list[$i]}\" has been deleted"
                    fi

                    ;;

                "VPC")
                    gcloud compute networks delete $net_name --project=$gcp_project
                    if [[ $? -gt 0 ]]; then
                        echo "Resource \"${resources_list[$i]}\" hasn't been deleted!"
                    else
                        echo "Resource \"${resources_list[$i]}\" has been deleted"
                    fi
                    ;;

            esac

        fi

        ((i++))

    done



# Start the whole process

check_gcloud
create_vpc_subnet
create_firewall_rules
create_dock_artif_registry
prepare_local_image
push_img_to_artif_registry
create_vm
delete_resources