#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MAX_BUF_SIZE 256
#define MAX_NAME_SIZE 20
#define MAX_BRANCHES 20
#define MAX_NODES 100
#define MAX_INFO_SIZE 2048

typedef struct storage_span {
    char name[MAX_NAME_SIZE];
    char *info;
    struct storage_span *successors[MAX_BRANCHES];
    unsigned s_index;
    struct storage_span *predecessors[MAX_BRANCHES];
    unsigned p_index;
    unsigned row_rank;
    unsigned col_width;
} storage_span;

storage_span lt[MAX_NODES];
unsigned lt_index=0;
unsigned lt_rank=0;
storage_span lv[MAX_NODES];
unsigned lv_index=0;
unsigned lv_rank=0;
storage_span vg[MAX_NODES];
unsigned vg_index=0;
unsigned vg_rank=0;
storage_span md[MAX_NODES];
unsigned md_index=0;
unsigned md_rank=0;
storage_span sd[MAX_NODES];
unsigned sd_index=0;
unsigned sd_rank=0;

char *populate_info(char *cmd, storage_span *ss)
{
    char *bufp;
    int len=0;
    FILE *fp;

    if ((ss->info=(char *)malloc(MAX_INFO_SIZE)) == NULL) {
	return NULL;
    }
    if ((fp=popen(cmd, "r")) == NULL) {
	free(ss->info);
	ss->info = NULL;
	return NULL;
    }
    for (bufp=ss->info; fgets(bufp, MAX_INFO_SIZE-len, fp) != NULL; 
	bufp += len) {

	len = strlen(bufp);
	bufp[len-1]='&';
	bufp[len++]='#';
	bufp[len++]='1';
	bufp[len++]='3';
	bufp[len++]=';';
    }
    bufp[len] = '\0';
    return ss->info;
}

char *populate_lt_info(storage_span *ss)
{
    char cmd_buf[MAX_BUF_SIZE];

    sprintf(cmd_buf, "/usr/lib/cgi-bin/getsessioninfo %s 2> /dev/null", 
	ss->name);
    return populate_info(cmd_buf, ss);
}

char *populate_vg_info(storage_span *ss)
{
    char cmd_buf[MAX_BUF_SIZE];

    sprintf(cmd_buf, "vgdisplay /dev/%s 2> /dev/null", ss->name);
    return populate_info(cmd_buf, ss);
}

char *populate_lv_info(storage_span *ss)
{
    char cmd_buf[MAX_BUF_SIZE];

    sprintf(cmd_buf, "lvdisplay /dev/%s/%s 2> /dev/null", 
	ss->successors[0]->name, ss->name);
    return populate_info(cmd_buf, ss);
}

char *populate_md_info(storage_span *ss)
{
    char cmd_buf[MAX_BUF_SIZE];

    sprintf(cmd_buf, "mdadm -D /dev/%s 2> /dev/null", ss->name);
    return populate_info(cmd_buf, ss);
}

char *populate_sd_info(storage_span *ss)
{
    char cmd_buf[MAX_BUF_SIZE];

    sprintf(cmd_buf, 
	"sg_scan -i /dev/%s 2> /dev/null; fdisk -l /dev/%s 2> /dev/null", 
	    ss->name, ss->name);
    return populate_info(cmd_buf, ss);
}

