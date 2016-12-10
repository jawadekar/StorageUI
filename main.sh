#!/bin/bash
export PATH=$PATH:/sbin:/usr/sbin
. ./functions.sh
display_cgi_header
refresh_global_state
${UIACTION}
refresh_global_state
load_tabs_script
jscript_forms_table
display_main_header
display_storage_state_tabs
display_forms_tabs
display_charts_tabs
display_last_action_message
