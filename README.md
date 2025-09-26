###########################################################################################################################
chennai

 ansible-playbook /opt/premd/playbook_security_report3.yml
 ansible chennai -a "cat /tmp/security_report.txt" >  /mnt/hamburg/logs/chennai/chennai_coc_security_report_`date -I`.txt
 python /mnt/hamburg/scripts/chennai/chennai_table_script3.py

#############################################################################################################################
chennai


ansible-playbook /opt/premd/playbook_security_report3-1.yml
ansible chennai -a "cat /tmp/security_audit1.txt" >  /mnt/hamburg/logs/chennai/chennai_coc_security_audit1_`date -I`.txt
python /mnt/hamburg/scripts/chennai/chennai_table_script3-2.py

 ############################################################################################################################

###########################################################################################################################
Kanchi

 ansible-playbook /opt/premd/kanchi_playbook_security_report3.yml
 ansible kanchi -a "cat /tmp/security_report.txt" >  /mnt/hamburg/logs/kanchi/kanchi_coc_security_report_`date -I`.txt
 python /mnt/hamburg/scripts/kanchi/kanchi_table_script3.py

#############################################################################################################################
Kanchi


ansible-playbook /opt/premd/kanchi_playbook_security_report3-1.yml
ansible kanchi -a "cat /tmp/security_audit1.txt" >  /mnt/hamburg/logs/kanchi/kanchi_coc_security_audit1_`date -I`.txt
python /mnt/hamburg/scripts/kanchi/kanchi_table_script3-2.py

 ############################################################################################################################

DB backup script : 

Single DB backup 
Multiple DB backup 
Upload the 5 DB to the Other location.
DB Restoreation -> DB zip Password open -> DB_Extraction > DB_Health_check --> update the status in the Webreport - > DB Restoration logs will store in /var/log/dbupload.logs








 