void compute_row_rank(void)
{
    int lti, lvi, vgi, mdi, sdi;
    int vg_colwidth, md_colwidth, succ_width;
    int i;

    for (vgi=0; vgi < vg_index; vgi++) {
	vg_colwidth=0;
	vg[vgi].row_rank = vg_rank++;
	for (lvi=0; lvi < vg[vgi].p_index; lvi++) {
	    vg[vgi].predecessors[lvi]->row_rank = lv_rank++;
	    for (lti=0; lti < vg[vgi].predecessors[lvi]->p_index; lti++) {
		vg[vgi].predecessors[lvi]->predecessors[lti]->row_rank = 
		    lt_rank++;
		vg[vgi].predecessors[lvi]->predecessors[lti]->col_width = 1;
		vg_colwidth++;
	    }
	    vg[vgi].predecessors[lvi]->col_width = 1;
	}
	vg[vgi].col_width=vg_colwidth;
	vg_colwidth=0;
	for (mdi=0; mdi < vg[vgi].s_index; mdi++) {
	    vg[vgi].successors[mdi]->row_rank = md_rank++;
	    for (sdi=0; sdi < vg[vgi].successors[mdi]->s_index; sdi++) {
		vg[vgi].successors[mdi]->successors[sdi]->row_rank = sd_rank++;
		vg[vgi].successors[mdi]->successors[sdi]->col_width = 1;
		vg[vgi].successors[mdi]->col_width++;
		vg_colwidth++;
	    }
	}
	if (vg[vgi].col_width < vg_colwidth) {
	    vg[vgi].col_width=vg_colwidth;
	}
    }
    for (vgi=0; vgi < vg_index; vgi++) {
	vg[vgi].predecessors[vg[vgi].p_index-1]->col_width =
	    vg[vgi].col_width - vg[vgi].p_index + 1;
	vg[vgi].predecessors[vg[vgi].p_index-1]->predecessors[0]->col_width =
	    vg[vgi].col_width - vg[vgi].p_index + 1;

	succ_width=0;
	for (i=0; i < vg[vgi].s_index; i++) {
	    succ_width += vg[vgi].successors[i]->col_width;
	}
	vg[vgi].successors[vg[vgi].s_index-1]->col_width +=
	    (vg[vgi].col_width - succ_width);
    }
    for (mdi=0; mdi < md_index; mdi++) {
	md[mdi].successors[md[mdi].s_index-1]->col_width =
	    md[mdi].col_width - md[mdi].s_index + 1;
    }
}

void print_bfs_span(void)
{
    unsigned lti, lvi, vgi, mdi, sdi;
    unsigned i;

    printf("<table border=1 width=\"750\" style=\"font-size:12\">\n");
    printf("<tr>\n");
    printf("<td style=\"background:aqua;font-size:12\" "\
	"onclick=\"show_iscsi_forms_table();\""\
	"title=\"Click here to get iSCSI Actions Menu\">"\
	"iSCSI Target LUN</td>\n");
    for (lti=0; lti < lt_rank; lti++) {
	for (i=0; i < lt_index; i++) {
	    if (lt[i].row_rank == lti) {
		printf("<td colspan=\"%d\" align=\"center\" "\
		    "style=\"background:aqua;font-size:12\" "\
		    "title=\"%s\">%s</td>\n", 
		lt[i].col_width, 
		(strncmp(lt[i].name, "&nbsp;", 6)?populate_lt_info(&lt[i]):""),
		lt[i].name);
	    }
	}
    }
    printf("</tr>\n");
    printf("<tr>\n");
    printf("<td style=\"background:yellow;font-size:12\" "\
	"onclick=\"show_lvm_forms_table();\" "\
	"title=\"Click here to get Logical Volumes Actions Menu\"> "\
	"Logical Volumes</td>\n");
    for (lvi=0; lvi < lv_rank; lvi++) {
	for (i=0; i < lv_index; i++) {
	    if (lv[i].row_rank == lvi) {
		printf("<td colspan=\"%d\" align=\"center\" "\
		    "style=\"background:yellow;font-size:12\" "\
		    "title=\"%s\">%s</td>\n",
		lv[i].col_width, 
		(strncmp(lv[i].name, "&nbsp;", 6)?populate_lv_info(&lv[i]):""),
		lv[i].name);
	    }
	}
    }
    printf("</tr>\n");
    printf("<tr>\n");
    printf("<td style=\"background:greenyellow;font-size:12\" "\
	"onclick=\"show_vg_forms_table();\" "\
	"title=\"Click here to get Volume Groups Actions Menu\">"\
	"Volume Groups</td>\n");
    for (vgi=0; vgi < vg_rank; vgi++) {
	for (i=0; i < vg_index; i++) {
	    if (vg[i].row_rank == vgi) {
		printf("<td colspan=\"%d\" align=\"center\" "\
		    "style=\"background:greenyellow;font-size:12\" "\
		    "title=\"%s\">%s</td>\n", 
		vg[i].col_width, 
		(strncmp(vg[i].name, "&nbsp;", 6)?populate_vg_info(&vg[i]):""),
		vg[i].name);
	    }
	}
    }
    printf("</tr>\n");
    printf("<tr>\n");
    printf("<td style=\"background:pink;font-size:12\" "\
	"onclick=\"show_raid_forms_table();\" "\
	"title=\"Click here to get RAID Actions Menu\">RAID</td>\n");
    for (mdi=0; mdi < md_rank; mdi++) {
	for (i=0; i < md_index; i++) {
	    if (md[i].row_rank == mdi) {
		printf("<td colspan=\"%d\" align=\"center\" "\
		    "style=\"background:pink;font-size:12\" "\
		    "title=\"%s\">%s</td>\n", 
		md[i].col_width, 
		(strncmp(md[i].name, "&nbsp;", 6)?populate_md_info(&md[i]):""),
		md[i].name);
	    }
	}
    }
    printf("</tr>\n");
    printf("<tr>\n");
    printf("<td style=\"background:sandybrown;font-size:12\" "\
	"onclick=\"show_wizard_forms_table();\" "\
	"title=\"Click here to get Storage Wizard Menu\">Disks</td>\n");
    for (sdi=0; sdi < sd_rank; sdi++) {
	for (i=0; i < sd_index; i++) {
	    if (sd[i].row_rank == sdi) {
		printf("<td colspan=\"%d\" align=\"center\" "\
		    "style=\"background:sandybrown;font-size:12\" "\
		    "title=\"%s\">%s</td>\n", 
		sd[i].col_width, 
		(strncmp(sd[i].name, "&nbsp;", 6)?populate_sd_info(&sd[i]):""),
		sd[i].name);
	    }
	}
    }
    printf("</tr>\n");
    printf("</table>\n");
}

