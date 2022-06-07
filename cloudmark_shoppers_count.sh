#!/bin/bash

# This scripts gathers a number of unique shoppers for cloudmark Licenses. This is for cPanel servers only( any type of cPanel, e.g. VMs, dedicated and Shared)

# The script ssh to each cpanel server and collects all user domain names. Then it checks product status and filters out active domains. Once the active domain data is processed the script then uses TSO WHMCS API to pull email address( does not output email addresses values). Finally, the script sorts the uniq billing email addresses to get a count of cpanel billing users based on number of unique billing email addresses.  The total  number is an estimate.

# Dependencies, jq needs to be installed and access to TSO VPN and cpanel servers. Also product_status and billing_status auth tokens for (Paragon APIs). Removed thsoe from the script for security reasons.

# Prevent manipulation of the input field separator
IFS='
        '
# Ensure that secure search path is inherited by sub-processes
OLDPATH="$PATH"

PATH=/bin:/usr/bin:/usr/sbin
export PATH

# Variables start here

#
# Options for the ssh command.
ssh_user="root"
ssh_options='-o ConnectTimeout=2'
ssh_port="2510"
ssh_auth_error="ssh_auth_error"
time_to_sleep='0.1'
exit_status='0'
api_token_product_status="Please use relevant token"
api_token_billing_status="Please use relevant token"

# Functions start here

# This function ssh to all cpanel servers and collects all domains from them

func_ssh_to_cpanel () {

for server in $(curl -s "https://cdb.prgn.misp.co.uk/?nodelist&fact=shared_cpanel&value=yes&operator=" | jq -r '.[]' )
do 
	
       	# Execute Commands over SSH 
	listuseraccts=$( ssh  $ssh_options -p$ssh_port $ssh_user@$server  ' whmapi1 listaccts | grep -v @ | grep -w domain | cut -d ':' -f2 ')

	# SSH Error Checking
	ssh_exit_status="$?"
	if ((ssh_exit_status))
       	then
	       	exit_status=${ssh_exit_status}
	       	echo "Execution on ${server} failed." 2>&1>> $ssh_auth_error  # Redirect standard OUTPUT AND ERROR to a file
	fi 

	declare -a usr_data

       	usr_data=( ${listuseraccts} ) 


# Output the data

printf '%s\n' ${usr_data[@]}  

done 

}

# This function  check if given domain is active or not

func_get_domain_status () {

while read DOMAIN; do
	{
 	domain_status=$(curl -s "https://deploy.prgn.misp.co.uk/api/v1/whmcs/product_status.php?auth=$api_token_product_status&domain="$DOMAIN"")
	echo ""$DOMAIN" is "$domain_status""
	} &
sleep $time_to_sleep
done < <(func_ssh_to_cpanel)
wait 

}

# This function does simply patter matching to filter out active domains 

	
func_get_active_domains () {

while read LINE; do
       	{
	       	[[ "$LINE" == *active* ]] && echo "$LINE" | awk '{print $1}' 

	} & 
sleep $time_to_sleep 
done < <(func_get_domain_status)
wait
}


# This function gets billing email addresses for ACTIVE_DOMAINS

func_get_contacts () {

while read ACTIVE_DOMAIN; do
       	{
	       	get_contact=$(curl -s "https://deploy.prgn.misp.co.uk/api/v1/whmcs/billing_contact.php?auth=$api_token_billing_status&domain="$ACTIVE_DOMAIN"") 

		declare -a user_contacts
		user_contacts=( $get_contact )

		printf '%s\n'  ${user_contacts[@]}
	} &

sleep $time_to_sleep

done < <(func_get_active_domains)
wait
}

# Body of the  script starts here

# This script does not need super user privileges 

if [[ "${EUID}" -eq 0 ]]
then
	echo 'Do not execute this script as root.' 
	exit 1
fi

# Store the email addresses output in a variable without outputing their values and then get the number of shoppers based on the number of unique billing email addresses 

result=$(func_get_contacts) 

# Counter

check_for_dups=$(printf "$result" | sort | uniq  | sort -n) 

# Counter based on number of line. Needs improving.

count_shoppers=$(printf  "$check_for_dups" | wc -l  ) 

echo "Total shoppers count is :  "${count_shoppers}""

exit 0