void lt_parser(char *buf)
{
    char *str1=NULL, *str2=NULL, *str3=NULL;
    unsigned i, len;
    unsigned vg_found_flag=0;

    str1 = buf;
    len = strlen(buf);
    for (i=0; i < len; i++) {
	if (buf[i] == ' ') {
	    buf[i] = '\0';
	    if (str1[0] == 'v' && !str3) {
		str3 = &buf[i+1];
	    } else {
		str2 = &buf[i+1];
		break;
	    }
	}
    }
    strncpy(lt[lt_index].name, str2, MAX_NAME_SIZE);
    switch (str1[0])
    {
	case 'v':
	    strncpy(lv[lv_index].name, str3, MAX_NAME_SIZE);
	    lt[lt_index].successors[0] = &lv[lv_index];
	    lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	    lv[lv_index].p_index++;
	    for (i = 0; i < vg_index; i++) {
		if (!strncmp(vg[i].name, str1, MAX_NAME_SIZE)) {
		    vg_found_flag=1;
		    break;
		}
	    }
	    if (!vg_found_flag) {
		strncpy(vg[vg_index].name, str1, MAX_NAME_SIZE);
		lv[lv_index].successors[0] = &vg[vg_index];
		vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
		vg[vg_index].p_index++;
		vg_index++;
	    } else {
		lv[lv_index].successors[0] = &vg[i];
		vg[i].predecessors[vg[i].p_index] = &lv[lv_index];
		vg[i].p_index++;
	    }
	    lv[lv_index].s_index++;
	    lv_index++;
	    break;
	case 'm':
	    strncpy(lv[lv_index].name,"&nbsp;", MAX_NAME_SIZE);
	    lt[lt_index].successors[0] = &lv[lv_index];
	    lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	    lv[lv_index].p_index++;
	    strncpy(vg[vg_index].name,"&nbsp;", MAX_NAME_SIZE);
	    lv[lv_index].successors[0] = &vg[vg_index];
	    lv[lv_index].s_index++;
	    vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
	    vg[vg_index].p_index++;
	    strncpy(md[md_index].name, str1, MAX_NAME_SIZE);
	    vg[vg_index].successors[0] = &md[md_index];
	    vg[vg_index].s_index++;
	    md[md_index].predecessors[md[md_index].p_index] = &vg[vg_index];
	    md[md_index].p_index++;
	    lv_index++;
	    md_index++;
	    vg_index++;
	    break;
	case 's':
	    strncpy(lv[lv_index].name,"&nbsp;", MAX_NAME_SIZE);
	    lt[lt_index].successors[0] = &lv[lv_index];
	    lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	    lv[lv_index].p_index++;
	    strncpy(vg[vg_index].name,"&nbsp;", MAX_NAME_SIZE);
	    lv[lv_index].successors[0] = &vg[vg_index];
	    lv[lv_index].s_index++;
	    vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
	    vg[vg_index].p_index++;
	    strncpy(md[md_index].name, "&nbsp;", MAX_NAME_SIZE);
	    vg[vg_index].successors[0] = &md[md_index];
	    vg[vg_index].s_index++;
	    md[md_index].predecessors[md[md_index].p_index] = &vg[vg_index];
	    md[md_index].p_index++;
	    strncpy(sd[sd_index].name, str1, MAX_NAME_SIZE);
	    md[md_index].successors[0] = &sd[sd_index];
	    md[md_index].s_index++;
	    sd[sd_index].predecessors[sd[sd_index].p_index] = &md[md_index];
	    sd[sd_index].p_index++;
	    sd_index++;
	    lv_index++;
	    md_index++;
	    vg_index++;
	    break;
    }
    lt[lt_index].s_index++;
    lt_index++;
}

void lv_parser(char *buf)
{
    char *str1=NULL, *str2=NULL;
    unsigned i, len;
    unsigned lv_found_flag=0;
    unsigned vg_found_flag=0;

    str1 = buf;
    len = strlen(buf);
    for (i=0; i < len; i++) {
	if (buf[i] == ' ') {
	    buf[i] = '\0';
	    str2 = &buf[i+1];
	    break;
	}
    }
    for (i=0; i < lv_index; i++) {
	if (!strncmp(lv[i].name, str2, MAX_NAME_SIZE) && 
	    lv[i].successors[0] &&
	    !strncmp(lv[i].successors[0]->name, 
		str1, MAX_NAME_SIZE)) {

	    lv_found_flag=1;
	    break;
	}
    }
    if (!lv_found_flag) {
	strncpy(lt[lt_index].name, "&nbsp;", MAX_NAME_SIZE);
	strncpy(lv[lv_index].name, str2, MAX_NAME_SIZE);
	lt[lt_index].successors[0] = &lv[lv_index];
	lt[lt_index].s_index++;
	lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	lv[lv_index].p_index++;
	lt_index++;
	for (i = 0; i < vg_index; i++) {
	    if (!strncmp(vg[i].name, str1, MAX_NAME_SIZE)) {
		vg_found_flag=1;
		break;
	    }
	}
	if (!vg_found_flag) {
	    strncpy(vg[vg_index].name, str1, MAX_NAME_SIZE);
	    lv[lv_index].successors[0] = &vg[vg_index];
	    vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
	    vg[vg_index].p_index++;
	    vg_index++;
	} else {
	    lv[lv_index].successors[0] = &vg[i];
	    vg[i].predecessors[vg[i].p_index] = &lv[lv_index];
	    vg[i].p_index++;
	}
	lv[lv_index].s_index++;
	lv_index++;
    }
}

void vg_parser(char *buf)
{
    char *str1=NULL, *str2=NULL;
    unsigned i, len;
    unsigned vg_found_flag=0;

    str1 = buf;
    len = strlen(buf);
    for (i=0; i < len; i++) {
	if (buf[i] == ' ') {
	    buf[i] = '\0';
	    str2 = &buf[i+1];
	    break;
	}
    }
    for (i = 0; i < vg_index; i++) {
	if (!strncmp(vg[i].name, str1, MAX_NAME_SIZE)) {
	    vg_found_flag=1;
	    break;
	}
    }
    if (!vg_found_flag) {
	strncpy(lt[lt_index].name, "&nbsp;", MAX_NAME_SIZE);
	strncpy(lv[lv_index].name, "&nbsp;", MAX_NAME_SIZE);
	lt[lt_index].successors[0] = &lv[lv_index];
	lt[lt_index].s_index++;
	lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	lv[lv_index].p_index++;
	lt_index++;
	strncpy(vg[vg_index].name, str1, MAX_NAME_SIZE);
	lv[lv_index].successors[0] = &vg[vg_index];
	lv[lv_index].s_index++;
	vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
	vg[vg_index].p_index++;
	lv_index++;
	i = vg_index;
	vg_index++;
    } 
    switch(str2[0]) {
	case 'm':
	    strncpy(md[md_index].name, str2, MAX_NAME_SIZE);
	    vg[i].successors[vg[i].s_index] = &md[md_index];
	    vg[i].s_index++;
	    md[md_index].predecessors[md[md_index].p_index] = &vg[i];
	    md[md_index].p_index++;
	    md_index++;
	    break;
	case 's':
	    strncpy(md[md_index].name, "&nbsp;", MAX_NAME_SIZE);
	    vg[i].successors[vg[i].s_index] = &md[md_index];
	    vg[i].s_index++;
	    md[md_index].predecessors[md[md_index].p_index] = &vg[i];
	    md[md_index].p_index++;
	    strncpy(sd[sd_index].name, str2, MAX_NAME_SIZE);
	    md[md_index].successors[md[md_index].s_index] = &sd[sd_index];
	    md[md_index].s_index++;
	    sd[sd_index].predecessors[sd[sd_index].s_index] = &md[md_index];
	    sd[sd_index].p_index++;
	    md_index++;
	    sd_index++;
	    break;
    }
}

void md_parser(char *buf)
{
    char *str1=NULL, *str2=NULL;
    unsigned i, len;
    unsigned md_found_flag=0;

    str1 = buf;
    len = strlen(buf);
    for (i=0; i < len; i++) {
	if (buf[i] == ' ') {
	    buf[i] = '\0';
	    str2 = &buf[i+1];
	    break;
	}
    }
    for (i = 0; i < md_index; i++) {
	if (!strncmp(md[i].name, str1, MAX_NAME_SIZE)) {
	    md_found_flag=1;
	    break;
	}
    }
    if (!md_found_flag) {
	strncpy(lt[lt_index].name, "&nbsp;", MAX_NAME_SIZE);
	strncpy(lv[lv_index].name, "&nbsp;", MAX_NAME_SIZE);
	lt[lt_index].successors[0] = &lv[lv_index];
	lt[lt_index].s_index++;
	lv[lv_index].predecessors[lv[lv_index].p_index] = &lt[lt_index];
	lv[lv_index].p_index++;
	lt_index++;
	strncpy(vg[vg_index].name, "&nbsp;", MAX_NAME_SIZE);
	lv[lv_index].successors[0] = &vg[vg_index];
	lv[lv_index].s_index++;
	vg[vg_index].predecessors[vg[vg_index].p_index] = &lv[lv_index];
	vg[vg_index].p_index++;
	lv_index++;
	strncpy(md[md_index].name, str1, MAX_NAME_SIZE);
	vg[vg_index].successors[vg[vg_index].s_index] = &md[md_index];
	vg[vg_index].s_index++;
	md[md_index].predecessors[md[md_index].p_index] = &vg[vg_index];
	md[md_index].p_index++;
	vg_index++;
	i = md_index;
	md_index++;
    }
    strncpy(sd[sd_index].name, str2, MAX_NAME_SIZE);
    md[i].successors[md[i].s_index] = &sd[sd_index];
    md[i].s_index++;
    sd[sd_index].predecessors[sd[sd_index].p_index] = &md[i];
    sd[sd_index].p_index++;
    sd_index++;
}

void do_command(char *cmd, void (*parser)(char *))
{
    FILE *fp;
    unsigned char buf[MAX_BUF_SIZE];

    if ((fp=popen(cmd, "r")) == NULL) {
	fprintf(stderr, "Error: popen for pvs failed\n");
    }
    while (fgets(buf, MAX_BUF_SIZE, fp) != NULL) {
	buf[strlen(buf)-1]='\0';
	parser(buf);
    }
}

main()
{
    int i;

    do_command("/usr/lib/cgi-bin/getluntarginfo", lt_parser);
    do_command("/usr/lib/cgi-bin/getlvinfo", lv_parser);
    do_command("/usr/lib/cgi-bin/getpvinfo", vg_parser);
    do_command("/usr/lib/cgi-bin/getmdinfo", md_parser);

    compute_row_rank();
    print_bfs_span();
}
